import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(_ frame: CGRect) -> PathNode {
  PathNode(path: .rectangle(frame), style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(nodes: [Node]) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document)
}

@Test func withFreshIDsChangesAllIDs() {
  let inner = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let group = GroupNode(children: [.path(inner)])
  let original = Node.group(group)
  let copy = original.withFreshIDs()
  #expect(copy.id != original.id)
  guard case .group(let copiedGroup) = copy else {
    Issue.record("그룹이 아님")
    return
  }
  #expect(copiedGroup.children[0].id != inner.id)
}

@Test func nodeClipboardRoundTripsThroughData() {
  let a = Node.path(rect(CGRect(x: 5, y: 5, width: 20, height: 20)))
  let data = NodeClipboard.encode([a])
  #expect(data != nil)
  let decoded = NodeClipboard.decode(data!)
  #expect(decoded == [a])
}

@Test func decodeReturnsNilForGarbage() {
  let garbage = Data("not json".utf8)
  #expect(NodeClipboard.decode(garbage) == nil)
}

@Test @MainActor func copyableSelectionReturnsSelectedNodesInZOrder() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let b = rect(CGRect(x: 20, y: 0, width: 10, height: 10))
  let c = rect(CGRect(x: 40, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a), .path(b), .path(c)])
  store.select([c.id, a.id])  // 선택 순서와 무관하게 z-순서로
  let nodes = store.copyableSelection()
  #expect(nodes.map(\.id) == [a.id, c.id])
}

@Test @MainActor func pasteNodesAddsFreshIDsWithOffsetAndSelects() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a)])
  let pasted = Node.path(rect(CGRect(x: 0, y: 0, width: 10, height: 10)))
  store.pasteNodes([pasted])
  #expect(store.document.layers[0].nodes.count == 2)
  let added = store.document.layers[0].nodes[1]
  #expect(added.id != pasted.id)  // 새 ID
  #expect(abs(added.bounds.minX - 10) < 0.5)  // +10 오프셋
  #expect(abs(added.bounds.minY - 10) < 0.5)
  #expect(store.selection == [added.id])
}

@Test @MainActor func pasteNodesIgnoresEmpty() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a)])
  store.pasteNodes([])
  #expect(store.document.layers[0].nodes.count == 1)
}

@Test @MainActor func duplicateSelectionAddsOffsetCopyOfSelection() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let b = rect(CGRect(x: 50, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  store.duplicateSelection()
  #expect(store.document.layers[0].nodes.count == 4)
  // 새로 추가된 2개가 선택됨, 원본 ID와 겹치지 않음.
  #expect(store.selection.count == 2)
  #expect(store.selection.isDisjoint(with: [a.id, b.id]))
}

@Test @MainActor func duplicateIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [.path(a)]
  let store = DocumentStore(document: document) { undoManager }
  store.select([a.id])
  store.duplicateSelection()
  undoManager.undo()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id])
}
