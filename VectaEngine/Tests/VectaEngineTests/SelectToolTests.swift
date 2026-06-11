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

@Test @MainActor func shiftMarqueeAddsToExistingSelection() {
  let (context, tool, nodeA, nodeB) = makeContext()
  context.store.select([nodeA])
  tool.mouseDown(click(90, 90, shift: true), context: context)
  tool.mouseDragged(click(160, 160, shift: true), context: context)
  tool.mouseUp(click(160, 160, shift: true), context: context)
  #expect(context.store.selection == [nodeA, nodeB])
}

@Test @MainActor func secondMouseDownDuringDragCancelsPreviousGesture() {
  let (context, tool, nodeA, _) = makeContext()
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseDragged(click(45, 25), context: context)
  // 정리되지 않은 채 새 mouseDown (이중 버튼 등) → 이전 제스처 취소
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseUp(click(25, 25), context: context)
  #expect(context.store.document.topLevelNode(id: nodeA)?.bounds.origin == .zero)
}

@Test @MainActor func drawOverlaySmokeTestDoesNotCrash() {
  let (context, tool, nodeA, _) = makeContext()
  context.store.select([nodeA])
  tool.mouseDown(click(300, 300), context: context)  // 마퀴 시작
  tool.mouseDragged(click(320, 320), context: context)
  let bitmap = CGContext(
    data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  tool.drawOverlay(in: bitmap, scale: 2, context: context)
  tool.mouseUp(click(320, 320), context: context)
}
