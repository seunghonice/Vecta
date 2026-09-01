import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

// MARK: - 헬퍼

@MainActor
private func makeStore(
  textNode: TextNode,
  extraNodes: [Node] = [],
  undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.text(textNode)] + extraNodes
  return DocumentStore(document: document) { undoManager }
}

private func makeTextNode(string: String = "Hello") -> TextNode {
  TextNode(
    string: string,
    fontName: "Helvetica",
    fontSize: 24,
    fill: .color(.black),
    position: CGPoint(x: 100, y: 100)
  )
}

// MARK: - commitTextEdit: 문자열 치환

@Test @MainActor func commitTextEditReplacesStringInDocument() {
  // Arrange
  let textNode = makeTextNode(string: "Hello")
  let store = makeStore(textNode: textNode)

  // Act
  store.commitTextEdit(id: textNode.id, string: "World")

  // Assert
  guard case .text(let updated) = store.document.topLevelNode(id: textNode.id) else {
    Issue.record("TextNode를 찾을 수 없음")
    return
  }
  #expect(updated.string == "World")
}

// MARK: - commitTextEdit: 치환 후 undo 1회 → 원래 string 복원

@Test @MainActor func commitTextEditUndoRestoresOriginalString() {
  // Arrange
  let undoManager = UndoManager()
  let textNode = makeTextNode(string: "Hello")
  let store = makeStore(textNode: textNode, undoManager: undoManager)

  // Act
  store.commitTextEdit(id: textNode.id, string: "World")
  #expect(undoManager.canUndo)
  undoManager.undo()

  // Assert — 원래 string으로 복원
  guard case .text(let restored) = store.document.topLevelNode(id: textNode.id) else {
    Issue.record("undo 후 TextNode를 찾을 수 없음")
    return
  }
  #expect(restored.string == "Hello")
  #expect(!undoManager.canUndo)
}

// MARK: - commitTextEdit: 빈 문자열 → 노드 삭제 + undo 1회 → 노드 복원

@Test @MainActor func commitTextEditWithEmptyStringDeletesNode() {
  // Arrange
  let textNode = makeTextNode(string: "Hello")
  let store = makeStore(textNode: textNode)

  // Act
  store.commitTextEdit(id: textNode.id, string: "")

  // Assert — 노드가 문서에서 사라짐
  #expect(store.document.topLevelNode(id: textNode.id) == nil)
  #expect(!store.document.topLevelNodeIDs.contains(textNode.id))
}

@Test @MainActor func commitTextEditWithWhitespaceOnlyDeletesNode() {
  // 공백/개행만 남은 편집도 "비어있음"으로 보고 삭제 — 생성 경로와 대칭 (R1).
  let textNode = makeTextNode(string: "Hello")
  let store = makeStore(textNode: textNode)

  store.commitTextEdit(id: textNode.id, string: "  \n \t")

  #expect(store.document.topLevelNode(id: textNode.id) == nil)
}

@Test @MainActor func commitTextEditWithEmptyStringUndoRestoresNode() {
  // Arrange
  let undoManager = UndoManager()
  let textNode = makeTextNode(string: "Hello")
  let store = makeStore(textNode: textNode, undoManager: undoManager)

  // Act
  store.commitTextEdit(id: textNode.id, string: "")
  #expect(undoManager.canUndo)
  undoManager.undo()

  // Assert — 노드 복원
  guard case .text(let restored) = store.document.topLevelNode(id: textNode.id) else {
    Issue.record("undo 후 TextNode를 찾을 수 없음")
    return
  }
  #expect(restored.string == "Hello")
}

// MARK: - VectorDocument.updateTextNode: fontSize / fontName 변경

@Test func updateTextNodeChangesFontSizeAndFontName() {
  // Arrange
  let textNode = makeTextNode()
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.text(textNode)]

  // Act
  document.updateTextNode(id: textNode.id) { node in
    node.fontSize = 48
    node.fontName = "Times New Roman"
  }

  // Assert
  guard case .text(let updated) = document.topLevelNode(id: textNode.id) else {
    Issue.record("TextNode를 찾을 수 없음")
    return
  }
  #expect(updated.fontSize == 48)
  #expect(updated.fontName == "Times New Roman")
}

// MARK: - VectorDocument.updateTextNode: 비텍스트 노드에 호출 → no-op

@Test func updateTextNodeOnPathNodeIsNoOp() {
  // Arrange
  let pathNode = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black))
  )
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.path(pathNode)]
  let before = document

  // Act — 패스 노드 id에 updateTextNode 호출
  document.updateTextNode(id: pathNode.id) { node in
    node.fontSize = 99
    node.fontName = "NonExistentFont"
  }

  // Assert — 문서가 변경 없어야 함
  #expect(document == before)
}

// MARK: - DocumentStore.updateTextNode(id:actionName:): 선택 비의존 단건 타겟

@Test @MainActor func storeUpdateTextNodeTargetsOnlyGivenIdRegardlessOfSelection() {
  // 인스펙터 색/서식 경로 — 표시 노드 id를 직접 타겟하므로 선택과 무관하게 그 노드만.
  let target = makeTextNode(string: "A")
  let other = makeTextNode(string: "B")
  let store = makeStore(textNode: target, extraNodes: [.text(other)])
  store.select([other.id])  // 일부러 다른 노드를 선택

  store.updateTextNode(id: target.id, actionName: "텍스트 색 변경") {
    $0.fill = .color(RGBA(red: 1, green: 0, blue: 0, alpha: 1))
  }

  guard case .text(let t) = store.document.topLevelNode(id: target.id),
    case .color(let targetColor) = t.fill,
    case .text(let o) = store.document.topLevelNode(id: other.id),
    case .color(let otherColor) = o.fill
  else {
    Issue.record("노드를 찾을 수 없음")
    return
  }
  #expect(targetColor == RGBA(red: 1, green: 0, blue: 0, alpha: 1))
  #expect(otherColor == .black)  // 선택돼 있어도 변경 안 됨
}

@Test @MainActor func storeUpdateTextNodeIsSingleUndoStep() {
  let undoManager = UndoManager()
  let node = makeTextNode(string: "A")
  let store = makeStore(textNode: node, undoManager: undoManager)

  store.updateTextNode(id: node.id, actionName: "글자 크기 변경") { $0.fontSize = 48 }
  #expect(undoManager.canUndo)
  undoManager.undo()

  guard case .text(let restored) = store.document.topLevelNode(id: node.id) else {
    Issue.record("undo 후 노드를 찾을 수 없음")
    return
  }
  #expect(restored.fontSize == 24)
}
