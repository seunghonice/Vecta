import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@MainActor
private func makeContext() -> (ToolContext, PenTool, DocumentStore) {
  let store = DocumentStore(document: .empty(size: CGSize(width: 300, height: 300)))
  return (ToolContext(store: store), PenTool(), store)
}

private func at(_ x: CGFloat, _ y: CGFloat) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), hitTolerance: 4)
}

@Test @MainActor func clicksThenEnterCommitsOpenPathOnce() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty(size: CGSize(width: 300, height: 300))) {
    undoManager
  }
  let context = ToolContext(store: store)
  let tool = PenTool()
  for point in [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), CGPoint(x: 100, y: 100)] {
    tool.mouseDown(CanvasEvent(point: point, hitTolerance: 4), context: context)
    tool.mouseUp(CanvasEvent(point: point, hitTolerance: 4), context: context)
  }
  #expect(store.document.layers[0].nodes.isEmpty)  // 아직 커밋 전
  #expect(tool.keyDown(.enter, context: context))
  let nodes = store.document.layers[0].nodes
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.path.subpaths[0].segments.count == 3)
  #expect(!pathNode.path.subpaths[0].isClosed)
  #expect(pathNode.style == .defaultShape)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.isEmpty)
  #expect(!undoManager.canUndo)  // 패스 전체가 undo 1단계
}

@Test @MainActor func clickingStartClosesPath() {
  let (context, tool, store) = makeContext()
  for point in [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), CGPoint(x: 50, y: 80)] {
    tool.mouseDown(CanvasEvent(point: point, hitTolerance: 4), context: context)
    tool.mouseUp(CanvasEvent(point: point, hitTolerance: 4), context: context)
  }
  tool.mouseDown(at(12, 11), context: context)  // 시작점 근처 → 닫기
  tool.mouseUp(at(12, 11), context: context)
  let nodes = store.document.layers[0].nodes
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else { return }
  #expect(pathNode.path.subpaths[0].isClosed)
}

@Test @MainActor func dragCreatesSmoothCurve() {
  let (context, tool, store) = makeContext()
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseDragged(at(40, 10), context: context)  // 시작 핸들
  tool.mouseUp(at(40, 10), context: context)
  tool.mouseDown(at(100, 50), context: context)
  tool.mouseUp(at(100, 50), context: context)
  #expect(tool.keyDown(.escape, context: context))
  guard case .path(let pathNode) = store.document.layers[0].nodes[0] else { return }
  guard case .curve = pathNode.path.subpaths[0].segments[1] else {
    Issue.record("곡선이 아님")
    return
  }
}

@Test @MainActor func escapeWithSingleAnchorDiscards() {
  let (context, tool, store) = makeContext()
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseUp(at(10, 10), context: context)
  #expect(tool.keyDown(.escape, context: context))
  #expect(store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func mouseMovedUpdatesRubberBandWithoutModelChange() {
  let (context, tool, store) = makeContext()
  let before = store.document
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseUp(at(10, 10), context: context)
  tool.mouseMoved(at(200, 200), context: context)
  #expect(store.document == before)  // 모델 불변
}

@Test @MainActor func deactivateCommitsUnfinishedPath() {
  let (context, tool, store) = makeContext()
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseUp(at(10, 10), context: context)
  tool.mouseDown(at(100, 10), context: context)
  tool.mouseUp(at(100, 10), context: context)
  tool.deactivate(context: context)
  #expect(store.document.layers[0].nodes.count == 1)  // 완결 커밋
  // 복귀 후 새 패스 시작 (이어 그리기 아님)
  tool.mouseDown(at(200, 200), context: context)
  tool.mouseUp(at(200, 200), context: context)
  tool.deactivate(context: context)
  #expect(store.document.layers[0].nodes.count == 1)  // 앵커 1개는 버려짐
}
