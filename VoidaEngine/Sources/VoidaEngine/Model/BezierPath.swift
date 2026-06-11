import CoreGraphics

/// 베지어 패스 한 구간. 첫 세그먼트는 항상 `.move`다.
public enum PathSegment: Equatable, Codable, Sendable {
  case move(to: CGPoint)
  case line(to: CGPoint)
  case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
}

public struct Subpath: Equatable, Codable, Sendable {
  public var segments: [PathSegment]
  public var isClosed: Bool

  public init(segments: [PathSegment], isClosed: Bool) {
    self.segments = segments
    self.isClosed = isClosed
  }
}

public struct BezierPath: Equatable, Codable, Sendable {
  public var subpaths: [Subpath]

  public init(subpaths: [Subpath]) {
    self.subpaths = subpaths
  }
}
