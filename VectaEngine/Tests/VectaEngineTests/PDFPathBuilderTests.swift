import CoreGraphics
import Testing

@testable import VectaEngine

@Test func polylineBuildsOpenSubpath() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  builder.line(to: CGPoint(x: 10, y: 10))
  let path = builder.finish()
  #expect(path.subpaths.count == 1)
  #expect(!path.subpaths[0].isClosed)
  #expect(path.subpaths[0].segments.count == 3)
}

@Test func moveStartsNewSubpath() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  builder.move(to: CGPoint(x: 50, y: 50))
  builder.line(to: CGPoint(x: 60, y: 50))
  let path = builder.finish()
  #expect(path.subpaths.count == 2)
}

@Test func curveVariantsMapControls() {
  // v: control1 = 현재 점, y: control2 = 종점 (PDF §8.5.2)
  var builder = PDFPathBuilder()
  builder.move(to: CGPoint(x: 0, y: 0))
  builder.curveV(to: CGPoint(x: 30, y: 0), control2: CGPoint(x: 20, y: 10))
  builder.curveY(to: CGPoint(x: 60, y: 0), control1: CGPoint(x: 40, y: 10))
  let path = builder.finish()
  guard case .curve(_, let vControl1, _) = path.subpaths[0].segments[1],
    case .curve(let yTo, _, let yControl2) = path.subpaths[0].segments[2]
  else {
    Issue.record("곡선이 아님")
    return
  }
  #expect(vControl1 == CGPoint(x: 0, y: 0))
  #expect(yControl2 == yTo)
}

@Test func closeThenLineStartsNewSubpathAtStart() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  builder.line(to: CGPoint(x: 10, y: 10))
  builder.close()
  builder.line(to: CGPoint(x: -5, y: -5))  // h 뒤 — 시작점에서 이어진다
  let path = builder.finish()
  #expect(path.subpaths.count == 2)
  #expect(path.subpaths[0].isClosed)
  #expect(path.subpaths[1].segments[0] == .move(to: .zero))
  #expect(path.subpaths[1].segments[1] == .line(to: CGPoint(x: -5, y: -5)))
}

@Test func rectAppendsClosedSubpath() {
  var builder = PDFPathBuilder()
  builder.rect(CGRect(x: 5, y: 5, width: 20, height: 10))
  let path = builder.finish()
  #expect(path.subpaths.count == 1)
  #expect(path.subpaths[0].isClosed)
  #expect(path.bounds == CGRect(x: 5, y: 5, width: 20, height: 10))
}

@Test func finishResetsBuilder() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  _ = builder.finish()
  #expect(builder.finish().subpaths.isEmpty)
}
