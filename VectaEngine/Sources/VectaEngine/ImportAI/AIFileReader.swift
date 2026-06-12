import Foundation

public enum AIFileReader {
  /// 임베드 JSON이 있으면 100% 복원, 없으면(외부 파일) 콘텐츠 스트림 파싱.
  /// 손상·과대 페이로드는 파싱 폴백 + 리포트 (조용한 데이터 손실 금지 — 스펙 §5).
  public static func read(from data: Data) throws -> ImportResult {
    guard data.starts(with: Data("%PDF-".utf8)) else {
      throw ImportError.notPDF
    }
    do {
      if let native = try NativeScenePayload.extract(from: data) {
        return ImportResult(document: native, report: .empty)
      }
    } catch ImportError.corruptNativeData {
      return try fallback(
        data: data, kind: .corruptNativePayload,
        detail: "저장된 Vecta 데이터가 손상되어 PDF 본문에서 가져왔습니다")
    } catch ImportError.payloadTooLarge {
      return try fallback(
        data: data, kind: .oversizedNativePayload,
        detail: "저장된 Vecta 데이터가 비정상적으로 커서 PDF 본문에서 가져왔습니다")
    }
    return try PDFDocumentImporter.importDocument(from: data)
  }

  private static func fallback(
    data: Data, kind: ImportIssue.Kind, detail: String
  ) throws -> ImportResult {
    var result = try PDFDocumentImporter.importDocument(from: data)
    result.report.issues.insert(ImportIssue(kind: kind, detail: detail), at: 0)
    return result
  }
}
