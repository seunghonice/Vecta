import CoreGraphics
import Testing

@testable import VectaEngine

/// 픽스처 PDF 1페이지를 파싱해 노드를 돌려준다.
func parseFixture(
  content: String,
  mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
  resources: String = "<< >>",
  extraObjects: [String] = []
) -> (nodes: [Node], report: ImportReport) {
  let data = makeTestPDF(
    content: content, mediaBox: mediaBox, resources: resources, extraObjects: extraObjects)
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  return ContentStreamParser.parse(page: page)
}

private func firstPath(_ nodes: [Node]) -> PathNode? {
  guard case .path(let pathNode)? = nodes.first else { return nil }
  return pathNode
}

@Test func parsesFilledRectangleWithFlippedCoordinates() {
  let (nodes, report) = parseFixture(content: "1 0 0 rg 10 20 100 50 re f")
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  // PDF y 20…70 → 모델 y 130…180 (mediaBox 높이 200)
  #expect(pathNode.path.bounds == CGRect(x: 10, y: 130, width: 100, height: 50))
  #expect(pathNode.style.fill == .color(RGBA(red: 1, green: 0, blue: 0)))
  #expect(pathNode.style.stroke == nil)
  #expect(pathNode.transform == .identity)
  #expect(pathNode.fillRule == .winding)
}

@Test func parsesStrokeAttributes() {
  let (nodes, _) = parseFixture(content: "0 0 1 RG 4 w 1 J 2 j 10 10 m 100 100 l S")
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.style.fill == nil)
  let stroke = pathNode.style.stroke
  #expect(stroke?.paint == RGBA(red: 0, green: 0, blue: 1))
  #expect(stroke?.width == 4)
  #expect(stroke?.cap == .round)
  #expect(stroke?.join == .bevel)
}

@Test func parsesGrayAndCMYKColors() {
  let (nodes, _) = parseFixture(
    content: "0.5 g 10 10 20 20 re f 1 0 0 0 k 50 10 20 20 re f")
  #expect(nodes.count == 2)
  guard case .path(let gray) = nodes[0], case .path(let cyan) = nodes[1] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(gray.style.fill == .color(RGBA(red: 0.5, green: 0.5, blue: 0.5)))
  #expect(cyan.style.fill == .color(RGBA(red: 0, green: 1, blue: 1)))
}

@Test func ctmScalesGeometryAndStrokeWidth() {
  let (nodes, _) = parseFixture(content: "q 2 0 0 2 0 0 cm 3 w 10 10 m 50 10 l S Q")
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  // 기하 ×2: PDF (20,20)→(100,20) → 모델 y 180
  #expect(pathNode.path.bounds == CGRect(x: 20, y: 180, width: 80, height: 0))
  #expect(pathNode.style.stroke?.width == 6)  // √|det| = 2
}

@Test func evenOddOperatorSetsFillRule() {
  let (nodes, _) = parseFixture(
    content: "20 20 160 160 re 70 70 60 60 re f*")
  #expect(firstPath(nodes)?.fillRule == .evenOdd)
}

@Test func saveRestoreIsolatesState() {
  let (nodes, _) = parseFixture(
    content: "1 0 0 rg q 0 1 0 rg 10 10 20 20 re f Q 50 10 20 20 re f")
  guard case .path(let green) = nodes[0], case .path(let red) = nodes[1] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(green.style.fill == .color(RGBA(red: 0, green: 1, blue: 0)))
  #expect(red.style.fill == .color(RGBA(red: 1, green: 0, blue: 0)))
}

@Test func extGStateSetsFillAlpha() {
  let (nodes, _) = parseFixture(
    content: "/GS1 gs 10 10 20 20 re f",
    resources: "<< /ExtGState << /GS1 5 0 R >> >>",
    extraObjects: ["<< /Type /ExtGState /ca 0.5 >>"])
  #expect(firstPath(nodes)?.style.opacity == 0.5)
}

@Test func dashArrayIsParsed() {
  let (nodes, _) = parseFixture(content: "[3 2] 0 d 10 10 m 100 10 l S")
  #expect(firstPath(nodes)?.style.stroke?.dash == [3, 2])
}

@Test func bStarFillsAndStrokesWithClose() {
  let (nodes, _) = parseFixture(
    content: "1 0 0 rg 0 0 1 RG 10 10 m 100 10 l 100 100 l b")
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.style.fill != nil)
  #expect(pathNode.style.stroke != nil)
  #expect(pathNode.path.subpaths[0].isClosed)
}

@Test func patternFillIsReportedAndSkipped() {
  let (nodes, report) = parseFixture(
    content: "/Pattern cs /P1 scn 10 10 20 20 re f")
  // 채움은 직전 색(기본 검정) 유지로 그려진다 — 색만 부정확, 도형은 보존
  #expect(nodes.count == 1)
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
}

@Test func curveShorthandOperatorsParse() {
  // v: control1 = 현재 점, y: control2 = 종점 (PDF §8.5.2)
  let (nodes, _) = parseFixture(
    content: "10 10 m 20 30 40 10 v 60 30 80 10 y S")
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  let segments = pathNode.path.subpaths[0].segments
  guard case .curve(let vTo, let vControl1, _) = segments[1],
    case .curve(let yTo, _, let yControl2) = segments[2]
  else {
    Issue.record("곡선이 아님")
    return
  }
  // 모델 좌표(플립 적용): PDF (10,10) → (10,190), (40,10) → (40,190), (80,10) → (80,190)
  #expect(vControl1 == CGPoint(x: 10, y: 190))  // v의 control1 = 직전 현재 점
  #expect(vTo == CGPoint(x: 40, y: 190))
  #expect(yControl2 == yTo)  // y의 control2 = 종점
  #expect(yTo == CGPoint(x: 80, y: 190))
}
