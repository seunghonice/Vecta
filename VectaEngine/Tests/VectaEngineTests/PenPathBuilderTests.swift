import CoreGraphics
import Testing

@testable import VectaEngine

@Test func cornerClicksBuildOpenPolyline() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.addAnchor(at: CGPoint(x: 50, y: 0))
  builder.addAnchor(at: CGPoint(x: 50, y: 50))
  let path = builder.finishOpen()
  #expect(path != nil)
  let segments = path!.subpaths[0].segments
  #expect(segments.count == 3)
  #expect(segments[0] == .move(to: .zero))
  #expect(segments[1] == .line(to: CGPoint(x: 50, y: 0)))
  #expect(segments[2] == .line(to: CGPoint(x: 50, y: 50)))
  #expect(!path!.subpaths[0].isClosed)
}

@Test func singleAnchorFinishDiscards() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: .zero)
  #expect(builder.finishOpen() == nil)
  #expect(builder.anchorCount == 0)  // finish 후 리셋
}

@Test func dragAfterAnchorCreatesSmoothSegments() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.dragHandle(to: CGPoint(x: 20, y: 0))  // 시작 앵커 나가는 핸들
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  let path = builder.finishOpen()!
  guard case .curve(let to, let control1, let control2) = path.subpaths[0].segments[1] else {
    Issue.record("곡선이 아님")
    return
  }
  #expect(to == CGPoint(x: 100, y: 0))
  #expect(control1 == CGPoint(x: 20, y: 0))  // pendingLeading 소비
  #expect(control2 == CGPoint(x: 100, y: 0))  // 아직 안 드래그된 끝 — 퇴화
}

@Test func dragOnLaterAnchorConvertsIncomingLineToCurve() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.addAnchor(at: CGPoint(x: 100, y: 0))  // line
  builder.dragHandle(to: CGPoint(x: 120, y: 20))  // 미러 = (80, -20)
  let path = builder.finishOpen()!
  guard case .curve(let to, let control1, let control2) = path.subpaths[0].segments[1] else {
    Issue.record("곡선 전환 안 됨")
    return
  }
  #expect(to == CGPoint(x: 100, y: 0))
  #expect(control1 == CGPoint(x: 0, y: 0))  // 이전 앵커 쪽 퇴화 핸들
  #expect(control2 == CGPoint(x: 80, y: -20))  // 미러
}

@Test func canCloseRequiresTwoAnchorsAndProximity() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  #expect(!builder.canClose(at: CGPoint(x: 1, y: 1), tolerance: 6))
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  #expect(builder.canClose(at: CGPoint(x: 3, y: 4), tolerance: 6))  // 거리 5 ≤ 6
  #expect(!builder.canClose(at: CGPoint(x: 30, y: 0), tolerance: 6))
}

@Test func closeAllLinesUsesImplicitClosingEdge() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  builder.addAnchor(at: CGPoint(x: 50, y: 80))
  let path = builder.close()!
  let subpath = path.subpaths[0]
  #expect(subpath.isClosed)
  #expect(subpath.segments.count == 3)  // 명시적 닫힘 세그먼트 없음
}

@Test func closeWithHandlesAppendsClosingCurveWithMirroredStart() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.dragHandle(to: CGPoint(x: 10, y: -10))  // 시작 나가는 핸들 → 미러 (−10, 10)
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  builder.dragHandle(to: CGPoint(x: 120, y: 10))
  let path = builder.close()!
  let subpath = path.subpaths[0]
  #expect(subpath.isClosed)
  guard case .curve(let to, let control1, let control2) = subpath.segments.last! else {
    Issue.record("닫힘 곡선이 아님")
    return
  }
  #expect(to == CGPoint(x: 0, y: 0))
  #expect(control1 == CGPoint(x: 120, y: 10))  // 마지막 나가는 핸들
  #expect(control2 == CGPoint(x: -10, y: 10))  // 시작 핸들 미러
  // 닫힘 패스는 디코드 불변식(.move 시작)도 유지
  #expect(subpath.segments.first == .move(to: .zero))
}
