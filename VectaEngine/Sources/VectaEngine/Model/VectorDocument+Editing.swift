import Foundation

extension VectorDocument {
  /// 모든 레이어의 최상위 노드 ID (그룹 내부 제외 — M2a 선택 단위).
  public var topLevelNodeIDs: Set<NodeID> {
    Set(layers.flatMap { $0.nodes.map(\.id) })
  }

  public func topLevelNode(id: NodeID) -> Node? {
    for layer in layers {
      if let node = layer.nodes.first(where: { $0.id == id }) {
        return node
      }
    }
    return nil
  }

  public mutating func updateTopLevelNodes(ids: Set<NodeID>, _ change: (Node) -> Node) {
    for layerIndex in layers.indices {
      for nodeIndex in layers[layerIndex].nodes.indices
      where ids.contains(layers[layerIndex].nodes[nodeIndex].id) {
        layers[layerIndex].nodes[nodeIndex] = change(layers[layerIndex].nodes[nodeIndex])
      }
    }
  }

  public mutating func removeTopLevelNodes(ids: Set<NodeID>) {
    for layerIndex in layers.indices {
      layers[layerIndex].nodes.removeAll { ids.contains($0.id) }
    }
  }
}
