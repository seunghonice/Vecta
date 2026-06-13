import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(_ frame: CGRect) -> PathNode {
  PathNode(path: .rectangle(frame), style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func alignLeftMovesNodesToSelectionLeft() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let left = store.selectionBounds!.minX  // 10
  store.alignSelection(edge: .left)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.minX - left) < 0.5)
  }
}

@Test @MainActor func alignRightMovesNodesToSelectionRight() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let right = store.selectionBounds!.maxX  // 180
  store.alignSelection(edge: .right)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.maxX - right) < 0.5)
  }
}

@Test @MainActor func alignCenterVerticalCentersNodes() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let midY = store.selectionBounds!.midY
  store.alignSelection(edge: .centerVertical)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.midY - midY) < 0.5)
  }
}

@Test @MainActor func alignTopMovesNodesToSelectionTop() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let top = store.selectionBounds!.minY  // 10 (모델 y-아래: 위 = 작은 y)
  store.alignSelection(edge: .top)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.minY - top) < 0.5)
  }
}

@Test @MainActor func alignCenterHorizontalCentersNodes() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let midX = store.selectionBounds!.midX
  store.alignSelection(edge: .centerHorizontal)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.midX - midX) < 0.5)
  }
}

@Test @MainActor func alignBottomMovesNodesToSelectionBottom() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let bottom = store.selectionBounds!.maxY  // 130 (모델 y-아래: 아래 = 큰 y)
  store.alignSelection(edge: .bottom)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.maxY - bottom) < 0.5)
  }
}

@Test @MainActor func alignRequiresTwoNodes() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let store = makeStore(nodes: [.path(a)])
  store.select([a.id])
  store.alignSelection(edge: .left)
  #expect(store.document.layers[0].nodes[0].bounds.minX == 10)  // 변화 없음
}

@Test @MainActor func alignIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)], undoManager: undoManager)
  store.select([a.id, b.id])
  store.alignSelection(edge: .left)
  undoManager.undo()
  #expect(store.document.layers[0].nodes[0].bounds.minX == 10)
  #expect(store.document.layers[0].nodes[1].bounds.minX == 100)
}
