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

@Test func decodesRawGrayImageToPNG() {
  // DeviceGray 8bpc raw 2×2 — 양성 경로 커버
  let hex = "00FF80C0>"  // 4 gray bytes
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(unsupported == nil)
  guard let png, let cgImage = CGImageCoding.cgImage(fromData: png) else {
    Issue.record("PNG 디코드 실패")
    return
  }
  #expect(cgImage.width == 2)
  #expect(cgImage.height == 2)
}

@Test func softMaskImageReports() {
  // /SMask 동반 — 두 경로 공통으로 미지원 리포트 (raw 경로로 검증)
  let hex = "FF000000FF000000FFFFFFFF>"
  let smaskHex = "FF80>"
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/SMask 6 0 R /Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  let smask =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceGray "
    + "/BitsPerComponent 8 /Filter /ASCIIHexDecode /Length \(smaskHex.utf8.count) "
    + ">> stream\n\(smaskHex)\nendstream"
  let (png, unsupported) = decodeImageResource2(
    name: "Im0", imageObject: image, extraObject: smask)
  #expect(png == nil)
  #expect(unsupported?.contains("마스크") == true)
}

@Test func cmykImageReportsUnsupported() {
  // DeviceCMYK raw — 미지원 (RGB/Gray만), 리포트 문자열 고정
  let hex = "00000000>"  // 1px CMYK 4 bytes
  let image =
    "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 "
    + "/ColorSpace /DeviceCMYK /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(png == nil)
  #expect(unsupported?.contains("색공간") == true)
}

private func decodeImageResource2(
  name: String, imageObject: String, extraObject: String
) -> (png: Data?, unsupported: String?) {
  let data = makeTestPDF(
    content: "/\(name) Do",
    resources: "<< /XObject << /\(name) 5 0 R >> >>",
    extraObjects: [imageObject, extraObject])
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  guard let object = CGPDFContentStreamGetResource(stream, "XObject", name),
    let xobjectStream = CGPDFReading.stream(from: object),
    let dictionary = CGPDFStreamGetDictionary(xobjectStream)
  else {
    Issue.record("이미지 리소스를 못 꺼냄")
    return (nil, nil)
  }
  return PDFImageDecoder.decode(xobjectStream, dictionary: dictionary)
}
