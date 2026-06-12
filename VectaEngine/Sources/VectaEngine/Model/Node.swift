import CoreGraphics
import Foundation

/// 면 채움 규칙. PDF의 f(winding)/f*(even-odd) 매핑 (스펙 §5).
public enum FillRule: String, Codable, Sendable {
  case winding
  case evenOdd
}

public struct PathNode: Equatable, Codable, Sendable {
  public let id: NodeID
  public var path: BezierPath
  public var style: Style
  public var transform: Transform2D
  /// M4a에 추가 — 기존 파일(키 없음)은 winding으로 디코드된다.
  public var fillRule: FillRule

  public init(
    id: NodeID = NodeID(), path: BezierPath, style: Style,
    transform: Transform2D = .identity, fillRule: FillRule = .winding
  ) {
    self.id = id
    self.path = path
    self.style = style
    self.transform = transform
    self.fillRule = fillRule
  }

  private enum CodingKeys: String, CodingKey {
    case id, path, style, transform, fillRule
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(NodeID.self, forKey: .id)
    path = try container.decode(BezierPath.self, forKey: .path)
    style = try container.decode(Style.self, forKey: .style)
    transform = try container.decode(Transform2D.self, forKey: .transform)
    fillRule = try container.decodeIfPresent(FillRule.self, forKey: .fillRule) ?? .winding
  }
}

public struct GroupNode: Equatable, Codable, Sendable {
  public let id: NodeID
  public var children: [Node]
  public var clipPath: BezierPath?
  public var transform: Transform2D

  public init(
    id: NodeID = NodeID(), children: [Node],
    clipPath: BezierPath? = nil, transform: Transform2D = .identity
  ) {
    self.id = id
    self.children = children
    self.clipPath = clipPath
    self.transform = transform
  }
}

public struct TextNode: Equatable, Codable, Sendable {
  public let id: NodeID
  public var string: String
  public var fontName: String
  public var fontSize: Double
  public var fill: Paint
  public var position: CGPoint
  public var transform: Transform2D

  public init(
    id: NodeID = NodeID(), string: String, fontName: String,
    fontSize: Double, fill: Paint, position: CGPoint,
    transform: Transform2D = .identity
  ) {
    self.id = id
    self.string = string
    self.fontName = fontName
    self.fontSize = fontSize
    self.fill = fill
    self.position = position
    self.transform = transform
  }
}

public struct ImageNode: Equatable, Codable, Sendable {
  public let id: NodeID
  public var imageData: Data
  public var frame: CGRect
  public var transform: Transform2D

  public init(
    id: NodeID = NodeID(), imageData: Data, frame: CGRect,
    transform: Transform2D = .identity
  ) {
    self.id = id
    self.imageData = imageData
    self.frame = frame
    self.transform = transform
  }
}

public enum Node: Equatable, Codable, Sendable {
  case path(PathNode)
  case group(GroupNode)
  case text(TextNode)
  case image(ImageNode)

  public var id: NodeID {
    switch self {
    case .path(let node): return node.id
    case .group(let node): return node.id
    case .text(let node): return node.id
    case .image(let node): return node.id
    }
  }
}
