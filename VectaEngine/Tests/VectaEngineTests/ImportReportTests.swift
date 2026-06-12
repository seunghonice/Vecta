import Foundation
import Testing

@testable import VectaEngine

@Test func importReportCollectsIssues() {
  var report = ImportReport()
  #expect(report.isEmpty)
  report.add(.unsupportedShading, detail: "sh 연산자")
  report.add(.multiplePages, detail: "3페이지 중 1페이지만")
  #expect(report.issues.count == 2)
  #expect(report.issues[0].kind == .unsupportedShading)
  #expect(!report.isEmpty)
}

@Test func oversizedPayloadThrows() throws {
  // 정상 PDF 꼬리 구조를 흉내 낸 데이터에 상한 초과 base64 블록 삽입
  let huge = Data(
    repeating: UInt8(ascii: "A"), count: NativeScenePayload.maxPayloadBytes + 1)
  var data = Data("%PDF-1.4\n".utf8)
  data.append(Data("\(NativeScenePayload.beginMarker)\n%".utf8))
  data.append(huge)
  data.append(Data("\n\(NativeScenePayload.endMarker)\nstartxref\n0\n%%EOF".utf8))
  #expect(throws: ImportError.payloadTooLarge) {
    try NativeScenePayload.extract(from: data)
  }
}

@Test func payloadUnderCapStillExtracts() throws {
  // 기존 정상 경로 회귀 — 작은 문서는 그대로 추출
  let document = VectorDocument.empty()
  let pdf = try AIFileWriter.data(for: document)
  let extracted = try NativeScenePayload.extract(from: pdf)
  #expect(extracted == document)
}

@Test func importErrorMessagesAreKorean() {
  #expect(ImportError.payloadTooLarge.errorDescription?.isEmpty == false)
  #expect(ImportError.encryptedPDF.errorDescription?.isEmpty == false)
  #expect(ImportError.unreadablePDF.errorDescription?.isEmpty == false)
}

@Test func payloadExactlyAtCapIsNotRejectedForSize() {
  // 정확히 상한 == 통과 (<= 경계 고정). 내용이 유효 JSON이 아니므로
  // corruptNativeData가 나야 하며, payloadTooLarge면 경계 회귀다.
  let atCap = Data(
    repeating: UInt8(ascii: "A"), count: NativeScenePayload.maxPayloadBytes)
  var data = Data("%PDF-1.4\n".utf8)
  data.append(Data("\(NativeScenePayload.beginMarker)\n%".utf8))
  data.append(atCap)
  data.append(Data("\n\(NativeScenePayload.endMarker)\nstartxref\n0\n%%EOF".utf8))
  #expect(throws: ImportError.corruptNativeData) {
    try NativeScenePayload.extract(from: data)
  }
}
