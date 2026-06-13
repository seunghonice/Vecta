/// 정렬 명령 — 인스펙터 6버튼과 연결된다 (스펙 §8). 선택 바운드를 기준으로 한다.
extension DocumentStore {
  public func alignSelection(edge: AlignEdge) {
    let ids = selection
    guard ids.count >= 2, let bounds = selectionBounds else { return }
    apply(actionName: "정렬") {
      $0.alignTopLevelNodes(ids: ids, edge: edge, within: bounds)
    }
  }
}
