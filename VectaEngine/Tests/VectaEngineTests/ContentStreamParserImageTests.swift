import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 2×2 RGB raw ASCIIHex 이미지 (Task 2와 동일 구조).
private let rgbImageObject: String = {
  let hex = "FF000000FF000000FFFFFFFF"
  let stream = "\(hex)>"
  return
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/Length \(stream.utf8.count) >> stream\n\(stream)\nendstream"
}()

@Test func imageXObjectBecomesImageNodeWithBakedPlacement() {
  // q 80 0 0 60 30 40 cm /Im0 Do Q — unit square가 PDF (30,40)~(110,100)에 배치
  // CTM [80 0 0 60 30 40] maps unit square → PDF (30,40)~(110,100)
  // pageFlip (height=200): y_model = 200 - y_pdf
  //   PDF y=40 → model y=160, PDF y=100 → model y=100
  // → model bounds: minX=30, width=80, minY=100, height=60
  let (nodes, report) = parseFixture(
    content: "q 80 0 0 60 30 40 cm /Im0 Do Q",
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [rgbImageObject])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .image(let imageNode) = nodes[0] else {
    Issue.record("이미지 노드가 아님")
    return
  }
  #expect(imageNode.frame == CGRect(x: 0, y: 0, width: 1, height: 1))
  #expect(!imageNode.imageData.isEmpty)
  // 모델 바운드: minX=30, width=80, minY=100, height=60
  let bounds = Node.image(imageNode).bounds
  #expect(abs(bounds.minX - 30) < 0.0001)
  #expect(abs(bounds.width - 80) < 0.0001)
  #expect(abs(bounds.minY - 100) < 0.0001)
  #expect(abs(bounds.height - 60) < 0.0001)
}

@Test func unsupportedImageProducesNoNodeButReports() {
  let badImage =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /ASCIIHexDecode "
    + "/Length 3 >> stream\nFF>\nendstream"
  let (nodes, report) = parseFixture(
    content: "/Im0 Do",
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [badImage])
  #expect(nodes.isEmpty)
  #expect(report.issues.contains { $0.kind == .unsupportedImage })
}

@Test func importedImageRendersUprightThroughFullPipeline() {
  // 상단 빨강(첫 행) / 하단 파랑(둘째 행) 1×2 이미지를 PDF 전체에 배치 →
  // 임포트→렌더 파이프라인을 거쳐 모델 상단이 빨강이어야 한다 (정립).
  let hex = "FF00000000FF>"  // row0 red(FF0000), row1 blue(0000FF)
  let image =
    "<< /Type /XObject /Subtype /Image /Width 1 /Height 2 "
    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  // 200 0 0 200 0 0 cm — unit square를 페이지 전체(200×200)에 배치
  let pdfData = makeTestPDF(
    content: "q 200 0 0 200 0 0 cm /Im0 Do Q",
    mediaBox: CGRect(x: 0, y: 0, width: 200, height: 200),
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [image])
  let provider = CGDataProvider(data: pdfData as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let (nodes, _) = ContentStreamParser.parse(page: page)
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = nodes
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  // 모델 상단(y=50)은 빨강, 하단(y=150)은 파랑
  let top = pixelColor(x: 100, y: 50, in: context)
  #expect(top.red > 180)
  #expect(top.blue < 80)
  let bottom = pixelColor(x: 100, y: 150, in: context)
  #expect(bottom.blue > 180)
  #expect(bottom.red < 80)
}

@Test func imageRespectsClip() {
  // 클립 안에서 이미지 — 클립 그룹으로 묶인다
  let (nodes, _) = parseFixture(
    content: "10 10 50 50 re W n q 80 0 0 60 0 0 cm /Im0 Do Q",
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [rgbImageObject])
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  guard case .image = group.children.first else {
    Issue.record("그룹 안에 이미지가 아님")
    return
  }
}
