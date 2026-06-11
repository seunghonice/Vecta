import Foundation

/// 씬그래프 JSON을 PDF의 마지막 `startxref` 직전에 base64 주석 블록으로
/// 삽입/추출한다. 주석은 xref 오프셋에 영향을 주지 않으므로 파일은 유효한
/// PDF로 유지된다 (스펙 6절, 2026-06-11 스파이크로 검증).
public enum NativeScenePayload {
  static let beginMarker = "%VoidaSceneJSON-BEGIN"
  static let endMarker = "%VoidaSceneJSON-END"

  public static func embed(_ document: VectorDocument, into pdfData: Data) throws -> Data {
    guard
      let startxrefRange = pdfData.range(
        of: Data("startxref".utf8), options: .backwards)
    else {
      throw ExportError.pdfGenerationFailed
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let payload = try encoder.encode(document).base64EncodedString()
    let block = "\(beginMarker)\n%\(payload)\n\(endMarker)\n"
    var result = pdfData
    result.insert(contentsOf: Data(block.utf8), at: startxrefRange.lowerBound)
    return result
  }

  /// 마커가 없으면 nil (외부 파일 → 콘텐츠 스트림 파싱 폴백 대상).
  public static func extract(from data: Data) throws -> VectorDocument? {
    guard
      let beginRange = data.range(of: Data((beginMarker + "\n%").utf8)),
      let endRange = data.range(
        of: Data(("\n" + endMarker).utf8), in: beginRange.upperBound..<data.endIndex)
    else {
      return nil
    }
    let base64 = data[beginRange.upperBound..<endRange.lowerBound]
    guard let json = Data(base64Encoded: Data(base64)) else {
      throw ImportError.corruptNativeData
    }
    do {
      return try JSONDecoder().decode(VectorDocument.self, from: json)
    } catch {
      throw ImportError.corruptNativeData
    }
  }
}
