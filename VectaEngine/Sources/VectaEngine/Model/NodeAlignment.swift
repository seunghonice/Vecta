import CoreGraphics

/// 정렬 기준 (스펙 §8). 모델은 y-아래 좌표계이므로 top = 최소 y, bottom = 최대 y.
public enum AlignEdge: Sendable {
  case left
  case centerHorizontal
  case right
  case top
  case centerVertical
  case bottom
}

extension VectorDocument {
  /// 선택된 최상위 노드들을 기준 바운드에 맞춰 정렬한다.
  /// 가로 기준(left/centerHorizontal/right)은 x축만, 세로 기준은 y축만 이동한다.
  public mutating func alignTopLevelNodes(
    ids: Set<NodeID>, edge: AlignEdge, within bounds: CGRect
  ) {
    updateTopLevelNodes(ids: ids) { node in
      let frame = node.bounds
      let delta: CGVector
      switch edge {
      case .left:
        delta = CGVector(dx: bounds.minX - frame.minX, dy: 0)
      case .centerHorizontal:
        delta = CGVector(dx: bounds.midX - frame.midX, dy: 0)
      case .right:
        delta = CGVector(dx: bounds.maxX - frame.maxX, dy: 0)
      case .top:
        delta = CGVector(dx: 0, dy: bounds.minY - frame.minY)
      case .centerVertical:
        delta = CGVector(dx: 0, dy: bounds.midY - frame.midY)
      case .bottom:
        delta = CGVector(dx: 0, dy: bounds.maxY - frame.maxY)
      }
      return NodeTransformer.translated(node, by: delta)
    }
  }
}
