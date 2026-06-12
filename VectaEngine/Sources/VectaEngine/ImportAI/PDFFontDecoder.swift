import CoreGraphics
import Foundation

/// 폰트의 바이트 코드 → 문자열 디코더 (스펙 §5).
struct PDFFont {
  /// 코드 바이트 폭 (Type0=2, simple=1).
  let codeBytes: Int
  /// /ToUnicode (있으면 우선).
  let toUnicode: ToUnicodeCMap?
  /// 표준 인코딩 폴백 (ToUnicode 없을 때).
  let stringEncoding: String.Encoding
  /// 원본 폰트명 (/BaseFont).
  let baseFont: String

  /// 바이트 → 문자열. ToUnicode 우선, 없으면 표준 인코딩.
  func decode(_ bytes: [UInt8]) -> String {
    if let toUnicode {
      return toUnicode.decode(bytes, codeBytes: codeBytes)
    }
    return String(bytes: bytes, encoding: stringEncoding) ?? ""
  }
}

/// 폰트 dict → PDFFont (스펙 §5). Type0는 ToUnicode 필수, 미지원 사유 반환.
enum PDFFontDecoder {
  static func font(
    from dictionary: CGPDFDictionaryRef
  ) -> (font: PDFFont?, unsupported: String?) {
    let subtype = CGPDFReading.name(dictionary, "Subtype") ?? ""
    let baseFont = CGPDFReading.name(dictionary, "BaseFont") ?? "Unknown"
    let isType0 = subtype == "Type0"
    let codeBytes = isType0 ? 2 : 1

    var unsupported: String?
    let toUnicode = toUnicodeCMap(from: dictionary)

    // Type0(복합)는 ToUnicode 없으면 디코드 불가.
    if isType0, toUnicode == nil {
      return (nil, "복합 폰트 \(baseFont) (ToUnicode 없음 — 미지원)")
    }

    // 인코딩: name 또는 dict(Differences 동반).
    let encoding = stringEncoding(from: dictionary, reportDifferences: &unsupported)

    let font = PDFFont(
      codeBytes: codeBytes, toUnicode: toUnicode,
      stringEncoding: encoding, baseFont: baseFont)
    return (font, unsupported)
  }

  private static func toUnicodeCMap(from dictionary: CGPDFDictionaryRef) -> ToUnicodeCMap? {
    guard let object = CGPDFReading.object(dictionary, "ToUnicode"),
      let stream = CGPDFReading.stream(from: object)
    else { return nil }
    var format = CGPDFDataFormat.raw
    guard let cfData = CGPDFStreamCopyData(stream, &format) else { return nil }
    let data = cfData as Data
    guard let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8)
    else { return nil }
    return ToUnicodeCMap.parse(text)
  }

  /// /Encoding name 또는 dict의 BaseEncoding → String.Encoding.
  /// Differences가 있으면 리포트(무시).
  private static func stringEncoding(
    from dictionary: CGPDFDictionaryRef, reportDifferences: inout String?
  ) -> String.Encoding {
    // name 형태
    if let name = CGPDFReading.name(dictionary, "Encoding") {
      return mapEncodingName(name)
    }
    // dict 형태 (BaseEncoding + Differences)
    if let encodingObject = CGPDFReading.object(dictionary, "Encoding"),
      let encodingDict = CGPDFReading.dictionary(from: encodingObject)
    {
      if CGPDFReading.object(encodingDict, "Differences") != nil {
        reportDifferences = "폰트 Differences 인코딩 (무시 — 기본 인코딩 사용)"
      }
      if let base = CGPDFReading.name(encodingDict, "BaseEncoding") {
        return mapEncodingName(base)
      }
    }
    return .windowsCP1252  // 기본
  }

  private static func mapEncodingName(_ name: String) -> String.Encoding {
    switch name {
    case "WinAnsiEncoding": return .windowsCP1252
    case "MacRomanEncoding": return .macOSRoman
    case "StandardEncoding", "PDFDocEncoding": return .isoLatin1
    default: return .windowsCP1252
    }
  }
}
