import CoreGraphics
import Testing

@testable import VectaEngine

private let rgbFunction = "<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"

private func axialShading(coords: String) -> String {
  "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [\(coords)] /Function \(rgbFunction) >>"
}

@Test func shFillsClipRegionWithLinearGradient() {
  // W n 으로 클립을 잡고 sh — 클립 사각형이 그라디언트 fill 패스가 된다.
  let (nodes, report) = parseFixture(
    content: "10 10 80 80 re W n /Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [axialShading(coords: "10 10 90 10")])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  guard case .linearGradient(let gradient) = pathNode.style.fill else {
    Issue.record("선형 그라디언트가 아님")
    return
  }
  // 클립 (10,10,80,80) PDF → 모델 y 110…190
  #expect(pathNode.path.bounds == CGRect(x: 10, y: 110, width: 80, height: 80))
  // 그라디언트 좌표 베이크: PDF (10,10)→(90,10) → 모델 (10,190)→(90,190)
  #expect(gradient.start == CGPoint(x: 10, y: 190))
  #expect(gradient.end == CGPoint(x: 90, y: 190))
  #expect(gradient.stops.count == 9)
}

@Test func shWithoutClipFillsMediaBox() {
  let (nodes, _) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [axialShading(coords: "0 0 200 0")])
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  // 클립 없음 → mediaBox 전체 (모델 0,0,200,200)
  #expect(pathNode.path.bounds == CGRect(x: 0, y: 0, width: 200, height: 200))
  #expect(pathNode.style.fill != nil)
}

@Test func shRadialProducesRadialGradient() {
  let radialShading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [100 100 0 100 100 50] "
    + "/Function \(rgbFunction) >>"
  let (nodes, _) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [radialShading])
  guard case .path(let pathNode) = nodes[0],
    case .radialGradient = pathNode.style.fill
  else {
    Issue.record("원형 그라디언트가 아님")
    return
  }
}

@Test func unsupportedShadingStillReports() {
  // mesh(type 4) → 변환 실패, 리포트, 노드 없음
  let mesh = "<< /ShadingType 4 /ColorSpace /DeviceRGB >>"
  let (nodes, report) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [mesh])
  #expect(nodes.isEmpty)
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
}

@Test func radialLossyApproximationReports() {
  let radialShading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [100 100 20 100 100 50] "
    + "/Function \(rgbFunction) >>"
  let (_, report) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [radialShading])
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
}

@Test func shBakesShadingCoordsUnderCTM() {
  // cm 2배 스케일 — 셰이딩 좌표가 CTM×pageFlip로 베이크된다.
  // PDF (0,0)→(50,0) 에 cm ×2 적용 → (0,0)→(100,0), 그 뒤 pageFlip(높이 200)
  // → 모델 (0,200)→(100,200)
  let (nodes, _) = parseFixture(
    content: "q 2 0 0 2 0 0 cm /Sh0 sh Q",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [axialShading(coords: "0 0 50 0")])
  guard case .path(let pathNode) = nodes[0],
    case .linearGradient(let gradient) = pathNode.style.fill
  else {
    Issue.record("선형 그라디언트가 아님")
    return
  }
  #expect(gradient.start == CGPoint(x: 0, y: 200))
  #expect(gradient.end == CGPoint(x: 100, y: 200))
}

@Test func shArrayFunctionReportsLossyFunction() {
  // /Function 배열(성분별 분리) 첫 함수가 3출력 → 변환 성공하되 근사 리포트
  let first = "<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"
  let second = "<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>"
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] "
    + "/Function [\(first) \(second)] >>"
  let (nodes, report) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [shading])
  #expect(nodes.count == 1)  // 변환 성공
  #expect(report.issues.contains { $0.detail.contains("성분별 분리 함수") })
}

// MARK: - 패턴 채움

@Test func shadingPatternFillsPathWithGradient() {
  // cs /Pattern + scn /P1 + 패스 f — 패턴의 shading이 패스 fill 그라디언트가 된다.
  let pattern =
    "<< /Type /Pattern /PatternType 2 /Matrix [1 0 0 1 0 0] "
    + "/Shading \(axialShading(coords: "0 0 100 0")) >>"
  let (nodes, report) = parseFixture(
    content: "/Pattern cs /P1 scn 10 10 80 80 re f",
    resources: "<< /Pattern << /P1 5 0 R >> >>",
    extraObjects: [pattern])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0],
    case .linearGradient(let gradient) = pathNode.style.fill
  else {
    Issue.record("선형 그라디언트 fill이 아님")
    return
  }
  // 패스 (10,10,80,80) PDF → 모델 y 110…190
  #expect(pathNode.path.bounds == CGRect(x: 10, y: 110, width: 80, height: 80))
  // 패턴 좌표 베이크(Matrix identity × pageFlip): PDF (0,0)→(100,0) → 모델 (0,200)→(100,200)
  #expect(gradient.start == CGPoint(x: 0, y: 200))
  #expect(gradient.end == CGPoint(x: 100, y: 200))
}

@Test func shadingPatternHonorsPatternMatrix() {
  // /Matrix 평행이동 50 — 그라디언트 좌표가 따라 이동
  let pattern =
    "<< /Type /Pattern /PatternType 2 /Matrix [1 0 0 1 50 0] "
    + "/Shading \(axialShading(coords: "0 0 100 0")) >>"
  let (nodes, _) = parseFixture(
    content: "/Pattern cs /P1 scn 0 0 200 200 re f",
    resources: "<< /Pattern << /P1 5 0 R >> >>",
    extraObjects: [pattern])
  guard case .path(let pathNode) = nodes[0],
    case .linearGradient(let gradient) = pathNode.style.fill
  else {
    Issue.record("그라디언트가 아님")
    return
  }
  // (0,0)+50 → 모델 (50,200), (100,0)+50 → (150,200)
  #expect(gradient.start == CGPoint(x: 50, y: 200))
  #expect(gradient.end == CGPoint(x: 150, y: 200))
}

@Test func tilingPatternIsReportedAndFillSkipped() {
  // PatternType 1(tiling) → 미지원, fill 없음(패스만)
  let tiling =
    "<< /Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 "
    + "/BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >> /Length 0 >> stream\n\nendstream"
  let (nodes, report) = parseFixture(
    content: "/Pattern cs /P1 scn 10 10 80 80 re f",
    resources: "<< /Pattern << /P1 5 0 R >> >>",
    extraObjects: [tiling])
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.style.fill == nil)  // 채움 스킵, 도형은 보존
}
