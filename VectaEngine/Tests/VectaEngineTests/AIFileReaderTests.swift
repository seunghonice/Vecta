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
  let result = try AIFileReader.read(from: data)
  #expect(result.document == document)
  #expect(result.report.isEmpty)
}

@Test func foreignPDFParsesViaContentStream() throws {
  // 외부 도구가 만든 PDF(페이로드 없음): M4 이후 파서 폴백으로 처리된다
  let raw = NSMutableData()
  var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
  let context = CGContext(
    consumer: CGDataConsumer(data: raw as CFMutableData)!,
    mediaBox: &mediaBox, nil)!
  context.beginPDFPage(nil)
  context.endPDFPage()
  context.closePDF()
  // 에러 없이 파싱 성공해야 한다 (noNativeData는 더 이상 던져지지 않는다)
  let result = try AIFileReader.read(from: raw as Data)
  #expect(result.report.isEmpty)
}

@Test func nonPDFDataThrowsNotPDF() {
  #expect(throws: ImportError.notPDF) {
    try AIFileReader.read(from: Data("이건 PDF가 아님".utf8))
  }
}
