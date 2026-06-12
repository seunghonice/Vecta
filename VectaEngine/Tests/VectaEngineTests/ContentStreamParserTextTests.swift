import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private let helveticaFont =
  "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"

private func parseText(
  content: String, mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200)
) -> (nodes: [Node], report: ImportReport) {
  parseFixture(
    content: content, mediaBox: mediaBox,
    resources: "<< /Font << /F0 5 0 R >> >>",
    extraObjects: [helveticaFont])
}

@Test func simpleTextBecomesTextNode() {
  let (nodes, report) = parseText(content: "BT /F0 24 Tf 50 100 Td (Hello) Tj ET")
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  #expect(textNode.string == "Hello")
  #expect(textNode.fontName == "Helvetica")
  #expect(textNode.fontSize == 24)
  // Td 50 100 → text 원점 PDF (50,100) → 모델 y 100 (mediaBox 200)
  #expect(abs(textNode.position.x - 50) < 0.0001)
  #expect(abs(textNode.position.y - 100) < 0.0001)
}

@Test func textMatrixSetsPosition() {
  let (nodes, _) = parseText(content: "BT /F0 12 Tf 1 0 0 1 30 40 Tm (Tm) Tj ET")
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  // Tm 원점 PDF (30,40) → 모델 (30, 160)
  #expect(abs(textNode.position.x - 30) < 0.0001)
  #expect(abs(textNode.position.y - 160) < 0.0001)
}

@Test func textFillColorCaptured() {
  let (nodes, _) = parseText(content: "BT 1 0 0 rg /F0 12 Tf 0 0 Td (Red) Tj ET")
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  #expect(textNode.fill == .color(RGBA(red: 1, green: 0, blue: 0)))
}

@Test func multipleTjProduceMultipleNodes() {
  let (nodes, _) = parseText(
    content: "BT /F0 12 Tf 0 100 Td (A) Tj 0 -20 Td (B) Tj ET")
  let textNodes = nodes.compactMap { node -> TextNode? in
    if case .text(let t) = node { return t }
    return nil
  }
  #expect(textNodes.count == 2)
  #expect(textNodes[0].string == "A")
  #expect(textNodes[1].string == "B")
  // T* 류 줄바꿈으로 둘째가 아래
  #expect(textNodes[1].position.y > textNodes[0].position.y)
}

@Test func tjArrayConcatenatesStrings() {
  let (nodes, _) = parseText(content: "BT /F0 12 Tf 0 0 Td [(Hel) -100 (lo)] TJ ET")
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  #expect(textNode.string == "Hello")
}

@Test func missingFontReportsAndSkips() {
  // Tf로 없는 폰트 참조 → 리포트, 텍스트 노드 없음
  let (nodes, report) = parseFixture(
    content: "BT /Missing 12 Tf 0 0 Td (X) Tj ET",
    resources: "<< /Font << >> >>")
  #expect(nodes.isEmpty)
  #expect(report.issues.contains { $0.kind == .unsupportedText })
}

@Test func textRespectsClip() {
  let (nodes, _) = parseText(
    content: "10 10 50 50 re W n BT /F0 12 Tf 0 0 Td (Clip) Tj ET")
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0], case .text = group.children.first else {
    Issue.record("클립 그룹 안에 텍스트가 아님")
    return
  }
}

@Test func rotatedTextReportsApproximation() {
  // 90° 회전 Tm — 정립 근사 + 리포트
  let (nodes, report) = parseText(content: "BT /F0 12 Tf 0 1 -1 0 50 50 Tm (R) Tj ET")
  #expect(nodes.count == 1)  // 텍스트는 여전히 생성(정립)
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  #expect(textNode.transform == .identity)  // 정립 근사
  #expect(report.issues.contains { $0.detail.contains("회전") })
}

@Test func nonRotatedTextNoApproximationReport() {
  // 평범한 텍스트는 회전 리포트 없음
  let (_, report) = parseText(content: "BT /F0 12 Tf 1 0 0 1 30 40 Tm (Plain) Tj ET")
  #expect(!report.issues.contains { $0.detail.contains("회전") })
}
