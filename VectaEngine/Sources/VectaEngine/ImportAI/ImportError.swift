import Foundation

public enum ImportError: Error, Equatable, LocalizedError {
  case notPDF
  case corruptNativeData
  case payloadTooLarge
  case encryptedPDF
  case unreadablePDF

  public var errorDescription: String? {
    switch self {
    case .notPDF:
      return "지원하지 않는 파일입니다. PDF 호환 .ai 파일만 열 수 있습니다."
    case .corruptNativeData:
      return "파일에 저장된 Vecta 데이터가 손상되었습니다."
    case .payloadTooLarge:
      return "파일에 저장된 Vecta 데이터가 비정상적으로 큽니다."
    case .encryptedPDF:
      return "암호로 보호된 파일은 열 수 없습니다."
    case .unreadablePDF:
      return "지원하지 않는 파일입니다. 파일이 손상되었을 수 있습니다."
    }
  }
}
