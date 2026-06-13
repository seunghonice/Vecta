import Foundation

extension DocumentStore {
  /// 텍스트 편집 커밋. 빈 문자열이면 노드 삭제, 아니면 string 치환.
  /// apply 1회 = undo 1단계.
  @MainActor public func commitTextEdit(id: NodeID, string: String) {
    if string.isEmpty {
      apply(actionName: "텍스트 삭제") { $0.removeTopLevelNodes(ids: [id]) }
    } else {
      apply(actionName: "텍스트 편집") { $0.updateTextNode(id: id) { $0.string = string } }
    }
  }
}
