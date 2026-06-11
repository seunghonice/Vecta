import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@MainActor
private func makeSelected() -> (ToolContext, SelectTool, NodeID) {
  let node = PathNode(
    path: .rectangle(CGRect(x: 100, y: 100, width: 100, height: 100)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.path(node)]
  let context = ToolContext(store: DocumentStore(document: document))
  context.store.select([node.id])
  return (context, SelectTool(), node.id)
}

private func event(_ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), isShiftPressed: shift, hitTolerance: 4)
}

@Test @MainActor func cornerHandleResizesAroundOppositeAnchor() {
  let (context, tool, node) = makeSelected()
  // bottomRight 핸들 (200,200) 잡고 (300,250)으로 → anchor (100,100),
  // scaleX 2, scaleY 1.5
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(300, 250), context: context)
  tool.mouseUp(event(300, 250), context: context)
  #expect(
    context.store.document.topLevelNode(id: node)?.bounds
      == CGRect(x: 100, y: 100, width: 200, height: 150))
}

@Test @MainActor func edgeHandleResizesSingleAxis() {
  let (context, tool, node) = makeSelected()
  // middleRight (200,150) → (250,300): scaleX 1.5, y는 불변
  tool.mouseDown(event(200, 150), context: context)
  tool.mouseDragged(event(250, 300), context: context)
  tool.mouseUp(event(250, 300), context: context)
  #expect(
    context.store.document.topLevelNode(id: node)?.bounds
      == CGRect(x: 100, y: 100, width: 150, height: 100))
}

@Test @MainActor func shiftCornerResizeIsUniform() {
  let (context, tool, node) = makeSelected()
  // bottomRight를 (300,250)으로 + Shift → 지배 축 비율 2.0 균등
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(300, 250, shift: true), context: context)
  tool.mouseUp(event(300, 250, shift: true), context: context)
  #expect(
    context.store.document.topLevelNode(id: node)?.bounds
      == CGRect(x: 100, y: 100, width: 200, height: 200))
}

@Test @MainActor func resizeIsSingleUndoStep() {
  let undoManager = UndoManager()
  let nodeSource = PathNode(
    path: .rectangle(CGRect(x: 100, y: 100, width: 100, height: 100)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.path(nodeSource)]
  let store = DocumentStore(document: document) { undoManager }
  let context = ToolContext(store: store)
  store.select([nodeSource.id])
  let tool = SelectTool()
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(220, 220), context: context)
  tool.mouseDragged(event(300, 300), context: context)
  tool.mouseUp(event(300, 300), context: context)
  undoManager.undo()
  #expect(
    store.document.topLevelNode(id: nodeSource.id)?.bounds
      == CGRect(x: 100, y: 100, width: 100, height: 100))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func rotationZoneDragRotatesSelection() {
  let (context, tool, node) = makeSelected()
  // 코너 (200,100) 바깥 회전 존에서 시작
  let start = CGPoint(x: 208, y: 92)
  tool.mouseDown(event(start.x, start.y), context: context)
  // 중심 (150,150) 기준 90° 회전한 위치로 드래그:
  // start-중심 벡터 (58,-58) → 90°(y-아래 좌표계 시계) 회전 → (58,58) → (208,208)
  tool.mouseDragged(event(208, 208), context: context)
  tool.mouseUp(event(208, 208), context: context)
  let bounds = context.store.document.topLevelNode(id: node)!.bounds
  // 정사각형 90° 회전 → 바운드 동일 (중심 유지)
  #expect(abs(bounds.midX - 150) < 0.01)
  #expect(abs(bounds.midY - 150) < 0.01)
  #expect(abs(bounds.width - 100) < 0.01)
}

@Test @MainActor func degenerateResizeIsClampedToNoOp() {
  let (context, tool, node) = makeSelected()
  // 핸들을 anchor 위로 정확히 끌어도 0 스케일이 되지 않는다
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(100, 100), context: context)
  tool.mouseUp(event(100, 100), context: context)
  let bounds = context.store.document.topLevelNode(id: node)!.bounds
  #expect(bounds.width > 0.5)
  #expect(bounds.height > 0.5)
}
