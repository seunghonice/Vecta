import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 상단 빨강 / 하단 파랑 2×2 PNG (top row = 빨강) — 상하 방향 검증용.
private func topRedBottomBluePNG() -> Data {
  let width = 2
  let height = 2
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  // CG는 y-up: 위쪽(y=1) 행을 먼저 칠하면 이미지 상단이 됨.
  context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
  context.fill(CGRect(x: 0, y: 1, width: 2, height: 1))  // CG 상단 = 이미지 첫 행
  context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))  // CG 하단 = 이미지 마지막 행
  let cgImage = context.makeImage()!
  return CGImageCoding.pngData(from: cgImage)!
}

@Test func pngRoundTripsThroughCGImageCoding() {
  let png = topRedBottomBluePNG()
  let decoded = CGImageCoding.cgImage(fromData: png)
  #expect(decoded != nil)
  #expect(decoded?.width == 2)
  #expect(decoded?.height == 2)
}

@Test func rendersImageUprightInModelSpace() {
  // ImageNode를 모델 (0,0)~(100,100)에 배치 — 모델 상단(y 작음)이 빨강이어야 한다.
  let png = topRedBottomBluePNG()
  // frame=unit square, transform = 모델 (0,0,100,100)으로 매핑
  let node = ImageNode(
    imageData: png, frame: CGRect(x: 0, y: 0, width: 1, height: 1),
    transform: Transform2D(CGAffineTransform(scaleX: 100, y: 100)))
  var document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  document.layers[0].nodes = [.image(node)]
  let context = renderToBitmap(document, size: CGSize(width: 100, height: 100))
  // 모델 상단(y=25)은 빨강, 하단(y=75)은 파랑 (이미지 첫 행이 모델 위)
  let top = pixelColor(x: 50, y: 25, in: context)
  #expect(top.red > 200)
  #expect(top.blue < 60)
  let bottom = pixelColor(x: 50, y: 75, in: context)
  #expect(bottom.blue > 200)
  #expect(bottom.red < 60)
}

@Test func corruptImageDataRendersNothing() {
  let node = ImageNode(
    imageData: Data("not a png".utf8),
    frame: CGRect(x: 0, y: 0, width: 1, height: 1),
    transform: Transform2D(CGAffineTransform(scaleX: 100, y: 100)))
  var document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  document.layers[0].nodes = [.image(node)]
  let context = renderToBitmap(document, size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 50, y: 50, in: context).alpha == 0)  // 빈 캔버스
}
