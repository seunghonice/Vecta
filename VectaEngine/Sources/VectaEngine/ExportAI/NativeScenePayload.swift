import Foundation

/// 씬그래프 JSON을 PDF의 마지막 `startxref` 직전에 base64 주석 블록으로
/// 삽입/추출한다. 주석은 xref 오프셋에 영향을 주지 않으므로 파일은 유효한
/// PDF로 유지된다 (스펙 6절, 2026-06-11 스파이크로 검증).
public enum NativeScenePayload {
  static let beginMarker = "%VectaSceneJSON-BEGIN"
  static let endMarker = "%VectaSceneJSON-END"

  /// 임베드 페이로드 상한 (M1 리뷰 보류 항목) — 비정상·악의적 파일의
  /// 메모리 폭주 방어. base64 텍스트 길이 기준 64MB.
  static let maxPayloadBytes = 64 * 1024 * 1024

  /// 씬그래프를 PDF 꼬리의 `startxref` 직전에 base64 주석 블록으로 삽입한다.
  /// 기존 블록이 있으면 교체한다.
  public static func embed(_ document: VectorDocument, into pdfData: Data) throws -> Data {
    var cleaned = pdfData
    if let staleRange = existingBlockRange(in: cleaned) {
      cleaned.removeSubrange(staleRange)
    }
    guard
      let startxrefRange = cleaned.range(
        of: Data("startxref".utf8), options: .backwards)
    else {
      throw ExportError.pdfGenerationFailed
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let payload = try encoder.encode(document).base64EncodedString()
    let block = "\(beginMarker)\n%\(payload)\n\(endMarker)\n"
    var result = cleaned
    result.insert(contentsOf: Data(block.utf8), at: startxrefRange.lowerBound)
    return result
  }

  /// 기존 페이로드 블록 전체 범위 (begin 줄 ~ end 마커 + 개행).
  private static func existingBlockRange(in data: Data) -> Range<Data.Index>? {
    guard
      let begin = data.range(of: Data(beginMarker.utf8)),
      let end = data.range(
        of: Data((endMarker + "\n").utf8), in: begin.upperBound..<data.endIndex)
    else {
      return nil
    }
    return begin.lowerBound..<end.upperBound
  }

  /// 마커가 없으면 nil (외부 파일 → 콘텐츠 스트림 파싱 폴백 대상).
  /// BEGIN만 있고 END가 없으면 손상된 파일로 간주해 `ImportError.corruptNativeData`를 throw.
  public static func extract(from data: Data) throws -> VectorDocument? {
    guard let beginRange = data.range(of: Data((beginMarker + "\n%").utf8)) else {
      return nil  // 마커 없음 = 외부 파일 (M4에서 콘텐츠 스트림 파싱 폴백)
    }
    guard
      let endRange = data.range(
        of: Data(("\n" + endMarker).utf8), in: beginRange.upperBound..<data.endIndex)
    else {
      throw ImportError.corruptNativeData  // BEGIN만 있고 END 없음 = 손상
    }
    let base64 = data[beginRange.upperBound..<endRange.lowerBound]
    guard base64.count <= maxPayloadBytes else {
      throw ImportError.payloadTooLarge
    }
    guard let json = Data(base64Encoded: base64) else {
      throw ImportError.corruptNativeData
    }
    do {
      return try JSONDecoder().decode(VectorDocument.self, from: json)
    } catch {
      throw ImportError.corruptNativeData
    }
  }
}
