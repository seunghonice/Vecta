import CoreGraphics
import Testing

@testable import VoidaEngine

private func documentWithRedRect() -> VectorDocument {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  let red = Style(fill: .color(RGBA(red: 1, green: 0, blue: 0)))
  let rect = PathNode(
    path: .rectangle(CGRect(x: 20, y: 20, width: 100, height: 100)),
    style: red)
  document.layers[0].nodes = [.path(rect)]
  return document
}

@Test func rendersFilledRectAtModelCoordinates() {
  let context = renderToBitmap(
    documentWithRedRect(), size: CGSize(width: 200, height: 200))
  let inside = pixelColor(x: 70, y: 70, in: context)
  #expect(inside.red == 255)
  #expect(inside.green == 0)
  #expect(inside.alpha == 255)
  // 모델 y=20 위쪽(top)은 비어 있어야 한다 — 좌표 플립 검증
  let above = pixelColor(x: 70, y: 5, in: context)
  #expect(above.alpha == 0)
  let below = pixelColor(x: 70, y: 180, in: context)
  #expect(below.alpha == 0)
}

@Test func hiddenLayerIsNotRendered() {
  var document = documentWithRedRect()
  document.layers[0].isVisible = false
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  #expect(pixelColor(x: 70, y: 70, in: context).alpha == 0)
}

@Test func nodeTransformIsApplied() {
  var document = documentWithRedRect()
  guard case .path(var node) = document.layers[0].nodes[0] else {
    Issue.record("path 노드가 아님")
    return
  }
  node.transform = Transform2D(CGAffineTransform(translationX: 60, y: 0))
  document.layers[0].nodes[0] = .path(node)
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  // 원래 (20…120) → 이동 후 (80…180)
  #expect(pixelColor(x: 70, y: 70, in: context).alpha == 0)
  #expect(pixelColor(x: 170, y: 70, in: context).red == 255)
}

@Test func strokeOnlyPathRendersOutline() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  let outlined = PathNode(
    path: .rectangle(CGRect(x: 50, y: 50, width: 100, height: 100)),
    style: Style(stroke: Stroke(paint: .black, width: 4)))
  document.layers[0].nodes = [.path(outlined)]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  #expect(pixelColor(x: 100, y: 50, in: context).alpha == 255)  // 윗변 위
  #expect(pixelColor(x: 100, y: 100, in: context).alpha == 0)  // 중앙은 비어 있음
}
