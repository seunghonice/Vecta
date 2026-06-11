import CoreGraphics
import Foundation
import Testing

@testable import VoidaEngine

/// startxref와 %%EOF를 가진 최소 형태의 가짜 PDF 꼬리.
private let fakePDF = Data(
  """
  %PDF-1.4
  1 0 obj << >> endobj
  xref
  trailer << >>
  startxref
  9
  %%EOF
  """.utf8)

@Test func embedThenExtractRoundTrips() throws {
  let document = VectorDocument.empty(size: CGSize(width: 100, height: 80))
  let embedded = try NativeScenePayload.embed(document, into: fakePDF)
  let extracted = try NativeScenePayload.extract(from: embedded)
  #expect(extracted == document)
}

@Test func embedInsertsBeforeStartxref() throws {
  let document = VectorDocument.empty()
  let embedded = try NativeScenePayload.embed(document, into: fakePDF)
  let text = String(decoding: embedded, as: UTF8.self)
  let markerIndex = text.range(of: "%VoidaSceneJSON-BEGIN")!.lowerBound
  let startxrefIndex = text.range(of: "startxref")!.lowerBound
  #expect(markerIndex < startxrefIndex)
  #expect(text.hasSuffix("%%EOF"))
}

@Test func extractReturnsNilWhenMarkerAbsent() throws {
  #expect(try NativeScenePayload.extract(from: fakePDF) == nil)
}

@Test func extractThrowsOnCorruptPayload() throws {
  let corrupt = Data(
    """
    %PDF-1.4
    %VoidaSceneJSON-BEGIN
    %!!!이건 base64가 아님!!!
    %VoidaSceneJSON-END
    startxref
    9
    %%EOF
    """.utf8)
  #expect(throws: ImportError.corruptNativeData) {
    try NativeScenePayload.extract(from: corrupt)
  }
}

@Test func embedThrowsWhenStartxrefMissing() {
  #expect(throws: ExportError.pdfGenerationFailed) {
    try NativeScenePayload.embed(VectorDocument.empty(), into: Data("no pdf".utf8))
  }
}

@Test func truncatedPayloadThrowsCorruptNativeData() throws {
  let document = VectorDocument.empty()
  let embedded = try NativeScenePayload.embed(document, into: fakePDF)
  // END 마커를 잘라낸 손상 파일
  let endMarkerData = Data("\n%VoidaSceneJSON-END".utf8)
  let endRange = embedded.range(of: endMarkerData)!
  let truncated = embedded[embedded.startIndex..<endRange.lowerBound]
  #expect(throws: ImportError.corruptNativeData) {
    try NativeScenePayload.extract(from: Data(truncated))
  }
}

@Test func embedReplacesExistingBlock() throws {
  let first = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  let second = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  let once = try NativeScenePayload.embed(first, into: fakePDF)
  let twice = try NativeScenePayload.embed(second, into: once)
  #expect(try NativeScenePayload.extract(from: twice) == second)
  // 블록이 하나만 남아야 한다
  let text = String(decoding: twice, as: UTF8.self)
  let beginCount = text.components(separatedBy: "%VoidaSceneJSON-BEGIN").count - 1
  #expect(beginCount == 1)
}
