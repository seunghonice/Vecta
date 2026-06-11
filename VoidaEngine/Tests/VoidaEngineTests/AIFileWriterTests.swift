import CoreGraphics
import Foundation
import Testing

@testable import VoidaEngine

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
  // 모델 top-left (70,70)은 PDF(bottom-left) 렌더 후에도 비트맵 row 70
  let inside = pixelColor(x: 70, y: 70, in: context)
  #expect(inside.red == 255)
  let outside = pixelColor(x: 70, y: 180, in: context)
  #expect(outside.alpha == 0)
}
