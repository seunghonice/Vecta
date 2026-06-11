import Foundation

public enum ImportError: Error, Equatable, LocalizedError {
  case notPDF
  case noNativeData
  case corruptNativeData

  public var errorDescription: String? {
    switch self {
    case .notPDF:
      return "지원하지 않는 파일입니다. PDF 호환 .ai 파일만 열 수 있습니다."
    case .noNativeData:
      return "다른 앱에서 만든 .ai 파일 가져오기는 아직 지원하지 않습니다."
    case .corruptNativeData:
      return "파일에 저장된 Voida 데이터가 손상되었습니다."
    }
  }
}
