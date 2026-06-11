import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(at origin: CGPoint) -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(origin: origin, size: CGSize(width: 50, height: 50))),
      style: Style(fill: .color(.black))))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func groupSelectionCreatesGroupAndSelectsIt() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let store = makeStore(nodes: [a, b])
  store.select([a.id, b.id])
  store.groupSelection()
  #expect(store.document.layers[0].nodes.count == 1)
  let groupID = store.document.layers[0].nodes[0].id
  #expect(store.selection == [groupID])
}

@Test @MainActor func groupSelectionIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let store = makeStore(nodes: [a, b], undoManager: undoManager)
  store.select([a.id, b.id])
  store.groupSelection()
  undoManager.undo()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id, b.id])
  #expect(!undoManager.canUndo)
}

@Test @MainActor func ungroupSelectionSelectsReleasedChildren() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(children: [.path(inner)])
  let store = makeStore(nodes: [.group(group)])
  store.select([group.id])
  store.ungroupSelection()
  #expect(store.selection == [inner.id])
}

@Test @MainActor func bringSelectionForwardReorders() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let store = makeStore(nodes: [a, b])
  store.select([a.id])
  store.bringSelectionForward()
  #expect(store.document.layers[0].nodes.map(\.id) == [b.id, a.id])
  #expect(store.selection == [a.id])  // 선택 유지
}

@Test @MainActor func structureCommandsIgnoreEmptySelection() {
  let a = rect(at: .zero)
  let store = makeStore(nodes: [a])
  store.groupSelection()
  store.ungroupSelection()
  store.bringSelectionForward()
  store.sendSelectionBackward()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id])
}
