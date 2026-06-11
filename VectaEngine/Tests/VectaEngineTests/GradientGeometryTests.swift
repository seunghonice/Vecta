import CoreGraphics
import Testing

@testable import VectaEngine

private func expectClose(
  _ point: CGPoint, _ expected: CGPoint,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(abs(point.x - expected.x) < 0.0001, sourceLocation: sourceLocation)
  #expect(abs(point.y - expected.y) < 0.0001, sourceLocation: sourceLocation)
}

@Test func angleZeroSpansBoundsLeftToRight() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let line = GradientGeometry.line(angleDegrees: 0, in: bounds)
  expectClose(line.start, CGPoint(x: 0, y: 25))
  expectClose(line.end, CGPoint(x: 100, y: 25))
}

@Test func angleNinetySpansBoundsTopToBottom() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let line = GradientGeometry.line(angleDegrees: 90, in: bounds)
  expectClose(line.start, CGPoint(x: 50, y: 0))
  expectClose(line.end, CGPoint(x: 50, y: 50))
}

@Test func angleRoundTripsThroughLine() {
  let bounds = CGRect(x: 10, y: 20, width: 80, height: 60)
  let line = GradientGeometry.line(angleDegrees: 30, in: bounds)
  let gradient = Gradient(stops: [], start: line.start, end: line.end)
  #expect(abs(GradientGeometry.angleDegrees(of: gradient) - 30) < 0.0001)
}

@Test func zeroLengthGradientAngleIsZero() {
  let gradient = Gradient(stops: [], start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5))
  #expect(GradientGeometry.angleDegrees(of: gradient) == 0)
}

@Test func defaultLinearPreservesBaseColorAndSpansBounds() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let red = RGBA(red: 1, green: 0, blue: 0)
  let gradient = Gradient.defaultLinear(from: red, in: bounds)
  #expect(gradient.stops.count == 2)
  #expect(gradient.stops[0].color == red)
  #expect(gradient.stops[0].location == 0)
  #expect(gradient.stops[1].color == .white)
  #expect(gradient.stops[1].location == 1)
  expectClose(gradient.start, CGPoint(x: 0, y: 25))
  expectClose(gradient.end, CGPoint(x: 100, y: 25))
}

@Test func defaultRadialCentersInBounds() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let gradient = Gradient.defaultRadial(from: .black, in: bounds)
  expectClose(gradient.start, CGPoint(x: 50, y: 25))
  expectClose(gradient.end, CGPoint(x: 100, y: 50))
}
