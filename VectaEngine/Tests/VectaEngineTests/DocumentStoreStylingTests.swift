import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private let red = RGBA(red: 1, green: 0, blue: 0)

private func rect(at origin: CGPoint = .zero) -> PathNode {
  PathNode(
    path: .rectangle(CGRect(origin: origin, size: CGSize(width: 50, height: 50))),
    style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func updateSelectionStylesChangesFillWithSingleUndo() {
  let undoManager = UndoManager()
  let node = rect()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.select([node.id])
  store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
    style.fill = .color(red)
  }
  #expect(store.selectionPathStyle?.fill == .color(red))
  undoManager.undo()
  #expect(store.selectionPathStyle?.fill == .color(.black))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func styleChangeOnGroupReachesPathDescendants() {
  let inner = rect()
  let nested = rect(at: CGPoint(x: 100, y: 0))
  let innerGroup = GroupNode(children: [.path(nested)])
  let group = GroupNode(children: [.path(inner), .group(innerGroup)])
  let store = makeStore(nodes: [.group(group)])
  store.select([group.id])
  store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
    style.fill = .color(red)
  }
  guard case .group(let updated)? = store.document.topLevelNode(id: group.id),
    case .path(let updatedInner) = updated.children[0],
    case .group(let updatedInnerGroup) = updated.children[1],
    case .path(let updatedNested) = updatedInnerGroup.children[0]
  else {
    Issue.record("구조가 다름")
    return
  }
  #expect(updatedInner.style.fill == .color(red))
  #expect(updatedNested.style.fill == .color(red))
}

@Test @MainActor func selectionPathStyleReturnsFrontmostPath() {
  let back = rect()
  var front = rect(at: CGPoint(x: 100, y: 0))
  front.style = Style(fill: .color(red))
  let store = makeStore(nodes: [.path(back), .path(front)])
  store.select([back.id, front.id])
  #expect(store.selectionPathStyle?.fill == .color(red))
}

@Test @MainActor func emptySelectionStyleUpdateIsNoOp() {
  let node = rect()
  let undoManager = UndoManager()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
    style.fill = .color(red)
  }
  #expect(!undoManager.canUndo)
}

@Test @MainActor func updateSelectionStylesProvidesLocalPathBounds() {
  // 그라디언트 기본 선분 계산용 — 클로저에 노드의 로컬 패스 바운드가 온다
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 20, width: 80, height: 40)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(translationX: 500, y: 0)))
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  var captured: CGRect?
  store.updateSelectionStyles(actionName: "확인") { style, bounds in
    captured = bounds
    style.fill = .color(red)  // 변경 없으면 apply가 무시하므로 더미 변경
  }
  #expect(captured == CGRect(x: 10, y: 20, width: 80, height: 40))
}

@Test @MainActor func transientStyleUpdateCommitsAsSingleUndoStep() {
  let undoManager = UndoManager()
  let node = rect()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.select([node.id])
  store.beginTransient()
  store.updateSelectionStylesTransient { style, _ in style.opacity = 0.7 }
  store.updateSelectionStylesTransient { style, _ in style.opacity = 0.4 }
  #expect(!undoManager.canUndo)  // 드래그 중에는 undo 미등록
  store.commitTransient(actionName: "불투명도")
  #expect(store.selectionPathStyle?.opacity == 0.4)
  undoManager.undo()
  #expect(store.selectionPathStyle?.opacity == 1)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func transientStyleUpdateWithoutBeginIsSilentNoOp() {
  let node = rect()
  let store = makeStore(nodes: [.path(node)], undoManager: nil)
  store.select([node.id])
  store.updateSelectionStylesTransient { style, _ in style.opacity = 0.5 }
  #expect(store.selectionPathStyle?.opacity == 1)
}
