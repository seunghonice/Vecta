import CoreGraphics
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

extension VectorDocument {
  /// 선택된 최상위 노드들을 하나의 그룹으로 묶는다. 그룹은 최전면(z-순서 맨
  /// 위) 선택 노드 자리에 들어가고, 자식 순서는 문서 z-순서를 따른다.
  /// 여러 레이어에 걸치면 최전면 노드의 레이어로 모인다.
  @discardableResult
  public mutating func groupTopLevelNodes(ids: Set<NodeID>) -> NodeID? {
    var collected: [Node] = []
    var frontmostID: NodeID?
    for layer in layers {
      for node in layer.nodes where ids.contains(node.id) {
        collected.append(node)
        frontmostID = node.id
      }
    }
    guard let frontmostID else { return nil }
    let group = GroupNode(children: collected)
    updateTopLevelNodes(ids: [frontmostID]) { _ in .group(group) }
    removeTopLevelNodes(ids: ids.subtracting([frontmostID]))
    return group.id
  }

  /// 선택된 최상위 그룹을 제자리에서 자식으로 푼다. 그룹 transform은 자식에
  /// 합성되고 clipPath는 폐기된다 (Illustrator 클리핑 마스크 해제 의미).
  /// 그룹이 아닌 노드는 건드리지 않는다. 풀린 자식 ID 집합을 반환.
  @discardableResult
  public mutating func ungroupTopLevelNodes(ids: Set<NodeID>) -> Set<NodeID> {
    var released: Set<NodeID> = []
    for layerIndex in layers.indices {
      layers[layerIndex].nodes = layers[layerIndex].nodes.flatMap { node -> [Node] in
        guard ids.contains(node.id), case .group(let group) = node else { return [node] }
        let children = group.children.map {
          NodeTransformer.applying(group.transform.cgAffineTransform, to: $0)
        }
        released.formUnion(children.map(\.id))
        return children
      }
    }
    return released
  }

  /// 같은 레이어 안에서 한 칸 앞으로(배열 뒤쪽 = 위). 맨 위 또는 바로 위가
  /// 같은 선택이면 그대로 — 인접 선택 묶음은 통째로 막힌다.
  public mutating func bringForwardTopLevelNodes(ids: Set<NodeID>) {
    for layerIndex in layers.indices {
      var nodes = layers[layerIndex].nodes
      guard nodes.count > 1 else { continue }
      for index in stride(from: nodes.count - 2, through: 0, by: -1)
      where ids.contains(nodes[index].id) && !ids.contains(nodes[index + 1].id) {
        nodes.swapAt(index, index + 1)
      }
      layers[layerIndex].nodes = nodes
    }
  }

  /// 같은 레이어 안에서 한 칸 뒤로(배열 앞쪽 = 아래).
  public mutating func sendBackwardTopLevelNodes(ids: Set<NodeID>) {
    for layerIndex in layers.indices {
      var nodes = layers[layerIndex].nodes
      guard nodes.count > 1 else { continue }
      for index in 1..<nodes.count
      where ids.contains(nodes[index].id) && !ids.contains(nodes[index - 1].id) {
        nodes.swapAt(index, index - 1)
      }
      layers[layerIndex].nodes = nodes
    }
  }
}
