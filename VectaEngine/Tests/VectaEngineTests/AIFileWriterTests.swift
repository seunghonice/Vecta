import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func documentWithRedRect() -> VectorDocument {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  let rect = PathNode(
    path: .rectangle(CGRect(x: 20, y: 20, width: 100, height: 100)),
    style: Style(fill: .color(RGBA(red: 1, green: 0, blue: 0))))
  document.layers[0].nodes = [.path(rect)]
  return document
}

@Test func outputIsValidPDFWithArtboardMediaBox() throws {
  let data = try AIFileWriter.data(for: documentWithRedRect())
  #expect(data.starts(with: Data("%PDF-".utf8)))
  let provider = CGDataProvider(data: data as CFData)!
  let pdf = CGPDFDocument(provider)
  #expect(pdf != nil)
  #expect(pdf!.numberOfPages == 1)
  let mediaBox = pdf!.page(at: 1)!.getBoxRect(.mediaBox)
  #expect(mediaBox == CGRect(x: 0, y: 0, width: 200, height: 200))
}

@Test func outputContainsExtractableSceneJSON() throws {
  let document = documentWithRedRect()
  let data = try AIFileWriter.data(for: document)
  let extracted = try NativeScenePayload.extract(from: data)
  #expect(extracted == document)
}

@Test func pdfPageRendersShapeAtModelPosition() throws {
  let data = try AIFileWriter.data(for: documentWithRedRect())
  let pdf = CGPDFDocument(CGDataProvider(data: data as CFData)!)!
  let page = pdf.page(at: 1)!
  let context = CGContext(
    data: nil, width: 200, height: 200,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.drawPDFPage(page)
  // 사각형(20,20,100×100) 내부 픽셀 (70,70) — 플립 좌표 검증
  let inside = pixelColor(x: 70, y: 70, in: context)
  #expect(inside.red == 255)
  let outside = pixelColor(x: 70, y: 180, in: context)
  #expect(outside.alpha == 0)
}

@Test func imageNodeRoundTripsThroughNativePayload() throws {
  // 작은 PNG ImageNode가 .ai 저장→재열기로 100% 복원되는지 (JSON 임베드)
  let png = makeSmallPNG()
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [
    .image(
      ImageNode(
        imageData: png, frame: CGRect(x: 0, y: 0, width: 1, height: 1),
        transform: Transform2D(CGAffineTransform(scaleX: 100, y: 100))))
  ]
  let data = try AIFileWriter.data(for: document)
  let result = try AIFileReader.read(from: data)
  #expect(result.document == document)
  #expect(result.report.isEmpty)
  guard case .image(let restored) = result.document.layers[0].nodes[0] else {
    Issue.record("이미지 노드가 아님")
    return
  }
  #expect(restored.imageData == png)
}

/// 1×1 빨강 PNG (테스트용 최소 이미지).
private func makeSmallPNG() -> Data {
  let context = CGContext(
    data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
  return CGImageCoding.pngData(from: context.makeImage()!)!
}
