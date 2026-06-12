import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func textNode(
  _ string: String, at position: CGPoint, size: Double = 40
) -> TextNode {
  TextNode(
    string: string, fontName: "Helvetica", fontSize: size,
    fill: .color(RGBA(red: 0, green: 0, blue: 0)), position: position,
    transform: .identity)
}

@Test func advanceWidthIsPositiveForNonEmpty() {
  let width = TextRendering.advanceWidth(
    string: "Hello", fontName: "Helvetica", fontSize: 12)
  #expect(width > 0)
  let wider = TextRendering.advanceWidth(
    string: "Hello World", fontName: "Helvetica", fontSize: 12)
  #expect(wider > width)
}

@Test func rendersTextPixels() {
  // 큰 검정 텍스트를 그리면 일부 픽셀이 칠해진다
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 100))
  document.layers[0].nodes = [.text(textNode("HELLO", at: CGPoint(x: 10, y: 50)))]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 100))
  // 텍스트 영역에 칠해진 픽셀이 하나라도 있어야 한다
  var painted = false
  for x in stride(from: 10, to: 190, by: 5) {
    for y in stride(from: 20, to: 60, by: 5) where pixelColor(x: x, y: y, in: context).alpha > 0 {
      painted = true
    }
  }
  #expect(painted)
}

@Test func textBoundsAreNonZero() {
  let node = Node.text(textNode("Text", at: CGPoint(x: 20, y: 30)))
  let bounds = node.bounds
  #expect(bounds.width > 0)
  #expect(bounds.height > 0)
  // position 근처에 있다
  #expect(abs(bounds.minX - 20) < 30)
}

@Test func textHitTestInsideBounds() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 100))
  let node = textNode("Hit", at: CGPoint(x: 50, y: 50))
  document.layers[0].nodes = [.text(node)]
  // 텍스트 바운드 중심 근처 클릭은 히트
  let bounds = Node.text(node).bounds
  let center = CGPoint(x: bounds.midX, y: bounds.midY)
  #expect(
    HitTesting.topmostNodeID(at: center, in: document, tolerance: 2) == node.id)
  // 멀리 떨어진 점은 미스
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 190, y: 95), in: document, tolerance: 2)
      == nil)
}
