import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

// MARK: - Fixtures

private let blackFill = Paint.color(RGBA(red: 0, green: 0, blue: 0))
private let redFill = Paint.color(RGBA(red: 1, green: 0, blue: 0))
private let blueFill = Paint.color(RGBA(red: 0, green: 0, blue: 1))

private func makeTextNode(
  string: String = "Hello",
  fontName: String = "Helvetica",
  fontSize: Double = 16,
  fill: Paint = blackFill,
  position: CGPoint = .zero
) -> TextNode {
  TextNode(
    string: string,
    fontName: fontName,
    fontSize: fontSize,
    fill: fill,
    position: position
  )
}

private func makePathNode() -> PathNode {
  PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black))
  )
}

@MainActor
private func makeStore(
  nodes: [Node],
  undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

// MARK: - T1: updateSelectedTextNodes — fontSize 변경 + undo 1단계

@Test @MainActor
func updateSelectedTextNodesChangesFontSizeAndUndoRestores() {
  // Arrange
  let undoManager = UndoManager()
  let textNode = makeTextNode(fontSize: 16)
  let store = makeStore(nodes: [.text(textNode)], undoManager: undoManager)
  store.select([textNode.id])

  // Act
  store.updateSelectedTextNodes(actionName: "폰트 크기 변경") { node in
    node.fontSize = 24
  }

  // Assert — 변경 반영
  #expect(store.selectionTextNode?.fontSize == 24)

  // Assert — undo 1회로 원복
  undoManager.undo()
  #expect(store.selectionTextNode?.fontSize == 16)
  #expect(!undoManager.canUndo)
}

// MARK: - T2: updateSelectedTextNodes — fontName·fill 변경 반영

@Test @MainActor
func updateSelectedTextNodesChangesFontNameAndFill() {
  // Arrange
  let textNode = makeTextNode(fontName: "Helvetica", fill: blackFill)
  let store = makeStore(nodes: [.text(textNode)])
  store.select([textNode.id])

  // Act
  store.updateSelectedTextNodes(actionName: "폰트/색 변경") { node in
    node.fontName = "Arial"
    node.fill = redFill
  }

  // Assert
  #expect(store.selectionTextNode?.fontName == "Arial")
  #expect(store.selectionTextNode?.fill == redFill)
}

// MARK: - T3: transient → commitTransient — 최종값 반영 & undo 1단계

@Test @MainActor
func transientTextFormattingCommitsAsSingleUndoStep() {
  // Arrange
  let undoManager = UndoManager()
  let textNode = makeTextNode(fontSize: 16)
  let store = makeStore(nodes: [.text(textNode)], undoManager: undoManager)
  store.select([textNode.id])

  // Act — 드래그 시뮬레이션: 여러 번 transient 갱신
  store.beginTransient()
  store.updateSelectedTextNodesTransient { node in node.fontSize = 20 }
  store.updateSelectedTextNodesTransient { node in node.fontSize = 24 }
  store.updateSelectedTextNodesTransient { node in node.fontSize = 28 }

  // Assert — 드래그 중 undo 미등록
  #expect(!undoManager.canUndo)

  // Act — 제스처 종료
  store.commitTransient(actionName: "폰트 크기")

  // Assert — 최종값 반영
  #expect(store.selectionTextNode?.fontSize == 28)

  // Assert — undo 1회로 원복 (단일 undo 단계)
  undoManager.undo()
  #expect(store.selectionTextNode?.fontSize == 16)
  #expect(!undoManager.canUndo)
}

// MARK: - T4: selectionTextNode 계약

@Test @MainActor
func selectionTextNodeReturnsSingleTextNodeWhenExactlyOneSelected() {
  // Arrange
  let textNode = makeTextNode()
  let store = makeStore(nodes: [.text(textNode)])

  // Act
  store.select([textNode.id])

  // Assert
  #expect(store.selectionTextNode?.id == textNode.id)
}

@Test @MainActor
func selectionTextNodeReturnsNilForMixedTextAndPathSelection() {
  // Arrange
  let textNode = makeTextNode()
  let pathNode = makePathNode()
  let store = makeStore(nodes: [.text(textNode), .path(pathNode)])

  // Act — 텍스트 + 패스 혼합 선택
  store.select([textNode.id, pathNode.id])

  // Assert
  #expect(store.selectionTextNode == nil)
}

@Test @MainActor
func selectionTextNodeReturnsNilWhenOnlyPathSelected() {
  // Arrange
  let pathNode = makePathNode()
  let store = makeStore(nodes: [.path(pathNode)])

  // Act
  store.select([pathNode.id])

  // Assert
  #expect(store.selectionTextNode == nil)
}

@Test @MainActor
func selectionTextNodeReturnsNilWhenNothingSelected() {
  // Arrange
  let textNode = makeTextNode()
  let store = makeStore(nodes: [.text(textNode)])

  // Act — 선택 없음 (기본 상태)

  // Assert
  #expect(store.selectionTextNode == nil)
}

@Test @MainActor
func selectionTextNodeReturnsNilWhenMultipleTextNodesSelected() {
  // Arrange
  let textNode1 = makeTextNode(string: "A")
  let textNode2 = makeTextNode(string: "B", position: CGPoint(x: 100, y: 0))
  let store = makeStore(nodes: [.text(textNode1), .text(textNode2)])

  // Act — 텍스트 2개 선택
  store.select([textNode1.id, textNode2.id])

  // Assert — 복수 선택이므로 nil
  #expect(store.selectionTextNode == nil)
}

// MARK: - T5: VectorDocument.updateTextNodes(ids:) 직접

@Test
func updateTextNodesOnlyChangesMatchingIds() {
  // Arrange
  let targetText = makeTextNode(string: "Target", fontSize: 16)
  let otherText = makeTextNode(string: "Other", fontSize: 16, position: CGPoint(x: 100, y: 0))
  let pathNode = makePathNode()
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.text(targetText), .text(otherText), .path(pathNode)]

  // Act — ids에 든 텍스트 노드만 변경
  document.updateTextNodes(ids: [targetText.id]) { node in
    node.fontSize = 32
  }

  // Assert — 대상 노드 변경됨
  guard case .text(let updatedTarget) = document.layers[0].nodes[0] else {
    Issue.record("첫 번째 노드가 TextNode여야 함")
    return
  }
  #expect(updatedTarget.fontSize == 32)

  // Assert — 다른 텍스트 노드 불변
  guard case .text(let updatedOther) = document.layers[0].nodes[1] else {
    Issue.record("두 번째 노드가 TextNode여야 함")
    return
  }
  #expect(updatedOther.fontSize == 16)

  // Assert — 패스 노드 불변
  guard case .path(let updatedPath) = document.layers[0].nodes[2] else {
    Issue.record("세 번째 노드가 PathNode여야 함")
    return
  }
  #expect(updatedPath.style.fill == .color(.black))
}

@Test
func updateTextNodesSkipsNonTextNodes() {
  // Arrange
  let pathNode = makePathNode()
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(pathNode)]

  // Act — 패스 노드 ID를 ids에 넣어도 TextNode 변경 클로저는 호출되지 않아야 함
  var closureCallCount = 0
  document.updateTextNodes(ids: [pathNode.id]) { node in
    closureCallCount += 1
    node.fontSize = 99
  }

  // Assert — 클로저 호출 없음
  #expect(closureCallCount == 0)

  // Assert — 패스 노드 불변
  guard case .path(let unchanged) = document.layers[0].nodes[0] else {
    Issue.record("노드가 PathNode여야 함")
    return
  }
  #expect(unchanged.id == pathNode.id)
}
