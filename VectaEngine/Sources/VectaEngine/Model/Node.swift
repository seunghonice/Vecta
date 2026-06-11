import CoreGraphics
import Foundation

public struct PathNode: Equatable, Codable, Sendable {
  public let id: NodeID
  public var path: BezierPath
  public var style: Style
  public var transform: Transform2D

  public init(
    id: NodeID = NodeID(), path: BezierPath, style: Style,
    transform: Transform2D = .identity
  ) {
    self.id = id
    self.path = path
    self.style = style
    self.transform = transform
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
