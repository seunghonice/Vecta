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

// MARK: - 클리핑

@Test func clipWrapsSubsequentNodesInGroup() {
  let (nodes, _) = parseFixture(
    content: "10 10 100 100 re W n 0 0 1 rg 0 0 200 200 re f")
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  // 클립 사각형: PDF (10,10,100,100) → 모델 y 90…190
  #expect(group.clipPath?.bounds == CGRect(x: 10, y: 90, width: 100, height: 100))
  #expect(group.children.count == 1)
}

@Test func clipIsRestoredByQ() {
  let (nodes, _) = parseFixture(
    content: "q 10 10 50 50 re W n 0 0 200 200 re f Q 0 0 20 20 re f")
  #expect(nodes.count == 2)
  guard case .group = nodes[0], case .path = nodes[1] else {
    Issue.record("구조가 다름 — 클립 그룹 + 최상위 패스여야 함")
    return
  }
}

@Test func nestedClipsIntersect() {
  let (nodes, _) = parseFixture(
    content: "0 0 100 100 re W n 50 50 100 100 re W n 0 0 200 200 re f")
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  // 교차: PDF (50,50)…(100,100) → 모델 y 100…150
  #expect(group.clipPath?.bounds == CGRect(x: 50, y: 100, width: 50, height: 50))
}

@Test func consecutiveNodesUnderSameClipShareOneGroup() {
  let (nodes, _) = parseFixture(
    content: "10 10 150 150 re W n 20 20 30 30 re f 60 20 30 30 re f")
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  #expect(group.children.count == 2)
}

@Test func clipWithCombinedPaintUsesOldClipForThatPaint() {
  // W f — 같은 연산자에서 클립+페인트: 페인트는 이전 클립(없음) 아래 (§8.5.4),
  // 클립은 그 다음 페인팅부터 적용된다.
  let (nodes, _) = parseFixture(
    content: "10 10 100 100 re W f 0 0 200 200 re f")
  #expect(nodes.count == 2)
  guard case .path = nodes[0], case .group(let clipped) = nodes[1] else {
    Issue.record("첫 노드는 최상위 패스, 둘째는 클립 그룹이어야 함")
    return
  }
  #expect(clipped.clipPath?.bounds == CGRect(x: 10, y: 90, width: 100, height: 100))
}

@Test func evenOddClipPreservesHole() {
  // 도넛(동일 방향 사각형 2개)을 W*로 클립 — 짝홀 정규화로 구멍이 보존된다.
  // 구멍 안에 칠한 패스는 클립 결과(구멍 제외)와 교차하지 않지만, 클립
  // 그룹의 clipPath 바운드는 외곽 사각형이어야 한다.
  let (nodes, _) = parseFixture(
    content: "20 20 160 160 re 70 70 60 60 re W* n 0 0 200 200 re f")
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  #expect(group.clipPath?.bounds == CGRect(x: 20, y: 20, width: 160, height: 160))
  // 짝홀 정규화 결과는 단일 사각형이 아니라 구멍을 포함한 복합 패스다
  #expect((group.clipPath?.subpaths.count ?? 0) >= 2)
}

// MARK: - 폼 XObject

@Test func formXObjectBecomesGroupWithMatrixApplied() {
  let formContent = "1 0 0 rg 0 0 20 20 re f"
  let form =
    "<< /Type /XObject /Subtype /Form /BBox [0 0 200 200] "
    + "/Matrix [1 0 0 1 50 0] /Length \(formContent.utf8.count) >> stream\n"
    + "\(formContent)\nendstream"
  let (nodes, report) = parseFixture(
    content: "/F0 Do",
    resources: "<< /XObject << /F0 5 0 R >> >>",
    extraObjects: [form])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("폼 그룹이 아님")
    return
  }
  #expect(group.children.count == 1)
  // /Matrix 평행이동 50 적용: PDF (50,0,20,20) → 모델 (50, 180, 20, 20)
  #expect(group.children[0].bounds == CGRect(x: 50, y: 180, width: 20, height: 20))
}

@Test func formBBoxClipsContent() {
  // BBox (0,0,30,30) 밖으로 그리는 폼 — BBox가 클립으로 적용된다
  let formContent = "1 0 0 rg 0 0 99 99 re f"
  let form =
    "<< /Type /XObject /Subtype /Form /BBox [0 0 30 30] "
    + "/Length \(formContent.utf8.count) >> stream\n\(formContent)\nendstream"
  let (nodes, _) = parseFixture(
    content: "/F0 Do",
    resources: "<< /XObject << /F0 5 0 R >> >>",
    extraObjects: [form])
  guard case .group(let outerGroup) = nodes[0],
    case .group(let clipGroup) = outerGroup.children[0]
  else {
    Issue.record("폼 그룹 안에 클립 그룹이어야 함")
    return
  }
  #expect(clipGroup.clipPath?.bounds == CGRect(x: 0, y: 170, width: 30, height: 30))
}

@Test func missingXObjectIsSilentlySkipped() {
  let (nodes, _) = parseFixture(content: "/Nope Do 10 10 20 20 re f")
  #expect(nodes.count == 1)  // Do 실패해도 이후 파싱 계속
}

@Test func selfReferencingFormDoesNotRecurse() {
  // CGPDFContentStreamGetResource는 폼 콘텐츠 스트림 안에서 부모 스트림(페이지)
  // 리소스로 폴백하지 않는다. 따라서 폼 안에서 동일 이름의 XObject를 Do 해도
  // 리소스 조회가 nil 을 반환해 재귀가 발생하지 않는다.
  // 이 테스트는 해당 CGPDF 동작을 잠근다 — formRecursionLimit 가드가
  // 이 경로에서 트리거되지 않음을 명시한다.
  let formContent = "/F0 Do 1 0 0 rg 0 0 10 10 re f"
  let form =
    "<< /Type /XObject /Subtype /Form /BBox [0 0 200 200] "
    + "/Length \(formContent.utf8.count) >> stream\n\(formContent)\nendstream"
  let (nodes, report) = parseFixture(
    content: "/F0 Do",
    resources: "<< /XObject << /F0 5 0 R >> >>",
    extraObjects: [form])
  // CGPDF가 폼 내부에서 부모 리소스를 조회하지 않으므로 재귀 없음
  #expect(!report.issues.contains { $0.kind == .formRecursionLimit })
  #expect(nodes.count == 1)  // 폼 안의 사각형 하나만 파싱
}

@Test func imageXObjectIsReported() {
  let image =
    "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 "
    + "/ColorSpace /DeviceRGB /Length 3 >> stream\nABC\nendstream"
  let (nodes, report) = parseFixture(
    content: "/Im0 Do 10 10 20 20 re f",
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [image])
  #expect(nodes.count == 1)  // 이미지는 건너뛰고 파싱 계속
  #expect(report.issues.contains { $0.kind == .unsupportedImage })
}
