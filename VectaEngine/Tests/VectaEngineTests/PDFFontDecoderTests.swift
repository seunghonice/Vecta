import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 픽스처 PDF의 /Resources/Font/<name> dict로 PDFFont를 만든다.
private func fontFromResource(
  name: String, fontObject: String, extraObjects: [String] = []
) -> (font: PDFFont?, unsupported: String?) {
  let data = makeTestPDF(
    content: "BT /\(name) 12 Tf (X) Tj ET",
    resources: "<< /Font << /\(name) 5 0 R >> >>",
    extraObjects: [fontObject] + extraObjects)
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  guard let object = CGPDFContentStreamGetResource(stream, "Font", name),
    let dictionary = CGPDFReading.dictionary(from: object)
  else {
    Issue.record("폰트 리소스를 못 꺼냄")
    return (nil, nil)
  }
  return PDFFontDecoder.font(from: dictionary)
}

@Test func type1WinAnsiDecodesLatin() {
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
    + "/Encoding /WinAnsiEncoding >>"
  let (pdfFont, unsupported) = fontFromResource(name: "F0", fontObject: font)
  #expect(unsupported == nil)
  #expect(pdfFont?.baseFont == "Helvetica")
  // WinAnsi: 0x41='A', 0xE9='é'(CP1252)
  #expect(pdfFont?.decode([0x41, 0x42, 0x43]) == "ABC")
  #expect(pdfFont?.decode([0xE9]) == "é")
}

@Test func toUnicodeWinsOverEncoding() {
  let cmap = """
    1 beginbfchar
    <0041> <0042>
    endbfchar
    endcmap
    """
  let cmapStream =
    "<< /Length \(cmap.utf8.count) >> stream\n\(cmap)\nendstream"
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
    + "/Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>"
  let (pdfFont, _) = fontFromResource(
    name: "F0", fontObject: font, extraObjects: [cmapStream])
  // ToUnicode 우선: 0x41 → 'B'(0x42)
  #expect(pdfFont?.decode([0x41]) == "B")
}

@Test func type0WithoutToUnicodeReports() {
  let font =
    "<< /Type /Font /Subtype /Type0 /BaseFont /SomeCID-Identity-H "
    + "/Encoding /Identity-H >>"
  let (pdfFont, unsupported) = fontFromResource(name: "F0", fontObject: font)
  #expect(pdfFont == nil)
  #expect(unsupported != nil)
}

@Test func type0WithToUnicodeUsesTwoByteCodes() {
  let cmap = """
    1 beginbfchar
    <0041> <0058>
    endbfchar
    endcmap
    """
  let cmapStream = "<< /Length \(cmap.utf8.count) >> stream\n\(cmap)\nendstream"
  let font =
    "<< /Type /Font /Subtype /Type0 /BaseFont /CID-Identity "
    + "/Encoding /Identity-H /ToUnicode 6 0 R >>"
  let (pdfFont, _) = fontFromResource(
    name: "F0", fontObject: font, extraObjects: [cmapStream])
  #expect(pdfFont?.codeBytes == 2)
  // 2바이트 코드 0x0041 → 'X'(0x58)
  #expect(pdfFont?.decode([0x00, 0x41]) == "X")
}

@Test func differencesEncodingReports() {
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
    + "/Encoding << /BaseEncoding /WinAnsiEncoding "
    + "/Differences [65 /bullet] >> >>"
  let (pdfFont, unsupported) = fontFromResource(name: "F0", fontObject: font)
  // Differences는 무시하되 리포트 — 폰트는 BaseEncoding으로 동작
  #expect(pdfFont != nil)
  #expect(unsupported != nil)
}

@Test func subsetPrefixStrippedFromBaseFont() {
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+Helvetica "
    + "/Encoding /WinAnsiEncoding >>"
  let (pdfFont, _) = fontFromResource(name: "F0", fontObject: font)
  #expect(pdfFont?.baseFont == "Helvetica")  // prefix 제거
}

@Test func nonSubsetBaseFontUnchanged() {
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman "
    + "/Encoding /WinAnsiEncoding >>"
  let (pdfFont, _) = fontFromResource(name: "F0", fontObject: font)
  #expect(pdfFont?.baseFont == "Times-Roman")  // '+' 없으면 그대로
}

@Test func macRomanEncodingDecodes() {
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
    + "/Encoding /MacRomanEncoding >>"
  let (pdfFont, _) = fontFromResource(name: "F0", fontObject: font)
  // MacRoman: 0x41='A' (ASCII 동일)
  #expect(pdfFont?.decode([0x41, 0x42]) == "AB")
}

@Test func nonIdentityType0Reports() {
  let cmap = """
    1 beginbfchar
    <0041> <0058>
    endbfchar
    endcmap
    """
  let cmapStream = "<< /Length \(cmap.utf8.count) >> stream\n\(cmap)\nendstream"
  let font =
    "<< /Type /Font /Subtype /Type0 /BaseFont /CID-Font "
    + "/Encoding /UniGB-UCS2-H /ToUnicode 6 0 R >>"
  let (pdfFont, unsupported) = fontFromResource(
    name: "F0", fontObject: font, extraObjects: [cmapStream])
  #expect(pdfFont != nil)  // ToUnicode 있으니 폰트는 생성
  #expect(unsupported != nil)  // 비-Identity 경고
}
