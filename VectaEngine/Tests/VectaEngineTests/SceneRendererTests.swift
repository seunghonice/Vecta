import CoreGraphics
import Testing

@testable import VectaEngine

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
  #expect(pixelColor(x: 100, y: 50, in: context).alpha == 255)  // 윗변 중앙 (4pt stroke center)
  #expect(pixelColor(x: 100, y: 100, in: context).alpha == 0)  // 중앙은 비어 있음
}

@Test func nodeOpacityAppliesToWholeNode() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  let translucent = PathNode(
    path: .rectangle(CGRect(x: 20, y: 20, width: 100, height: 100)),
    style: Style(fill: .color(RGBA(red: 1, green: 0, blue: 0)), opacity: 0.5))
  document.layers[0].nodes = [.path(translucent)]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  let inside = pixelColor(x: 70, y: 70, in: context)
  // premultipliedLast: alpha ≈ 0.5 → 약 127±8
  #expect(inside.alpha > 119)
  #expect(inside.alpha < 136)
}

// MARK: - 그라디언트 (M3)

private func documentWithGradientRect(_ fill: Paint) -> VectorDocument {
  var document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 80, height: 80)),
    style: Style(fill: fill))
  document.layers[0].nodes = [.path(node)]
  return document
}

private let redToBlue = [
  GradientStop(location: 0, color: RGBA(red: 1, green: 0, blue: 0)),
  GradientStop(location: 1, color: RGBA(red: 0, green: 0, blue: 1)),
]

@Test func linearGradientInterpolatesAndClipsToPath() {
  let gradient = Gradient(
    stops: redToBlue, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  let left = pixelColor(x: 12, y: 50, in: context)
  #expect(left.red > 230)
  #expect(left.blue < 25)
  let right = pixelColor(x: 88, y: 50, in: context)
  #expect(right.blue > 230)
  #expect(right.red < 25)
  let middle = pixelColor(x: 50, y: 50, in: context)
  #expect(middle.red > 100 && middle.red < 160)
  #expect(middle.blue > 100 && middle.blue < 160)
  // 패스 밖(그라디언트 연장선 위)은 클립으로 비어 있어야 한다
  #expect(pixelColor(x: 5, y: 50, in: context).alpha == 0)
}

@Test func linearGradientExtendsBeyondEndpoints() {
  // 선분이 패스보다 짧아도 양 끝 색으로 연장된다 (drawsBefore/AfterStartLocation)
  let gradient = Gradient(
    stops: redToBlue, start: CGPoint(x: 40, y: 50), end: CGPoint(x: 60, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 12, y: 50, in: context).red > 230)
  #expect(pixelColor(x: 88, y: 50, in: context).blue > 230)
}

@Test func radialGradientShadesFromCenter() {
  // start = 중심, end = 원주 위 한 점 (반지름 40)
  let whiteToBlack = [
    GradientStop(location: 0, color: .white),
    GradientStop(location: 1, color: .black),
  ]
  let gradient = Gradient(
    stops: whiteToBlack, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 90, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.radialGradient(gradient)), size: CGSize(width: 100, height: 100))
  let center = pixelColor(x: 50, y: 50, in: context)
  #expect(center.red > 230)
  let nearEdge = pixelColor(x: 88, y: 50, in: context)
  #expect(nearEdge.red < 40)
}

@Test func singleStopGradientRendersSolid() {
  let gradient = Gradient(
    stops: [GradientStop(location: 0, color: RGBA(red: 0, green: 1, blue: 0))],
    start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  let inside = pixelColor(x: 50, y: 50, in: context)
  #expect(inside.green > 230)
  #expect(inside.red < 25)
}

@Test func degenerateGradientLineRendersFirstStopSolid() {
  // start == end (길이 0 선분) → 첫 스톱 단색
  let gradient = Gradient(
    stops: redToBlue, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 50, y: 50, in: context).red > 230)
}

@Test func emptyStopsGradientDrawsNothing() {
  let gradient = Gradient(stops: [], start: .zero, end: CGPoint(x: 100, y: 0))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 50, y: 50, in: context).alpha == 0)
}
