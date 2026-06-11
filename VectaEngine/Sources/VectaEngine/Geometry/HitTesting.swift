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

  /// 특이 행렬(행렬식 ≈ 0)이면 nil — inverted()가 원본을 반환하는 함정 방어.
  private static func safeInverse(of transform: Transform2D) -> CGAffineTransform? {
    let determinant = transform.a * transform.d - transform.b * transform.c
    guard abs(determinant) > 1e-10 else { return nil }
    return transform.cgAffineTransform.inverted()
  }

  static func hits(_ node: Node, at point: CGPoint, tolerance: CGFloat) -> Bool {
    switch node {
    case .path(let pathNode):
      return hits(pathNode, at: point, tolerance: tolerance)
    case .group(let group):
      guard let inverse = safeInverse(of: group.transform) else { return false }
      let local = point.applying(inverse)
      // 행렬식 √|det| = 균등 스케일 근사. 비균등 스케일(sx≠sy)은 방향별 오차가
      // 남지만 선택 UI 허용 오차 용도로 충분하다.
      let determinant =
        group.transform.a * group.transform.d
        - group.transform.b * group.transform.c
      let localTolerance = tolerance / sqrt(abs(determinant))
      // 클립 패스는 AABB 근사 — 비직사각형 클립은 실제보다 큰 바운드
      // (마퀴는 보수적 판정, 히트테스트는 정확 판정)
      if let clip = group.clipPath, !clip.cgPath.contains(local, using: .winding) {
        return false
      }
      return group.children.contains { hits($0, at: local, tolerance: localTolerance) }
    case .text:
      return false  // M5에서 텍스트 바운드와 함께
    case .image(let image):
      guard let inverse = safeInverse(of: image.transform) else { return false }
      let local = point.applying(inverse)
      return image.frame.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
    }
  }

  static func hits(_ pathNode: PathNode, at point: CGPoint, tolerance: CGFloat) -> Bool {
    guard let inverse = safeInverse(of: pathNode.transform) else { return false }
    let local = point.applying(inverse)
    let cgPath = pathNode.path.cgPath
    if pathNode.style.fill != nil, cgPath.contains(local, using: .winding) {
      return true
    }
    if let stroke = pathNode.style.stroke {
      // hitWidth는 copy(strokingWithWidth:)에 전달하는 직경 — 화면 히트 반경 = width/2 + tolerance
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
