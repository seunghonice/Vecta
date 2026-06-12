import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(at origin: CGPoint = CGPoint(x: 10, y: 10)) -> PathNode {
  PathNode(
    path: .rectangle(CGRect(origin: origin, size: CGSize(width: 100, height: 50))),
    style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

private func expectClose(
  _ actual: CGFloat, _ expected: CGFloat,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(abs(actual - expected) < 0.0001, sourceLocation: sourceLocation)
}

@Test @MainActor func moveSelectionSetsBoundsOrigin() {
  let node = rect()
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.moveSelection(x: 50)
  expectClose(store.selectionBounds!.minX, 50)
  expectClose(store.selectionBounds!.minY, 10)  // y 유지
  store.moveSelection(y: 80)
  expectClose(store.selectionBounds!.minY, 80)
  expectClose(store.selectionBounds!.minX, 50)  // x 유지
}

@Test @MainActor func resizeSelectionAnchorsTopLeft() {
  let node = rect()
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.resizeSelection(width: 200)
  let bounds = store.selectionBounds!
  expectClose(bounds.width, 200)
  expectClose(bounds.height, 50)  // 비율 독립
  expectClose(bounds.minX, 10)  // 좌상단 고정
  expectClose(bounds.minY, 10)
}

@Test @MainActor func resizeSelectionRejectsNonPositive() {
  let node = rect()
  let undoManager = UndoManager()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.select([node.id])
  store.resizeSelection(width: 0)
  store.resizeSelection(height: -5)
  expectClose(store.selectionBounds!.width, 100)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func rotateSelectionByNinetyDegreesSwapsBoundsAroundCenter() {
  let node = rect()  // bounds (10,10,100,50), 중심 (60,35)
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.rotateSelection(byDegrees: 90)
  let bounds = store.selectionBounds!
  expectClose(bounds.width, 50)
  expectClose(bounds.height, 100)
  expectClose(bounds.midX, 60)  // 중심 유지
  expectClose(bounds.midY, 35)
}

@Test @MainActor func rotationDegreesExtractsAngleFromTransform() {
  var node = rect()
  node.transform = Transform2D(CGAffineTransform(rotationAngle: 30 * .pi / 180))
  #expect(abs(Node.path(node).rotationDegrees - 30) < 0.0001)
  #expect(Node.path(rect()).rotationDegrees == 0)
}

@Test @MainActor func transformCommandIsSingleUndoStep() {
  let undoManager = UndoManager()
  let node = rect()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.select([node.id])
  store.moveSelection(x: 50)
  undoManager.undo()
  expectClose(store.selectionBounds!.minX, 10)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func resizeMultiSelectionScalesPositionsProportionally() {
  // 공통 좌상단 기준 스케일 — 노드 간 간격도 함께 늘어난다 (상대 배치 보존)
  let first = rect(at: CGPoint(x: 10, y: 10))  // (10,10,100,50)
  let second = rect(at: CGPoint(x: 130, y: 10))  // (130,10,100,50) → union (10,10,220,50)
  let store = makeStore(nodes: [.path(first), .path(second)])
  store.select([first.id, second.id])
  store.resizeSelection(width: 440)  // scaleX = 2
  let bounds = store.selectionBounds!
  expectClose(bounds.width, 440)
  expectClose(bounds.minX, 10)
  guard case .path(let scaledSecond)? = store.document.topLevelNode(id: second.id) else {
    Issue.record("패스가 아님")
    return
  }
  // second 원점: 10 + (130-10)*2 = 250
  expectClose(Node.path(scaledSecond).bounds.minX, 250)
}

@Test @MainActor func resizeRotatedNodeShearsByDesign() {
  // 회전된 노드의 비균일 스케일은 전단을 만든다 — 알려진 한계의 특성 고정 테스트.
  // AABB 폭이 목표값과 일치하는지가 아니라, 연산이 적용되어 바운드가 변했는지만 고정한다.
  let node = rect()  // (10,10,100,50)
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.rotateSelection(byDegrees: 30)
  let rotatedBounds = store.selectionBounds!
  store.resizeSelection(width: rotatedBounds.width * 2)
  let resized = store.selectionBounds!
  expectClose(resized.width, rotatedBounds.width * 2)
  expectClose(resized.minX, rotatedBounds.minX)  // 좌상단 고정 유지
}

@Test @MainActor func rotateSelectionAccumulatesDeltas() {
  let node = rect()
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.rotateSelection(byDegrees: 30)
  store.rotateSelection(byDegrees: 60)
  guard let id = store.selection.first,
    let rotated = store.document.topLevelNode(id: id)
  else {
    Issue.record("노드 없음")
    return
  }
  #expect(abs(rotated.rotationDegrees - 90) < 0.0001)
}
