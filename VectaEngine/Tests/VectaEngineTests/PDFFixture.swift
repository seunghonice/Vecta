import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 수제 미니멀 PDF (스펙 §11 — 연산자 케이스별 파싱 테스트용).
/// 객체 번호 규약: 1 카탈로그, 2 페이지 트리, 페이지 i(0부터)는
/// 3+2i(페이지)·4+2i(콘텐츠). extraObjects는 그 뒤 — 1페이지면 5번부터.
func makeTestPDF(
  pages: [String],
  mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
  resources: String = "<< >>",
  extraObjects: [String] = [],
  trailerExtra: String = ""
) -> Data {
  var objects: [String] = []
  let kids = (0..<pages.count).map { "\(3 + 2 * $0) 0 R" }.joined(separator: " ")
  objects.append("<< /Type /Catalog /Pages 2 0 R >>")
  objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
  for (index, content) in pages.enumerated() {
    let box =
      "[\(Int(mediaBox.minX)) \(Int(mediaBox.minY)) \(Int(mediaBox.maxX)) \(Int(mediaBox.maxY))]"
    objects.append(
      "<< /Type /Page /Parent 2 0 R /MediaBox \(box) "
        + "/Contents \(4 + 2 * index) 0 R /Resources \(resources) >>")
    objects.append("<< /Length \(content.utf8.count) >> stream\n\(content)\nendstream")
  }
  objects.append(contentsOf: extraObjects)

  var body = "%PDF-1.4\n"
  var offsets: [Int] = []
  for (index, object) in objects.enumerated() {
    offsets.append(body.utf8.count)
    body += "\(index + 1) 0 obj \(object) endobj\n"
  }
  let xrefOffset = body.utf8.count
  body += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
  for offset in offsets {
    body += String(format: "%010d 00000 n \n", offset)
  }
  body += "trailer << /Size \(objects.count + 1) /Root 1 0 R \(trailerExtra)>>\n"
  body += "startxref\n\(xrefOffset)\n%%EOF\n"
  return Data(body.utf8)
}

/// 콘텐츠 1개짜리 단축 헬퍼.
func makeTestPDF(
  content: String,
  mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
  resources: String = "<< >>",
  extraObjects: [String] = []
) -> Data {
  makeTestPDF(
    pages: [content], mediaBox: mediaBox, resources: resources, extraObjects: extraObjects)
}

@Test func fixtureOpensWithCGPDFDocument() {
  let data = makeTestPDF(content: "10 10 100 100 re f")
  let provider = CGDataProvider(data: data as CFData)!
  let pdf = CGPDFDocument(provider)
  #expect(pdf != nil)
  #expect(pdf?.numberOfPages == 1)
  #expect(pdf?.page(at: 1) != nil)
}

@Test func fixtureSupportsMultiplePages() {
  let data = makeTestPDF(pages: ["10 10 50 50 re f", "20 20 50 50 re f"])
  let provider = CGDataProvider(data: data as CFData)!
  let pdf = CGPDFDocument(provider)
  #expect(pdf?.numberOfPages == 2)
}
