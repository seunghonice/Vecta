/// 그룹/해제·앞뒤 순서 명령 — 메뉴(⌘G/⇧⌘G/⌘]/⌘[)와 연결된다 (스펙 §8).
extension DocumentStore {
  public func groupSelection() {
    let ids = selection
    guard !ids.isEmpty else { return }
    var groupID: NodeID?
    apply(actionName: "그룹") { groupID = $0.groupTopLevelNodes(ids: ids) }
    if let groupID { select([groupID]) }
  }

  public func ungroupSelection() {
    let ids = selection
    guard !ids.isEmpty else { return }
    var released: Set<NodeID> = []
    apply(actionName: "그룹 해제") { released = $0.ungroupTopLevelNodes(ids: ids) }
    // 그룹이 아니어서 남은 노드 + 풀린 자식을 함께 선택 (select가 존재 검증)
    select(ids.union(released))
  }

  public func bringSelectionForward() {
    let ids = selection
    guard !ids.isEmpty else { return }
    apply(actionName: "앞으로 가져오기") { $0.bringForwardTopLevelNodes(ids: ids) }
  }

  public func sendSelectionBackward() {
    let ids = selection
    guard !ids.isEmpty else { return }
    apply(actionName: "뒤로 보내기") { $0.sendBackwardTopLevelNodes(ids: ids) }
  }
}
