import CoreGraphics

/// 복사/붙여넣기/복제 명령 (스펙 §8). 직렬화는 NodeClipboard, NSPasteboard
/// I/O는 앱이 담당하고, 스토어는 선택 수집·노드 추가만 한다.
extension DocumentStore {
  /// 선택된 최상위 노드를 문서 z-순서로 반환 (복사·잘라내기·복제용).
  public func copyableSelection() -> [Node] {
    let ids = selection
    var result: [Node] = []
    for layer in document.layers {
      for node in layer.nodes where ids.contains(node.id) {
        result.append(node)
      }
    }
    return result
  }

  /// 노드들을 새 ID·오프셋으로 활성 레이어에 추가하고 선택한다 (붙여넣기).
  /// 활성 레이어가 숨김/잠금이면 조용히 무시한다 (생성 경로와 동일 규칙).
  public func pasteNodes(_ nodes: [Node], offset: CGVector = CGVector(dx: 10, dy: 10)) {
    guard !nodes.isEmpty else { return }
    let index = activeLayerIndex
    guard document.layers.indices.contains(index) else { return }
    let layer = document.layers[index]
    guard layer.isVisible, !layer.isLocked else { return }
    let fresh = nodes.map { NodeTransformer.translated($0.withFreshIDs(), by: offset) }
    apply(actionName: "붙여넣기") { $0.layers[index].nodes.append(contentsOf: fresh) }
    select(Set(fresh.map(\.id)))
  }

  /// 선택을 그 자리에서 오프셋 복제한다 — 클립보드를 거치지 않는다.
  public func duplicateSelection() {
    apply(actionName: "복제") { document in
      let index = activeLayerIndex
      guard document.layers.indices.contains(index) else { return }
      let layer = document.layers[index]
      guard layer.isVisible, !layer.isLocked else { return }
      let copies = copyableSelection().map {
        NodeTransformer.translated($0.withFreshIDs(), by: CGVector(dx: 10, dy: 10))
      }
      guard !copies.isEmpty else { return }
      document.layers[index].nodes.append(contentsOf: copies)
      pendingSelection = Set(copies.map(\.id))
    }
    if let pending = pendingSelection {
      select(pending)
      pendingSelection = nil
    }
  }
}
