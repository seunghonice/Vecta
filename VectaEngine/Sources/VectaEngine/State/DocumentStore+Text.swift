import Foundation

extension DocumentStore {
  /// 텍스트 편집 커밋. 공백만 남으면 노드 삭제, 아니면 string 치환.
  /// 생성 경로(앱)와 동일하게 공백 전용을 "비어있음"으로 본다(빈 노드 잔존 방지).
  /// apply 1회 = undo 1단계.
  @MainActor public func commitTextEdit(id: NodeID, string: String) {
    if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      apply(actionName: "텍스트 삭제") { $0.removeTopLevelNodes(ids: [id]) }
    } else {
      apply(actionName: "텍스트 편집") { $0.updateTextNode(id: id) { $0.string = string } }
    }
  }

  /// 인스펙터 표시용 대표 텍스트 노드 — 선택이 정확히 1개이고 그 노드가 텍스트일 때만 반환.
  @MainActor public var selectionTextNode: TextNode? {
    guard selection.count == 1, let id = selection.first else { return nil }
    guard case .text(let textNode) = document.topLevelNode(id: id) else { return nil }
    return textNode
  }

  /// 선택된 텍스트 노드의 속성을 일괄 변경한다 (apply 1회 = undo 1단계).
  @MainActor public func updateSelectedTextNodes(
    actionName: String, _ change: @escaping (inout TextNode) -> Void
  ) {
    let ids = selection
    guard !ids.isEmpty else { return }
    apply(actionName: actionName) { $0.updateTextNodes(ids: ids, change) }
  }

  /// 드래그 제스처용 미리보기 — begin/commitTransient 사이에서 undo 등록 없이 텍스트 속성 갱신.
  @MainActor public func updateSelectedTextNodesTransient(
    _ change: @escaping (inout TextNode) -> Void
  ) {
    let ids = selection
    guard !ids.isEmpty else { return }
    updateTransient { $0.updateTextNodes(ids: ids, change) }
  }
}
