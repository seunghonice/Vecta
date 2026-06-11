import CoreGraphics

/// 베지어 패스 한 구간. 첫 세그먼트는 항상 `.move`다.
public enum PathSegment: Equatable, Codable, Sendable {
  case move(to: CGPoint)
  case line(to: CGPoint)
  case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
}

extension PathSegment {
  var isMove: Bool {
    if case .move = self { return true }
    return false
  }
}

public struct Subpath: Equatable, Codable, Sendable {
  public var segments: [PathSegment]
  public var isClosed: Bool

  public init(segments: [PathSegment], isClosed: Bool) {
    if let first = segments.first {
      guard first.isMove else {
        preconditionFailure("Subpath의 첫 세그먼트는 반드시 .move 여야 합니다")
      }
    }
    self.segments = segments
    self.isClosed = isClosed
  }

  private enum CodingKeys: String, CodingKey {
    case segments
    case isClosed
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let segments = try container.decode([PathSegment].self, forKey: .segments)
    let isClosed = try container.decode(Bool.self, forKey: .isClosed)
    if let first = segments.first, !first.isMove {
      throw DecodingError.dataCorruptedError(
        forKey: .segments,
        in: container,
        debugDescription: "Subpath의 첫 세그먼트는 반드시 .move 여야 합니다")
    }
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
