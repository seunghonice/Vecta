import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 픽스처 PDF의 /Resources/XObject/<name> image stream을 디코드한다.
private func decodeImageResource(
  name: String, imageObject: String
) -> (png: Data?, unsupported: String?) {
  let data = makeTestPDF(
    content: "/\(name) Do",
    resources: "<< /XObject << /\(name) 5 0 R >> >>",
    extraObjects: [imageObject])
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  // CGPDFReading.stream(from:)은 Step 3에서 추가한다.
  guard let object = CGPDFContentStreamGetResource(stream, "XObject", name),
    let xobjectStream = CGPDFReading.stream(from: object),
    let dictionary = CGPDFStreamGetDictionary(xobjectStream)
  else {
    Issue.record("이미지 리소스를 못 꺼냄")
    return (nil, nil)
  }
  return PDFImageDecoder.decode(xobjectStream, dictionary: dictionary)
}

/// 2×2 RGB raw 픽셀의 ASCIIHexDecode 이미지 XObject.
/// 픽셀: (좌상 빨강 FF0000)(우상 초록 00FF00)(좌하 파랑 0000FF)(우하 흰 FFFFFF)
/// PDF image 행 순서 = top-to-bottom: 1행 [빨강 초록], 2행 [파랑 흰].
private let rgbImageObject: String = {
  let hex = "FF000000FF000000FFFFFFFF"  // 12 bytes → 24 hex chars
  let stream = "\(hex)>"  // ASCIIHexDecode 종료 마커
  return
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/Length \(stream.utf8.count) >> stream\n\(stream)\nendstream"
}()

@Test func decodesRawRGBImageToPNG() {
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: rgbImageObject)
  #expect(unsupported == nil)
  guard let png, let cgImage = CGImageCoding.cgImage(fromData: png) else {
    Issue.record("PNG 디코드 실패")
    return
  }
  #expect(cgImage.width == 2)
  #expect(cgImage.height == 2)
}

@Test func unsupportedColorSpaceImageReports() {
  // Indexed 색공간 raw → 미지원
  let hex = "00010203>"
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace [/Indexed /DeviceRGB 1 <000000FFFFFF>] /BitsPerComponent 8 "
    + "/Filter /ASCIIHexDecode /Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(png == nil)
  #expect(unsupported != nil)
}

@Test func unsupportedBitDepthImageReports() {
  // 1 bpc raw → 미지원
  let hex = "FF>"
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceGray /BitsPerComponent 1 "
    + "/Filter /ASCIIHexDecode /Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(png == nil)
  #expect(unsupported != nil)
}

@Test func imageMaskReports() {
  let hex = "FF>"
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /ImageMask true "
    + "/BitsPerComponent 1 /Filter /ASCIIHexDecode /Length \(hex.utf8.count) "
    + ">> stream\n\(hex)\nendstream"
  let (_, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(unsupported != nil)
}
