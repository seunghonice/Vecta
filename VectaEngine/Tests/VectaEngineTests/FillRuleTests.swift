import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 동일 방향 사각형 2개 (도넛) — winding은 전체 채움, evenOdd는 구멍.
private func donutNode(fillRule: FillRule) -> PathNode {
  let outer = BezierPath.rectangle(CGRect(x: 20, y: 20, width: 160, height: 160))
  let inner = BezierPath.rectangle(CGRect(x: 70, y: 70, width: 60, height: 60))
  let donut = BezierPath(subpaths: outer.subpaths + inner.subpaths)
  return PathNode(
    path: donut, style: Style(fill: .color(RGBA(red: 1, green: 0, blue: 0))),
    fillRule: fillRule)
}

@Test func evenOddFillRendersHole() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [.path(donutNode(fillRule: .evenOdd))]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  #expect(pixelColor(x: 40, y: 100, in: context).red > 230)  // 링
  #expect(pixelColor(x: 100, y: 100, in: context).alpha == 0)  // 구멍
}

@Test func windingFillHasNoHole() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [.path(donutNode(fillRule: .winding))]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  #expect(pixelColor(x: 100, y: 100, in: context).red > 230)  // 동일 방향 → 채워짐
}

@Test func evenOddHitTestMissesHole() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  let node = donutNode(fillRule: .evenOdd)
  document.layers[0].nodes = [.path(node)]
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 40, y: 100), in: document, tolerance: 0)
      == node.id)
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 100, y: 100), in: document, tolerance: 0)
      == nil)
}

@Test func pathNodeDecodesLegacyJSONWithWindingDefault() throws {
  // fillRule 키가 없는 구버전 JSON — winding으로 디코드 (저장 파일 호환)
  let legacy = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
    style: Style(fill: .color(.black)))
  var json =
    try JSONSerialization.jsonObject(
      with: JSONEncoder().encode(legacy)) as! [String: Any]
  json.removeValue(forKey: "fillRule")
  let stripped = try JSONSerialization.data(withJSONObject: json)
  let decoded = try JSONDecoder().decode(PathNode.self, from: stripped)
  #expect(decoded.fillRule == .winding)
  #expect(decoded.id == legacy.id)
}

@Test func fillRuleRoundTripsThroughCodable() throws {
  let node = donutNode(fillRule: .evenOdd)
  let decoded = try JSONDecoder().decode(
    PathNode.self, from: JSONEncoder().encode(node))
  #expect(decoded.fillRule == .evenOdd)
  #expect(decoded == node)
}
