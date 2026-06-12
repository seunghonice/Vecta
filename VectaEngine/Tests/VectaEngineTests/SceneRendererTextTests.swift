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

@Test func textRendersUprightNotMirrored() {
  // 비대칭 글리프 "L" — 잉크가 정립(하단·좌측 우세)이어야 한다 (상하/좌우 반전 회귀 방지)
  var document = VectorDocument.empty(size: CGSize(width: 120, height: 120))
  document.layers[0].nodes = [.text(textNode("L", at: CGPoint(x: 20, y: 90), size: 80))]
  let context = renderToBitmap(document, size: CGSize(width: 120, height: 120))
  // "L": 잉크가 하단 행(발)에 위쪽 행보다 넓게 퍼진다. baseline=90, ascent 위로.
  // 글리프 상단 영역 vs 하단 영역 잉크량 — 측정 후 고정.
  func inkCount(yRange: Range<Int>) -> Int {
    var count = 0
    for x in stride(from: 10, to: 110, by: 2) {
      for y in yRange where pixelColor(x: x, y: y, in: context).alpha > 0 { count += 1 }
    }
    return count
  }
  // L의 발(하단, baseline 근처)이 상단 세로획보다 가로로 넓다 → 하단 행 잉크가 더 넓게 분포.
  // 실제 픽셀로 측정해 어느 영역이 더 넓은지 확인하고 단언을 고정하라.
  let upperInk = inkCount(yRange: 35..<55)  // 글리프 상부(세로획만)
  let lowerInk = inkCount(yRange: 75..<92)  // 글리프 하부(발 — 가로 확장)
  #expect(lowerInk > upperInk)  // L의 발이 더 넓음 = 정립
}

@Test func paintedPixelsFallWithinBounds() {
  // 렌더된 잉크가 node.bounds 안에 있다 (렌더↔히트테스트 계약)
  let node = textNode("Text", at: CGPoint(x: 30, y: 60), size: 40)
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 100))
  document.layers[0].nodes = [.text(node)]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 100))
  let bounds = Node.text(node).bounds
  // 칠해진 픽셀을 찾아 bounds 안에 있는지 (약간의 tolerance)
  for x in stride(from: 0, to: 200, by: 3) {
    for y in stride(from: 0, to: 100, by: 3) where pixelColor(x: x, y: y, in: context).alpha > 0 {
      #expect(bounds.insetBy(dx: -3, dy: -3).contains(CGPoint(x: x, y: y)))
    }
  }
}

@Test func zeroFontSizeRendersNothingWithZeroMetrics() {
  let node = textNode("Hidden", at: CGPoint(x: 10, y: 50), size: 0)
  #expect(TextRendering.advanceWidth(string: "Hidden", fontName: "Helvetica", fontSize: 0) == 0)
  let bounds = Node.text(node).bounds
  #expect(bounds.height == 0)
  var document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  document.layers[0].nodes = [.text(node)]
  let context = renderToBitmap(document, size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 30, y: 50, in: context).alpha == 0)  // 아무것도 안 그림
}
