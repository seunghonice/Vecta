import CoreGraphics

/// 패스파인더 불린 연산 (스펙 §8). Illustrator 합치기/빼기/교차/제외에 대응.
public enum PathfinderOperation: Sendable {
  case unite
  case subtract
  case intersect
  case exclude
}

extension VectorDocument {
  /// 선택된 최상위 패스 노드들을 불린 연산으로 합쳐 하나의 패스 노드로 치환한다.
  /// 패스가 2개 미만이면 아무것도 하지 않고 nil을 반환한다.
  /// 비-패스 노드(그룹·텍스트·이미지)는 무시한다.
  ///
  /// 좌표 처리: 각 패스를 자기 transform으로 모델 좌표에 베이크한 뒤, 자기
  /// fillRule로 `normalized` 정규화한다(자가교차 패스를 단일 winding 영역으로).
  /// 결과는 모델 좌표이므로 새 노드의 transform은 identity, fillRule은 winding.
  /// 스타일과 z-자리는 최하단(문서 z-순서 맨 아래) 패스를 따른다.
  @discardableResult
  public mutating func combineSelectedPaths(
    ids: Set<NodeID>, operation: PathfinderOperation
  ) -> NodeID? {
    var ordered: [PathNode] = []
    for layer in layers {
      for node in layer.nodes where ids.contains(node.id) {
        if case .path(let pathNode) = node { ordered.append(pathNode) }
      }
    }
    guard ordered.count >= 2 else { return nil }

    let normalized = ordered.map { node -> CGPath in
      let model = node.path.applying(node.transform.cgAffineTransform).cgPath
      let rule: CGPathFillRule = node.fillRule == .evenOdd ? .evenOdd : .winding
      return model.normalized(using: rule)
    }
    let combined = Self.applyBoolean(normalized, operation: operation)

    let bottom = ordered[0]
    let result = PathNode(
      path: BezierPath(cgPath: combined),
      style: bottom.style,
      transform: .identity,
      fillRule: .winding)

    updateTopLevelNodes(ids: [bottom.id]) { _ in .path(result) }
    removeTopLevelNodes(ids: ids.subtracting([bottom.id]))
    return result.id
  }

  private static func applyBoolean(
    _ paths: [CGPath], operation: PathfinderOperation
  ) -> CGPath {
    let first = paths[0]
    let rest = Array(paths.dropFirst())
    switch operation {
    case .unite:
      return rest.reduce(first) { $0.union($1, using: .winding) }
    case .intersect:
      return rest.reduce(first) { $0.intersection($1, using: .winding) }
    case .exclude:
      return rest.reduce(first) { $0.symmetricDifference($1, using: .winding) }
    case .subtract:
      let top = rest.dropFirst().reduce(rest[0]) { $0.union($1, using: .winding) }
      return first.subtracting(top, using: .winding)
    }
  }
}
