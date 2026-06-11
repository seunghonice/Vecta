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

@Test func applyMutatesDocument() {
  let store = DocumentStore(document: .empty())
  store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  #expect(store.document.layers[0].nodes.count == 1)
}

@Test func undoRestoresPreviousDocumentAndRedoReapplies() {
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

@Test func noOpChangeRegistersNoUndo() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  store.apply(actionName: "아무것도 안 함") { _ in }
  #expect(!undoManager.canUndo)
}

@Test func loadReplacesDocumentAndClearsUndoStack() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
  let replacement = VectorDocument.empty(size: CGSize(width: 50, height: 50))
  store.load(replacement)
  #expect(store.document == replacement)
  #expect(!undoManager.canUndo)
}
