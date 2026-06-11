import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@MainActor
private func makeContext() -> (ToolContext, SelectTool, NodeID, NodeID) {
  let nodeA = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let nodeB = PathNode(
    path: .rectangle(CGRect(x: 100, y: 100, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.path(nodeA), .path(nodeB)]
  let context = ToolContext(store: DocumentStore(document: document))
  return (context, SelectTool(), nodeA.id, nodeB.id)
}

private func click(_ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), isShiftPressed: shift, hitTolerance: 4)
}

@Test @MainActor func clickSelectsTopmostNode() {
  let (context, tool, nodeA, _) = makeContext()
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseUp(click(25, 25), context: context)
  #expect(context.store.selection == [nodeA])
}

@Test @MainActor func clickEmptySpaceClearsSelection() {
  let (context, tool, nodeA, _) = makeContext()
  context.store.select([nodeA])
  tool.mouseDown(click(300, 300), context: context)
  tool.mouseUp(click(300, 300), context: context)
  #expect(context.store.selection.isEmpty)
}

@Test @MainActor func shiftClickTogglesMembership() {
  let (context, tool, nodeA, nodeB) = makeContext()
  context.store.select([nodeA])
  tool.mouseDown(click(125, 125, shift: true), context: context)
  tool.mouseUp(click(125, 125, shift: true), context: context)
  #expect(context.store.selection == [nodeA, nodeB])
  tool.mouseDown(click(125, 125, shift: true), context: context)
  tool.mouseUp(click(125, 125, shift: true), context: context)
  #expect(context.store.selection == [nodeA])
}

@Test @MainActor func dragSelectedNodeMovesItWithSingleUndo() {
  let undoManager = UndoManager()
  let (base, tool, nodeA, _) = makeContext()
  let store = DocumentStore(document: base.store.document) { undoManager }
  let context = ToolContext(store: store)
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseDragged(click(35, 30), context: context)
  tool.mouseDragged(click(45, 35), context: context)
  tool.mouseUp(click(45, 35), context: context)
  // 총 델타 (20, 10)
  #expect(store.document.topLevelNode(id: nodeA)?.bounds.origin == CGPoint(x: 20, y: 10))
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(store.document.topLevelNode(id: nodeA)?.bounds.origin == .zero)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func marqueeSelectsIntersectingNodes() {
  let (context, tool, nodeA, nodeB) = makeContext()
  tool.mouseDown(click(200, 200), context: context)
  tool.mouseDragged(click(120, 120), context: context)
  tool.mouseUp(click(120, 120), context: context)
  #expect(context.store.selection == [nodeB])
  // 전체를 덮는 마퀴
  tool.mouseDown(click(220, 220), context: context)
  tool.mouseDragged(click(-10, -10), context: context)
  tool.mouseUp(click(-10, -10), context: context)
  #expect(context.store.selection == [nodeA, nodeB])
}

@Test @MainActor func deleteKeyRemovesSelection() {
  let (context, tool, nodeA, _) = makeContext()
  context.store.select([nodeA])
  #expect(tool.keyDown(.delete, context: context))
  #expect(context.store.document.topLevelNode(id: nodeA) == nil)
}

@Test @MainActor func escapeClearsSelectionWhenIdle() {
  let (context, tool, nodeA, _) = makeContext()
  context.store.select([nodeA])
  #expect(tool.keyDown(.escape, context: context))
  #expect(context.store.selection.isEmpty)
}

@Test @MainActor func escapeDuringMoveCancelsGesture() {
  let (context, tool, nodeA, _) = makeContext()
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseDragged(click(45, 25), context: context)
  #expect(tool.keyDown(.escape, context: context))
  #expect(context.store.document.topLevelNode(id: nodeA)?.bounds.origin == .zero)
}
