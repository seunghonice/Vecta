import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@Test func writerOutputRoundTripsThroughReader() throws {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 200))
  document.layers[0].nodes = [
    .path(
      PathNode(
        path: .ellipse(in: CGRect(x: 10, y: 10, width: 80, height: 40)),
        style: .defaultShape))
  ]
  let data = try AIFileWriter.data(for: document)
  let loaded = try AIFileReader.document(from: data)
  #expect(loaded == document)
}

@Test func foreignPDFThrowsNoNativeData() throws {
  // 외부 도구가 만든 PDF(페이로드 없음) 흉내: CG로 직접 생성
  let raw = NSMutableData()
  var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
  let context = CGContext(
    consumer: CGDataConsumer(data: raw as CFMutableData)!,
    mediaBox: &mediaBox, nil)!
  context.beginPDFPage(nil)
  context.endPDFPage()
  context.closePDF()
  #expect(throws: ImportError.noNativeData) {
    try AIFileReader.document(from: raw as Data)
  }
}

@Test func nonPDFDataThrowsNotPDF() {
  #expect(throws: ImportError.notPDF) {
    try AIFileReader.document(from: Data("이건 PDF가 아님".utf8))
  }
}
