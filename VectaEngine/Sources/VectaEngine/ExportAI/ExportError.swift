import Foundation

public enum ExportError: Error, Equatable, LocalizedError {
  case pdfGenerationFailed

  public var errorDescription: String? {
    switch self {
    case .pdfGenerationFailed:
      return "PDF 생성에 실패했습니다."
    }
  }
}
