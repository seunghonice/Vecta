import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@MainActor
private func makeContext() -> (ToolContext, DirectSelectTool, NodeID) {
  // 100×50 사각형 (앵커: (10,10) (110,10) (110,60) (10,60))
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  let context = ToolContext(store: DocumentStore(document: document))
  return (context, DirectSelectTool(), node.id)
}

private func at(_ x: CGFloat, _ y: CGFloat) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), hitTolerance: 4)
}

@Test @MainActor func clickOnPathSetsEditTarget() {
  let (context, tool, nodeID) = makeContext()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  #expect(tool.editNodeID == nodeID)
  #expect(tool.selectedAnchor == nil)
}

@Test @MainActor func clickOnAnchorSelectsIt() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)  // 편집 대상 지정
  tool.mouseUp(at(50, 30), context: context)
  tool.mouseDown(at(110, 60), context: context)  // 우하단 앵커
  tool.mouseUp(at(110, 60), context: context)
  #expect(tool.selectedAnchor == AnchorRef(subpathIndex: 0, segmentIndex: 2))
}

@Test @MainActor func draggingAnchorMovesItWithSingleUndo() {
  let undoManager = UndoManager()
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  let store = DocumentStore(document: document) { undoManager }
  let context = ToolContext(store: store)
  let tool = DirectSelectTool()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  tool.mouseDown(at(110, 60), context: context)  // 앵커 잡기
  tool.mouseDragged(at(130, 80), context: context)
  tool.mouseDragged(at(140, 90), context: context)
  tool.mouseUp(at(140, 90), context: context)
  guard case .path(let edited)? = store.document.topLevelNode(id: node.id) else {
    Issue.record("패스가 아님")
    return
  }
  #expect(
    edited.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
      == CGPoint(x: 140, y: 90))
  undoManager.undo()
  guard case .path(let restored)? = store.document.topLevelNode(id: node.id) else { return }
  #expect(
    restored.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
      == CGPoint(x: 110, y: 60))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func draggingAnchorOnTransformedNodeUsesLocalCoordinates() {
  // 노드가 (100,0) 이동돼 있으면 모델 좌표 → 로컬 역변환 후 편집
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  let context = ToolContext(store: DocumentStore(document: document))
  let tool = DirectSelectTool()
  tool.mouseDown(at(120, 20), context: context)  // 본체
  tool.mouseUp(at(120, 20), context: context)
  tool.mouseDown(at(150, 50), context: context)  // 모델 (150,50) = 로컬 (50,50) 앵커
  tool.mouseDragged(at(160, 60), context: context)
  tool.mouseUp(at(160, 60), context: context)
  guard case .path(let edited)? = context.store.document.topLevelNode(id: node.id) else { return }
  // 로컬 좌표로 (60,60)
  #expect(
    edited.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
      == CGPoint(x: 60, y: 60))
}

@Test @MainActor func clickEmptyClearsEditTarget() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  tool.mouseDown(at(250, 250), context: context)
  tool.mouseUp(at(250, 250), context: context)
  #expect(tool.editNodeID == nil)
}

@Test @MainActor func escapeClearsEditState() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  #expect(tool.keyDown(.escape, context: context))
  #expect(tool.editNodeID == nil)
  #expect(tool.selectedAnchor == nil)
}

@Test @MainActor func draggingControlHandleChangesCurvatureWithSingleUndo() {
  let undoManager = UndoManager()
  // 타원 (10,10,100×100): south 앵커(60,110)의 들어오는 핸들 = segments[1].control2
  let node = PathNode(
    path: .ellipse(in: CGRect(x: 10, y: 10, width: 100, height: 100)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  let store = DocumentStore(document: document) { undoManager }
  let context = ToolContext(store: store)
  let tool = DirectSelectTool()
  tool.mouseDown(at(60, 60), context: context)  // 본체 → 편집 대상
  tool.mouseUp(at(60, 60), context: context)
  tool.mouseDown(at(60, 110), context: context)  // south 앵커 선택
  tool.mouseUp(at(60, 110), context: context)
  #expect(tool.selectedAnchor == AnchorRef(subpathIndex: 0, segmentIndex: 1))
  // 들어오는 핸들 위치 ≈ (60 + 50×kappa, 110) = (87.614, 110)
  tool.mouseDown(at(87.6, 110), context: context)
  tool.mouseDragged(at(90, 130), context: context)
  tool.mouseUp(at(90, 130), context: context)
  guard case .path(let edited)? = store.document.topLevelNode(id: node.id),
    case .curve(_, _, let control2) = edited.path.subpaths[0].segments[1]
  else {
    Issue.record("곡선이 아님")
    return
  }
  #expect(control2 == CGPoint(x: 90, y: 130))
  undoManager.undo()
  guard case .path(let restored)? = store.document.topLevelNode(id: node.id),
    case .curve(_, _, let restoredControl2) = restored.path.subpaths[0].segments[1]
  else { return }
  #expect(abs(restoredControl2.x - 87.614) < 0.01)
  #expect(restoredControl2.y == 110)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func deactivateClearsEditState() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  tool.deactivate(context: context)
  #expect(tool.editNodeID == nil)
  #expect(tool.selectedAnchor == nil)
}

@Test @MainActor func clickInsideGroupTargetsInnerPath() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  let context = ToolContext(store: DocumentStore(document: document))
  let tool = DirectSelectTool()
  tool.mouseDown(at(120, 20), context: context)
  tool.mouseUp(at(120, 20), context: context)
  #expect(tool.editNodeID == inner.id)
}

@Test @MainActor func draggingAnchorInsideGroupUsesWorldCoordinates() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  let store = DocumentStore(document: document)
  let context = ToolContext(store: store)
  let tool = DirectSelectTool()
  tool.mouseDown(at(120, 20), context: context)  // 본체 → 편집 대상
  tool.mouseUp(at(120, 20), context: context)
  tool.mouseDown(at(150, 50), context: context)  // 월드 (150,50) = 로컬 (50,50) 앵커
  tool.mouseDragged(at(160, 60), context: context)
  tool.mouseUp(at(160, 60), context: context)
  guard let found = store.document.pathNode(id: inner.id) else {
    Issue.record("패스 없음")
    return
  }
  // 로컬 좌표로 (60,60)
  #expect(
    found.node.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
      == CGPoint(x: 60, y: 60))
}

@Test @MainActor func draggingAnchorInsideScaledGroupConvertsToLocal() {
  // 2배 스케일 그룹 — 변환 합성 순서(노드 × 그룹)를 구분하는 테스트.
  // 로컬 (0,0,50,50) 사각형이 월드 (100,0)~(200,100)에 보인다.
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(
      CGAffineTransform(translationX: 100, y: 0).scaledBy(x: 2, y: 2)))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.group(group)]
  let store = DocumentStore(document: document)
  let context = ToolContext(store: store)
  let tool = DirectSelectTool()
  tool.mouseDown(at(150, 50), context: context)  // 본체 (월드) → 편집 대상
  tool.mouseUp(at(150, 50), context: context)
  #expect(tool.editNodeID == inner.id)
  tool.mouseDown(at(200, 100), context: context)  // 월드 (200,100) = 로컬 (50,50) 앵커
  tool.mouseDragged(at(220, 120), context: context)  // 월드 +20 → 로컬 +10
  tool.mouseUp(at(220, 120), context: context)
  guard let found = store.document.pathNode(id: inner.id) else {
    Issue.record("패스 없음")
    return
  }
  #expect(
    found.node.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
      == CGPoint(x: 60, y: 60))
}

@Test @MainActor func drawOverlaySmokeDoesNotCrash() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)  // 편집 대상
  tool.mouseUp(at(50, 30), context: context)
  tool.mouseDown(at(110, 60), context: context)  // 앵커 선택 (핸들 경로 포함)
  tool.mouseUp(at(110, 60), context: context)
  let bitmap = CGContext(
    data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  tool.drawOverlay(in: bitmap, scale: 2, context: context)
}
