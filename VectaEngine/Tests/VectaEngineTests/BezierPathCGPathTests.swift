import CoreGraphics
import Testing

@testable import VectaEngine

@Test func rectangleRoundTripsThroughCGPath() {
  let original = BezierPath.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50))
  let roundTripped = BezierPath(cgPath: original.cgPath)
  #expect(roundTripped == original)
}

@Test func ellipseRoundTripsThroughCGPath() {
  let original = BezierPath.ellipse(in: CGRect(x: 0, y: 0, width: 80, height: 60))
  let roundTripped = BezierPath(cgPath: original.cgPath)
  #expect(roundTripped == original)
}

@Test func quadCurveIsPromotedToCubic() {
  let cgPath = CGMutablePath()
  cgPath.move(to: .zero)
  cgPath.addQuadCurve(to: CGPoint(x: 90, y: 0), control: CGPoint(x: 45, y: 60))
  let path = BezierPath(cgPath: cgPath)
  guard case .curve(let to, let control1, let control2) = path.subpaths[0].segments[1] else {
    Issue.record("3차 곡선이 아님")
    return
  }
  #expect(to == CGPoint(x: 90, y: 0))
  // c1 = p0 + 2/3(q − p0) = (30, 40), c2 = p + 2/3(q − p) = (60, 40)
  #expect(abs(control1.x - 30) < 0.0001 && abs(control1.y - 40) < 0.0001)
  #expect(abs(control2.x - 60) < 0.0001 && abs(control2.y - 40) < 0.0001)
}

@Test func multipleSubpathsArePreserved() {
  let cgPath = CGMutablePath()
  cgPath.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
  cgPath.move(to: CGPoint(x: 50, y: 50))
  cgPath.addLine(to: CGPoint(x: 80, y: 50))
  let path = BezierPath(cgPath: cgPath)
  #expect(path.subpaths.count == 2)
  #expect(path.subpaths[0].isClosed)
  #expect(!path.subpaths[1].isClosed)
}

@Test func segmentAfterCloseStartsNewSubpathAtStartPoint() {
  let cgPath = CGMutablePath()
  cgPath.move(to: .zero)
  cgPath.addLine(to: CGPoint(x: 10, y: 0))
  cgPath.closeSubpath()
  cgPath.addLine(to: CGPoint(x: 0, y: 20))  // 닫힘 뒤 — 시작점에서 새 subpath
  let path = BezierPath(cgPath: cgPath)
  #expect(path.subpaths.count == 2)
  #expect(path.subpaths[1].segments[0] == .move(to: .zero))
  #expect(path.subpaths[1].segments[1] == .line(to: CGPoint(x: 0, y: 20)))
}

@Test func applyingTransformsEveryPoint() {
  let path = BezierPath.ellipse(in: CGRect(x: 0, y: 0, width: 40, height: 40))
  let moved = path.applying(CGAffineTransform(translationX: 100, y: 50))
  #expect(moved.bounds == CGRect(x: 100, y: 50, width: 40, height: 40))
  #expect(moved.subpaths[0].segments.count == path.subpaths[0].segments.count)
}
