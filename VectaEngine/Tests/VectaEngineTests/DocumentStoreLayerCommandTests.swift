import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect() -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
      style: Style(fill: .color(.black))))
}

@MainActor
private func makeStore(undoManager: UndoManager? = nil) -> DocumentStore {
  DocumentStore(document: .empty(size: CGSize(width: 300, height: 300))) { undoManager }
}

@Test @MainActor func addLayerAppendsOnTopAndActivates() {
  let store = makeStore()
  store.addLayer()
  #expect(store.document.layers.count == 2)
  #expect(store.document.layers[1].name == "레이어 2")
  #expect(store.activeLayerIndex == 1)
}

@Test @MainActor func addLayerIsSingleUndoStep() {
  let undoManager = UndoManager()
  let store = makeStore(undoManager: undoManager)
  store.addLayer()
  undoManager.undo()
  #expect(store.document.layers.count == 1)
}

@Test @MainActor func removeLastRemainingLayerIsPrevented() {
  let store = makeStore()
  store.removeLayer(id: store.document.layers[0].id)
  #expect(store.document.layers.count == 1)
}

@Test @MainActor func removeLayerDropsItsNodesAndSelection() {
  let store = makeStore()
  store.addLayer()
  let node = rect()
  store.apply(actionName: "노드 추가") { $0.layers[1].nodes.append(node) }
  store.select([node.id])
  store.removeLayer(id: store.document.layers[1].id)
  #expect(store.document.layers.count == 1)
  #expect(store.selection.isEmpty)
}

@Test @MainActor func renameLayerTrimsAndRejectsEmpty() {
  let store = makeStore()
  let id = store.document.layers[0].id
  store.renameLayer(id: id, to: "  배경  ")
  #expect(store.document.layers[0].name == "배경")
  store.renameLayer(id: id, to: "   ")
  #expect(store.document.layers[0].name == "배경")
}

@Test @MainActor func hidingLayerDeselectsItsNodes() {
  let store = makeStore()
  let node = rect()
  store.apply(actionName: "노드 추가") { $0.layers[0].nodes.append(node) }
  store.select([node.id])
  store.setLayerVisibility(id: store.document.layers[0].id, isVisible: false)
  #expect(store.document.layers[0].isVisible == false)
  #expect(store.selection.isEmpty)
}

@Test @MainActor func lockingLayerDeselectsItsNodes() {
  let store = makeStore()
  let node = rect()
  store.apply(actionName: "노드 추가") { $0.layers[0].nodes.append(node) }
  store.select([node.id])
  store.setLayerLocked(id: store.document.layers[0].id, isLocked: true)
  #expect(store.document.layers[0].isLocked == true)
  #expect(store.selection.isEmpty)
}

@Test @MainActor func moveLayerReordersAndClamps() {
  let store = makeStore()
  store.addLayer()
  store.addLayer()
  let bottom = store.document.layers[0].id
  store.moveLayer(id: bottom, toIndex: 99)  // 클램프 → 맨 위
  #expect(store.document.layers[2].id == bottom)
  store.moveLayer(id: bottom, toIndex: 0)
  #expect(store.document.layers[0].id == bottom)
}
