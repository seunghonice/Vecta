import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@MainActor
private func storeWithOneRect() -> (DocumentStore, NodeID) {
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaultShape)
  var document = VectorDocument.empty()
  document.layers[0].nodes = [.path(node)]
  return (DocumentStore(document: document), node.id)
}

@Test @MainActor func selectAndToggleAndClear() {
  let (store, id) = storeWithOneRect()
  store.select([id])
  #expect(store.selection == [id])
  store.toggleSelection(id)
  #expect(store.selection.isEmpty)
  store.toggleSelection(id)
  #expect(store.selection == [id])
  store.clearSelection()
  #expect(store.selection.isEmpty)
}

@Test @MainActor func selectIgnoresUnknownIDs() {
  let (store, id) = storeWithOneRect()
  store.select([id, NodeID()])
  #expect(store.selection == [id])
}

@Test @MainActor func selectionPrunedWhenNodeRemovedByApply() {
  let (store, id) = storeWithOneRect()
  store.select([id])
  store.apply(actionName: "삭제") { $0.removeTopLevelNodes(ids: [id]) }
  #expect(store.selection.isEmpty)
}

@Test @MainActor func loadClearsSelection() {
  let (store, id) = storeWithOneRect()
  store.select([id])
  store.load(.empty())
  #expect(store.selection.isEmpty)
}

@Test @MainActor func deleteSelectionRemovesNodesWithSingleUndoStep() {
  let undoManager = UndoManager()
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaultShape)
  var document = VectorDocument.empty()
  document.layers[0].nodes = [.path(node)]
  let store = DocumentStore(document: document) { undoManager }
  store.select([node.id])
  store.deleteSelection()
  #expect(store.document.layers[0].nodes.isEmpty)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.count == 1)
}

@Test @MainActor func selectionBoundsUnionsSelectedNodes() {
  let nodeA = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaultShape)
  let nodeB = PathNode(
    path: .rectangle(CGRect(x: 20, y: 20, width: 10, height: 10)), style: .defaultShape)
  var document = VectorDocument.empty()
  document.layers[0].nodes = [.path(nodeA), .path(nodeB)]
  let store = DocumentStore(document: document)
  #expect(store.selectionBounds == nil)
  store.select([nodeA.id, nodeB.id])
  #expect(store.selectionBounds == CGRect(x: 0, y: 0, width: 30, height: 30))
}

// --- transient ---

@Test @MainActor func transientUpdatesPublishWithoutUndo() {
  let undoManager = UndoManager()
  let (storeBase, id) = storeWithOneRect()
  let store = DocumentStore(document: storeBase.document) { undoManager }
  store.beginTransient()
  store.updateTransient { document in
    document.updateTopLevelNodes(ids: [id]) {
      NodeTransformer.translated($0, by: CGVector(dx: 5, dy: 0))
    }
  }
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 5)
  #expect(!undoManager.canUndo)
  store.commitTransient(actionName: "이동")
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 0)
}

@Test @MainActor func transientUpdateIsAbsoluteFromBase() {
  // update를 여러 번 호출해도 베이스 기준 절대 변경 — 누적되지 않는다
  let (store, id) = storeWithOneRect()
  store.beginTransient()
  for _ in 0..<3 {
    store.updateTransient { document in
      document.updateTopLevelNodes(ids: [id]) {
        NodeTransformer.translated($0, by: CGVector(dx: 7, dy: 0))
      }
    }
  }
  store.commitTransient(actionName: "이동")
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 7)
}

@Test @MainActor func cancelTransientRestoresBase() {
  let (store, id) = storeWithOneRect()
  store.beginTransient()
  store.updateTransient { document in
    document.updateTopLevelNodes(ids: [id]) {
      NodeTransformer.translated($0, by: CGVector(dx: 5, dy: 0))
    }
  }
  store.cancelTransient()
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 0)
}

@Test @MainActor func noOpTransientCommitRegistersNoUndo() {
  let undoManager = UndoManager()
  let (storeBase, _) = storeWithOneRect()
  let store = DocumentStore(document: storeBase.document) { undoManager }
  store.beginTransient()
  store.commitTransient(actionName: "이동")
  #expect(!undoManager.canUndo)
}

@Test @MainActor func applyDuringTransientCancelsPreview() {
  let undoManager = UndoManager()
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaultShape)
  var document = VectorDocument.empty()
  document.layers[0].nodes = [.path(node)]
  let store = DocumentStore(document: document) { undoManager }
  store.beginTransient()
  store.updateTransient { doc in
    doc.updateTopLevelNodes(ids: [node.id]) {
      NodeTransformer.translated($0, by: CGVector(dx: 50, dy: 0))
    }
  }
  // 드래그 중 외부 apply (예: 삭제 단축키) → 미리보기 취소 후 적용
  store.apply(actionName: "삭제") { $0.removeTopLevelNodes(ids: [node.id]) }
  #expect(store.document.layers[0].nodes.isEmpty)
  undoManager.undo()
  // undo 결과는 드래그 시작 전 위치 (미리보기 50pt 이동은 버려짐)
  #expect(store.document.topLevelNode(id: node.id)?.bounds.minX == 0)
  // 세션은 파기됨 — 이후 commit은 no-op
  store.commitTransient(actionName: "이동")
  #expect(undoManager.canRedo)  // commit이 새 undo를 등록하지 않았음을 간접 확인
}

@Test @MainActor func loadDuringTransientDiscardsBase() {
  let (storeSource, id) = storeWithOneRect()
  let store = DocumentStore(document: storeSource.document)
  store.beginTransient()
  store.updateTransient { doc in
    doc.updateTopLevelNodes(ids: [id]) {
      NodeTransformer.translated($0, by: CGVector(dx: 5, dy: 0))
    }
  }
  let replacement = VectorDocument.empty(size: CGSize(width: 77, height: 77))
  store.load(replacement)
  #expect(store.document == replacement)
  // 파기된 세션의 cancel이 새 문서를 덮어쓰지 않는다
  store.cancelTransient()
  #expect(store.document == replacement)
}

@Test @MainActor func updateTransientWithoutSessionIsSilentNoOp() {
  let (store, id) = storeWithOneRect()
  store.updateTransient { doc in
    doc.updateTopLevelNodes(ids: [id]) {
      NodeTransformer.translated($0, by: CGVector(dx: 5, dy: 0))
    }
  }
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 0)
}
