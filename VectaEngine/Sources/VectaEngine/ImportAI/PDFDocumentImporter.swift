import CoreGraphics
import Foundation

/// CGPDFDocument → ImportResult (스펙 §5). 1페이지만 파싱하고
/// 다중 페이지는 경고를 남긴다 (스펙 §10).
enum PDFDocumentImporter {
  static func importDocument(from data: Data) throws -> ImportResult {
    guard let provider = CGDataProvider(data: data as CFData),
      let pdf = CGPDFDocument(provider)
    else {
      throw ImportError.unreadablePDF
    }
    if pdf.isEncrypted && !pdf.isUnlocked {
      throw ImportError.encryptedPDF
    }
    guard pdf.numberOfPages >= 1, let page = pdf.page(at: 1) else {
      throw ImportError.unreadablePDF
    }
    var (nodes, report) = ContentStreamParser.parse(page: page)
    if pdf.numberOfPages > 1 {
      report.add(
        .multiplePages,
        detail: "\(pdf.numberOfPages)페이지 중 1페이지만 가져왔습니다")
    }
    let mediaBox = page.getBoxRect(.mediaBox)
    var document = VectorDocument.empty(size: mediaBox.size)
    document.layers[0].nodes = nodes
    return ImportResult(document: document, report: report)
  }
}
