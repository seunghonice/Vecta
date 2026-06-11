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
