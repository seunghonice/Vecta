import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@Test func rectangleFactoryProducesClosedSubpath() {
  let path = BezierPath.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50))
  #expect(path.subpaths.count == 1)
  let subpath = path.subpaths[0]
  #expect(subpath.isClosed)
  // move + 3 lines (마지막 변은 close가 담당)
  #expect(subpath.segments.count == 4)
  #expect(subpath.segments[0] == .move(to: CGPoint(x: 10, y: 20)))
}

@Test func ellipseFactoryProducesFourCurves() {
  let path = BezierPath.ellipse(in: CGRect(x: 0, y: 0, width: 100, height: 60))
  let subpath = path.subpaths[0]
  #expect(subpath.isClosed)
  let curveCount = subpath.segments.filter {
    if case .curve = $0 { return true } else { return false }
  }.count
  #expect(curveCount == 4)
}

@Test func cgPathBoundingBoxMatchesSourceRect() {
  let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
  #expect(BezierPath.rectangle(rect).cgPath.boundingBox == rect)
}

@Test func ellipseCGPathBoundingBoxMatchesRect() {
  let rect = CGRect(x: 5, y: 5, width: 80, height: 40)
  let box = BezierPath.ellipse(in: rect).cgPath.boundingBox
  #expect(abs(box.minX - rect.minX) < 0.001)
  #expect(abs(box.minY - rect.minY) < 0.001)
  #expect(abs(box.maxX - rect.maxX) < 0.001)
  #expect(abs(box.maxY - rect.maxY) < 0.001)
}

@Test func bezierPathCodableRoundTrip() throws {
  let original = BezierPath.ellipse(in: CGRect(x: 1, y: 2, width: 3, height: 4))
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(BezierPath.self, from: data)
  #expect(decoded == original)
}

@Test func rectFromCornersNormalizesNegativeDrag() {
  let rect = CGRect(corner: CGPoint(x: 100, y: 80), oppositeCorner: CGPoint(x: 40, y: 20))
  #expect(rect == CGRect(x: 40, y: 20, width: 60, height: 60))
}

@Test func decodingLineFirstSubpathThrows() {
  let json = #"{"isClosed":false,"segments":[{"line":{"to":[5,5]}}]}"#
  #expect(throws: DecodingError.self) {
    try JSONDecoder().decode(Subpath.self, from: Data(json.utf8))
  }
}

@Test func decodingValidSubpathStillWorks() throws {
  let original = Subpath(
    segments: [.move(to: CGPoint(x: 1, y: 2)), .line(to: CGPoint(x: 3, y: 4))],
    isClosed: false)
  let data = try JSONEncoder().encode(original)
  #expect(try JSONDecoder().decode(Subpath.self, from: data) == original)
}
