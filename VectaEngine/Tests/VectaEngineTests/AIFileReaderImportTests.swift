import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@Test func nativePayloadStillWinsWithEmptyReport() throws {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [
    .path(
      PathNode(
        path: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)),
        style: .defaultShape))
  ]
  let data = try AIFileWriter.data(for: document)
  let result = try AIFileReader.read(from: data)
  #expect(result.document == document)
  #expect(result.report.isEmpty)
}

@Test func externalPDFParsesViaContentStream() throws {
  let data = makeTestPDF(content: "1 0 0 rg 10 20 100 50 re f")
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers.count == 1)
  #expect(result.document.layers[0].nodes.count == 1)
  #expect(result.document.artboard.size == CGSize(width: 200, height: 200))
}

@Test func corruptPayloadFallsBackToParserWithIssue() throws {
  // BEGIN만 있고 END 없는 손상 블록을 startxref 직전에 삽입
  var data = makeTestPDF(content: "10 10 50 50 re f")
  let marker = Data("\(NativeScenePayload.beginMarker)\n%AAAA\n".utf8)
  let startxref = data.range(of: Data("startxref".utf8), options: .backwards)!
  data.insert(contentsOf: marker, at: startxref.lowerBound)
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers[0].nodes.count == 1)  // 파서 폴백 성공
  #expect(result.report.issues.contains { $0.kind == .corruptNativePayload })
}

@Test func oversizedPayloadFallsBackToParserWithIssue() throws {
  var data = makeTestPDF(content: "10 10 50 50 re f")
  var block = Data("\(NativeScenePayload.beginMarker)\n%".utf8)
  block.append(
    Data(repeating: UInt8(ascii: "A"), count: NativeScenePayload.maxPayloadBytes + 1))
  block.append(Data("\n\(NativeScenePayload.endMarker)\n".utf8))
  let startxref = data.range(of: Data("startxref".utf8), options: .backwards)!
  data.insert(contentsOf: block, at: startxref.lowerBound)
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers[0].nodes.count == 1)
  #expect(result.report.issues.contains { $0.kind == .oversizedNativePayload })
}

@Test func multiPageLoadsFirstPageWithWarning() throws {
  let data = makeTestPDF(pages: ["10 10 50 50 re f", "20 20 50 50 re f 60 60 50 50 re f"])
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers[0].nodes.count == 1)  // 1페이지만
  #expect(result.report.issues.contains { $0.kind == .multiplePages })
}

@Test func encryptedPDFThrowsClearError() {
  // CGPDFDocument.isEncrypted = true가 되려면 Standard 핸들러의 /O·/U가
  // 각각 32바이트여야 한다 (인라인 딕셔너리 형태는 isEncrypted=false로 무시됨).
  // 간접 참조(/Encrypt 5 0 R)와 32-byte /O·/U로 올바른 픽스처를 생성한다.
  let o32 = String(repeating: "O", count: 32)
  let u32 = String(repeating: "U", count: 32)
  let encryptObj =
    "<< /Filter /Standard /V 1 /R 2 /O (\(o32)) /U (\(u32)) /P -4 >>"
  let data = makeTestPDF(
    pages: ["10 10 50 50 re f"],
    extraObjects: [encryptObj],
    trailerExtra: "/Encrypt 5 0 R ")
  #expect(throws: ImportError.encryptedPDF) {
    try AIFileReader.read(from: data)
  }
}

@Test func nonPDFStillThrowsNotPDF() {
  #expect(throws: ImportError.notPDF) {
    try AIFileReader.read(from: Data("hello".utf8))
  }
}

@Test func vectaOwnPDFContentParsesWhenPayloadStripped() throws {
  // 우리 익스포터의 PDF 본문도 파서가 읽을 수 있다 (페이로드 제거 후)
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [
    .path(
      PathNode(
        path: .rectangle(CGRect(x: 10, y: 10, width: 80, height: 40)),
        style: Style(fill: .color(RGBA(red: 1, green: 0, blue: 0)))))
  ]
  var data = try AIFileWriter.data(for: document)
  // 페이로드 블록 제거
  let begin = data.range(of: Data(NativeScenePayload.beginMarker.utf8))!
  let end = data.range(
    of: Data((NativeScenePayload.endMarker + "\n").utf8),
    in: begin.lowerBound..<data.endIndex)!
  data.removeSubrange(begin.lowerBound..<end.upperBound)
  let result = try AIFileReader.read(from: data)
  let imported = result.document.layers[0].nodes
  #expect(imported.count == 1)
  // CG가 좌표를 어떻게 직렬화하든 바운드는 보존되어야 한다
  #expect(imported[0].bounds == CGRect(x: 10, y: 10, width: 80, height: 40))
}
