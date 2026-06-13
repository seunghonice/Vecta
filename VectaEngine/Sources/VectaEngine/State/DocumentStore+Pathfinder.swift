/// 패스파인더 명령 — 인스펙터 4버튼·오브젝트 메뉴와 연결된다 (스펙 §8).
extension DocumentStore {
  /// 선택된 최상위 패스(2개 이상)를 불린 연산으로 합쳐 결과를 선택한다.
  public func applyPathfinder(_ operation: PathfinderOperation) {
    let ids = selection
    var resultID: NodeID?
    apply(actionName: "패스파인더") {
      resultID = $0.combineSelectedPaths(ids: ids, operation: operation)
    }
    if let resultID { select([resultID]) }
  }

  /// 선택 중 패스파인더 대상이 되는 최상위 패스 노드 수 (UI 활성화 판단용).
  public var combinablePathCount: Int {
    selection.reduce(into: 0) { count, id in
      if case .path? = document.topLevelNode(id: id) { count += 1 }
    }
  }
}
