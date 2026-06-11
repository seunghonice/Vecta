public struct Layer: Equatable, Codable, Sendable {
  public let id: NodeID
  public var name: String
  public var isVisible: Bool
  public var isLocked: Bool
  public var nodes: [Node]

  public init(
    id: NodeID = NodeID(), name: String,
    isVisible: Bool = true, isLocked: Bool = false, nodes: [Node] = []
  ) {
    self.id = id
    self.name = name
    self.isVisible = isVisible
    self.isLocked = isLocked
    self.nodes = nodes
  }
}
