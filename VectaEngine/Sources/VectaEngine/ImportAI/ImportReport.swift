/// 임포트 중 건너뛴 요소의 항목별 수집 (스펙 §5 — 조용한 데이터 손실 금지).
public struct ImportIssue: Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case multiplePages
    case unsupportedShading
    case unsupportedImage
    case unsupportedText
    case unsupportedColorSpace
    case formRecursionLimit
    case corruptNativePayload
    case oversizedNativePayload
  }

  public var kind: Kind
  public var detail: String

  public init(kind: Kind, detail: String) {
    self.kind = kind
    self.detail = detail
  }
}

public struct ImportReport: Equatable, Sendable {
  public var issues: [ImportIssue]

  public init(issues: [ImportIssue] = []) {
    self.issues = issues
  }

  public static let empty = ImportReport()

  public var isEmpty: Bool { issues.isEmpty }

  public mutating func add(_ kind: ImportIssue.Kind, detail: String) {
    issues.append(ImportIssue(kind: kind, detail: detail))
  }
}

/// 임포트 결과 — 문서 + 리포트 (배너 표시용).
public struct ImportResult: Equatable, Sendable {
  public var document: VectorDocument
  public var report: ImportReport

  public init(document: VectorDocument, report: ImportReport) {
    self.document = document
    self.report = report
  }
}
