import Foundation

/// 레이어 패널 명령 (스펙 §8). 각 명령 = apply 1회 = undo 1단계.
extension DocumentStore {
  public func addLayer() {
    let layer = Layer(name: "레이어 \(document.layers.count + 1)")
    apply(actionName: "레이어 추가") { $0.layers.append(layer) }
    setActiveLayer(id: layer.id)
  }

  /// 마지막 남은 레이어는 삭제하지 않는다 (최소 1개 불변식).
  public func removeLayer(id: NodeID) {
    guard document.layers.count > 1 else { return }
    apply(actionName: "레이어 삭제") { document in
      document.layers.removeAll { $0.id == id }
    }
  }

  /// 앞뒤 공백은 잘라내고, 빈 이름은 무시한다.
  public func renameLayer(id: NodeID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    apply(actionName: "레이어 이름 변경") { document in
      guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
      document.layers[index].name = trimmed
    }
  }

  /// 숨긴 레이어의 노드는 선택에서 제외한다 (히트테스트 불가 상태와 일관).
  public func setLayerVisibility(id: NodeID, isVisible: Bool) {
    apply(actionName: isVisible ? "레이어 표시" : "레이어 숨김") { document in
      guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
      document.layers[index].isVisible = isVisible
    }
    if !isVisible {
      deselectNodes(inLayer: id)
    }
  }

  /// 잠근 레이어의 노드는 선택에서 제외한다.
  public func setLayerLocked(id: NodeID, isLocked: Bool) {
    apply(actionName: isLocked ? "레이어 잠금" : "레이어 잠금 해제") { document in
      guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
      document.layers[index].isLocked = isLocked
    }
    if isLocked {
      deselectNodes(inLayer: id)
    }
  }

  /// toIndex는 배열 범위로 클램프된다 (레이어 패널 드래그 순서 변경).
  public func moveLayer(id: NodeID, toIndex: Int) {
    apply(actionName: "레이어 순서 변경") { document in
      guard let from = document.layers.firstIndex(where: { $0.id == id }) else { return }
      let clamped = max(0, min(toIndex, document.layers.count - 1))
      guard clamped != from else { return }
      let layer = document.layers.remove(at: from)
      document.layers.insert(layer, at: clamped)
    }
  }

  private func deselectNodes(inLayer layerID: NodeID) {
    guard let layer = document.layers.first(where: { $0.id == layerID }) else { return }
    let layerNodeIDs = Set(layer.nodes.map(\.id))
    select(selection.subtracting(layerNodeIDs))
  }
}
