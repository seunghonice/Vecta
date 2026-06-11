import CoreGraphics

/// 점·마퀴 → 노드 판정. 모든 좌표는 모델 좌표.
public enum HitTesting {
  /// 점에 닿는 최상단 노드 ID. 위 레이어·나중에 그려진 노드 우선,
  /// 숨김/잠금 레이어 제외. 그룹은 자식이 닿으면 그룹 ID를 반환한다.
  public static func topmostNodeID(
    at point: CGPoint, in document: VectorDocument, tolerance: CGFloat
  ) -> NodeID? {
    for layer in document.layers.reversed() where layer.isVisible && !layer.isLocked {
      for node in layer.nodes.reversed() where hits(node, at: point, tolerance: tolerance) {
        return node.id
      }
    }
    return nil
  }

  /// 마퀴 사각형과 바운드가 교차하는 최상위 노드 집합.
  public static func topLevelNodeIDs(
    intersecting rect: CGRect, in document: VectorDocument
  ) -> Set<NodeID> {
    var result: Set<NodeID> = []
    for layer in document.layers where layer.isVisible && !layer.isLocked {
      for node in layer.nodes where node.bounds.intersects(rect) {
        result.insert(node.id)
      }
    }
    return result
  }

  static func hits(_ node: Node, at point: CGPoint, tolerance: CGFloat) -> Bool {
    switch node {
    case .path(let pathNode):
      return hits(pathNode, at: point, tolerance: tolerance)
    case .group(let group):
      let local = point.applying(group.transform.cgAffineTransform.inverted())
      if let clip = group.clipPath, !clip.cgPath.contains(local, using: .winding) {
        return false
      }
      return group.children.contains { hits($0, at: local, tolerance: tolerance) }
    case .text:
      return false  // M5에서 텍스트 바운드와 함께
    case .image(let image):
      let local = point.applying(image.transform.cgAffineTransform.inverted())
      return image.frame.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
    }
  }

  static func hits(_ pathNode: PathNode, at point: CGPoint, tolerance: CGFloat) -> Bool {
    let local = point.applying(pathNode.transform.cgAffineTransform.inverted())
    let cgPath = pathNode.path.cgPath
    if pathNode.style.fill != nil, cgPath.contains(local, using: .winding) {
      return true
    }
    if let stroke = pathNode.style.stroke {
      let hitWidth = max(stroke.width, 1) + tolerance * 2
      let stroked = cgPath.copy(
        strokingWithWidth: hitWidth, lineCap: stroke.cap.cgLineCap,
        lineJoin: stroke.join.cgLineJoin, miterLimit: 10)
      if stroked.contains(local, using: .winding) {
        return true
      }
    }
    return false
  }
}
