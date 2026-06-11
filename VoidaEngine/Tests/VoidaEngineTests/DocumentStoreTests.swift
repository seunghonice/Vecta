import CoreGraphics
import Foundation
import Testing

@testable import VoidaEngine

private func makeRectNode() -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
      style: .defaultShape))
}

@Test @MainActor func applyMutatesDocument() {
  let store = DocumentStore(document: .empty())
  store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  #expect(store.document.layers[0].nodes.count == 1)
}

@Test @MainActor func undoRestoresPreviousDocumentAndRedoReapplies() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.isEmpty)
  #expect(undoManager.canRedo)
  undoManager.redo()
  #expect(store.document.layers[0].nodes.count == 1)
}

@Test @MainActor func noOpChangeRegistersNoUndo() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  store.apply(actionName: "아무것도 안 함") { _ in }
  #expect(!undoManager.canUndo)
}

@Test @MainActor func loadReplacesDocumentAndClearsUndoStack() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  let replacement = VectorDocument.empty(size: CGSize(width: 50, height: 50))
  store.load(replacement)
  #expect(store.document == replacement)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func newApplyAfterUndoInvalidatesRedoStack() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  undoManager.undo()
  #expect(undoManager.canRedo)
  store.apply(actionName: "다른 도형") { $0.layers[0].nodes.append(makeRectNode()) }
  #expect(!undoManager.canRedo)
}

@Test @MainActor func multipleAppliesEachUndoIndependently() {
  let undoManager = UndoManager()
  // 런루프 없는 테스트 환경에서 apply마다 독립 그룹을 명시적으로 만든다.
  undoManager.groupsByEvent = false
  let store = DocumentStore(document: .empty()) { undoManager }
  undoManager.beginUndoGrouping()
  store.apply(actionName: "도형1 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  undoManager.endUndoGrouping()
  undoManager.beginUndoGrouping()
  store.apply(actionName: "도형2 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  undoManager.endUndoGrouping()

  undoManager.undo()
  #expect(store.document.layers[0].nodes.count == 1)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func actionNameAppearsInUndoMenuTitle() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  #expect(undoManager.undoActionName == "도형 추가")
  undoManager.undo()
  #expect(undoManager.redoActionName == "도형 추가")
}
