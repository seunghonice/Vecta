import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private let red = RGBA(red: 1, green: 0, blue: 0)
private let blue = RGBA(red: 0, green: 0, blue: 1)

private func rect(_ frame: CGRect, fill: RGBA = .black) -> PathNode {
  PathNode(path: .rectangle(frame), style: Style(fill: .color(fill)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func pathfinderUniteReplacesSelectionWithSinglePath() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let b = rect(CGRect(x: 50, y: 50, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  store.applyPathfinder(.unite)
  #expect(store.document.layers[0].nodes.count == 1)
  guard case .path(let result) = store.document.layers[0].nodes[0] else {
    Issue.record("결과가 패스 노드가 아님")
    return
  }
  let bounds = Node.path(result).bounds
  #expect(abs(bounds.minX - 0) < 0.5)
  #expect(abs(bounds.minY - 0) < 0.5)
  #expect(abs(bounds.maxX - 150) < 0.5)
  #expect(abs(bounds.maxY - 150) < 0.5)
  #expect(store.selection == [result.id])
}

@Test @MainActor func pathfinderIntersectBoundsIsOverlap() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let b = rect(CGRect(x: 50, y: 50, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  store.applyPathfinder(.intersect)
  let bounds = store.document.layers[0].nodes[0].bounds
  #expect(abs(bounds.minX - 50) < 0.5)
  #expect(abs(bounds.minY - 50) < 0.5)
  #expect(abs(bounds.maxX - 100) < 0.5)
  #expect(abs(bounds.maxY - 100) < 0.5)
}

@Test @MainActor func pathfinderSubtractRemovesTopFromBottom() {
  let bottom = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let top = rect(CGRect(x: 50, y: 0, width: 100, height: 100))
  let store = makeStore(nodes: [.path(bottom), .path(top)])
  store.select([bottom.id, top.id])
  store.applyPathfinder(.subtract)
  let bounds = store.document.layers[0].nodes[0].bounds
  #expect(abs(bounds.minX - 0) < 0.5)
  #expect(abs(bounds.maxX - 50) < 0.5)
}

@Test @MainActor func pathfinderUsesBottomMostStyle() {
  let bottom = rect(CGRect(x: 0, y: 0, width: 100, height: 100), fill: red)
  let top = rect(CGRect(x: 50, y: 50, width: 100, height: 100), fill: blue)
  let store = makeStore(nodes: [.path(bottom), .path(top)])
  store.select([bottom.id, top.id])
  store.applyPathfinder(.unite)
  guard case .path(let result) = store.document.layers[0].nodes[0],
    case .color(let color) = result.style.fill
  else {
    Issue.record("결과 스타일을 읽을 수 없음")
    return
  }
  #expect(color == red)
}

@Test @MainActor func pathfinderRequiresTwoPaths() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a)])
  store.select([a.id])
  store.applyPathfinder(.unite)
  #expect(store.document.layers[0].nodes.count == 1)
  #expect(store.document.layers[0].nodes[0].id == a.id)
}

@Test @MainActor func pathfinderIgnoresNonPathNodes() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let text = TextNode(
    string: "안녕", fontName: "Helvetica", fontSize: 12,
    fill: .color(.black), position: CGPoint(x: 10, y: 10))
  let store = makeStore(nodes: [.path(a), .text(text)])
  store.select([a.id, text.id])
  store.applyPathfinder(.unite)
  #expect(store.document.layers[0].nodes.count == 2)
}

@Test @MainActor func pathfinderPreservesNonPathNodesInSelection() {
  // 패스 2개 + 텍스트 1개 동시 선택 → 패스만 결합되고 텍스트는 남는다.
  let bottom = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let top = rect(CGRect(x: 50, y: 50, width: 100, height: 100))
  let text = TextNode(
    string: "안녕", fontName: "Helvetica", fontSize: 12,
    fill: .color(.black), position: CGPoint(x: 10, y: 10))
  let store = makeStore(nodes: [.path(bottom), .path(top), .text(text)])
  store.select([bottom.id, top.id, text.id])
  store.applyPathfinder(.unite)
  // 결합 패스 1개 + 텍스트 1개 = 2개.
  #expect(store.document.layers[0].nodes.count == 2)
  #expect(store.document.layers[0].nodes.contains { $0.id == text.id })
}

@Test @MainActor func pathfinderIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let b = rect(CGRect(x: 50, y: 50, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a), .path(b)], undoManager: undoManager)
  store.select([a.id, b.id])
  store.applyPathfinder(.unite)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id, b.id])
  #expect(!undoManager.canUndo)
}

@Test @MainActor func combinablePathCountCountsOnlyPaths() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let text = TextNode(
    string: "x", fontName: "Helvetica", fontSize: 12,
    fill: .color(.black), position: .zero)
  let store = makeStore(nodes: [.path(a), .text(text)])
  store.select([a.id, text.id])
  #expect(store.combinablePathCount == 1)
}
