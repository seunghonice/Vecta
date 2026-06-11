import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func drag(_ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), isShiftPressed: shift, hitTolerance: 4)
}

@Test func dragRectNormalizesAndConstrains() {
  #expect(
    ShapeTool.dragRect(
      from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 30), constrainSquare: false)
      == CGRect(x: 10, y: 10, width: 30, height: 20))
  // Shift: 큰 변 기준 정사각형, 드래그 방향 유지
  #expect(
    ShapeTool.dragRect(
      from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 30), constrainSquare: true)
      == CGRect(x: 10, y: 10, width: 30, height: 30))
  // 음의 방향 드래그 + Shift
  #expect(
    ShapeTool.dragRect(
      from: CGPoint(x: 40, y: 40), to: CGPoint(x: 10, y: 30), constrainSquare: true)
      == CGRect(x: 10, y: 10, width: 30, height: 30))
}

@Test @MainActor func dragCreatesRectangleNodeWithDefaultStyle() {
  let context = ToolContext(store: DocumentStore(document: .empty()))
  let tool = ShapeTool(shape: .rectangle)
  tool.mouseDown(drag(10, 10), context: context)
  tool.mouseDragged(drag(60, 40), context: context)
  tool.mouseUp(drag(60, 40), context: context)
  let nodes = context.store.document.layers[0].nodes
  #expect(nodes.count == 1)
  #expect(nodes[0].bounds == CGRect(x: 10, y: 10, width: 50, height: 30))
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("path 노드가 아님")
    return
  }
  #expect(pathNode.style == .defaultShape)
}

@Test @MainActor func ellipseToolCreatesEllipse() {
  let context = ToolContext(store: DocumentStore(document: .empty()))
  let tool = ShapeTool(shape: .ellipse)
  tool.mouseDown(drag(0, 0), context: context)
  tool.mouseUp(drag(40, 20), context: context)
  guard case .path(let pathNode) = context.store.document.layers[0].nodes[0] else {
    Issue.record("path 노드가 아님")
    return
  }
  let curveCount = pathNode.path.subpaths[0].segments.filter {
    if case .curve = $0 { return true } else { return false }
  }.count
  #expect(curveCount == 4)
}

@Test @MainActor func tinyDragCreatesNothing() {
  let context = ToolContext(store: DocumentStore(document: .empty()))
  let tool = ShapeTool(shape: .rectangle)
  tool.mouseDown(drag(10, 10), context: context)
  tool.mouseUp(drag(10.5, 10.5), context: context)
  #expect(context.store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func shapeCreationIsOneUndoStep() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  let context = ToolContext(store: store)
  let tool = ShapeTool(shape: .rectangle)
  tool.mouseDown(drag(10, 10), context: context)
  tool.mouseUp(drag(60, 60), context: context)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.isEmpty)
}
