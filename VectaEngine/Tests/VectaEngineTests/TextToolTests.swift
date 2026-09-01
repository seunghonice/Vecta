import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

// MARK: - 헬퍼

@MainActor
private func makeTextNode(at position: CGPoint) -> TextNode {
  TextNode(
    string: "Hello",
    fontName: "Helvetica",
    fontSize: 24,
    fill: .color(.black),
    position: position
  )
}

@MainActor
private func makePathNode(covering rect: CGRect) -> PathNode {
  PathNode(
    path: .rectangle(rect),
    style: Style(fill: .color(.black))
  )
}

/// TextNode 한 개를 문서에 포함한 ToolContext와 TextTool을 반환한다.
@MainActor
private func makeTextToolContext(
  textPosition: CGPoint = CGPoint(x: 100, y: 100)
) -> (context: ToolContext, tool: TextTool, textNodeID: NodeID) {
  let textNode = makeTextNode(at: textPosition)
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.text(textNode)]
  let context = ToolContext(store: DocumentStore(document: document))
  return (context, TextTool(), textNode.id)
}

/// 클릭 이벤트 생성 헬퍼.
private func click(
  _ x: CGFloat, _ y: CGFloat, clickCount: Int = 1
) -> CanvasEvent {
  CanvasEvent(
    point: CGPoint(x: x, y: y),
    isShiftPressed: false,
    clickCount: clickCount,
    hitTolerance: 4
  )
}

// MARK: - TextTool 테스트

@Test @MainActor func textToolCursorIsIBeam() {
  let tool = TextTool()
  #expect(tool.cursorKind == .iBeam)
}

@Test @MainActor func textToolClickOnTextNodeRequestsEdit() {
  // Arrange
  let (context, tool, textNodeID) = makeTextToolContext(
    textPosition: CGPoint(x: 100, y: 100)
  )
  var captured: TextEditRequest?
  context.requestTextEditing = { captured = $0 }

  // Act — TextNode position(100, 100) bounds 내부를 클릭
  tool.mouseDown(click(100, 100), context: context)

  // Assert
  #expect(captured == .edit(textNodeID))
}

@Test @MainActor func textToolClickOnEmptyCanvasRequestsCreate() {
  // Arrange
  let (context, tool, _) = makeTextToolContext(
    textPosition: CGPoint(x: 100, y: 100)
  )
  var captured: TextEditRequest?
  context.requestTextEditing = { captured = $0 }

  // Act — 노드가 없는 빈 영역 클릭
  let emptyPoint = CGPoint(x: 300, y: 300)
  tool.mouseDown(click(300, 300), context: context)

  // Assert
  #expect(captured == .create(at: emptyPoint))
}

@Test @MainActor func textToolClickOnPathNodeRequestsCreate() {
  // Arrange — PathNode가 TextNode 위를 덮는 상황
  let textNode = makeTextNode(at: CGPoint(x: 100, y: 100))
  let coveringPath = makePathNode(covering: CGRect(x: 80, y: 80, width: 100, height: 50))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  // 레이어 순서: text 먼저, path 나중(= 최상위)
  document.layers[0].nodes = [.text(textNode), .path(coveringPath)]
  let context = ToolContext(store: DocumentStore(document: document))
  let tool = TextTool()
  var captured: TextEditRequest?
  context.requestTextEditing = { captured = $0 }

  // Act — PathNode가 덮고 있는 지점 클릭
  let clickPoint = CGPoint(x: 110, y: 100)
  tool.mouseDown(click(110, 100), context: context)

  // Assert — 최상위 노드가 패스이므로 create
  #expect(captured == .create(at: clickPoint))
}

// MARK: - SelectTool 더블클릭 테스트

@Test @MainActor func selectToolDoubleClickOnTextNodeRequestsEdit() {
  // Arrange
  let textNode = makeTextNode(at: CGPoint(x: 100, y: 100))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.text(textNode)]
  let context = ToolContext(store: DocumentStore(document: document))
  let tool = SelectTool()
  var captured: TextEditRequest?
  context.requestTextEditing = { captured = $0 }

  // Act — clickCount=2 더블클릭
  tool.mouseDown(
    CanvasEvent(
      point: CGPoint(x: 100, y: 100),
      isShiftPressed: false,
      clickCount: 2,
      hitTolerance: 4
    ),
    context: context
  )

  // Assert
  #expect(captured == .edit(textNode.id))
}

@Test @MainActor func selectToolSingleClickOnTextNodeDoesNotRequestEdit() {
  // Arrange
  let textNode = makeTextNode(at: CGPoint(x: 100, y: 100))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.text(textNode)]
  let context = ToolContext(store: DocumentStore(document: document))
  let tool = SelectTool()
  var captured: TextEditRequest?
  context.requestTextEditing = { captured = $0 }

  // Act — clickCount=1 싱글클릭
  tool.mouseDown(click(100, 100, clickCount: 1), context: context)
  tool.mouseUp(click(100, 100, clickCount: 1), context: context)

  // Assert — requestTextEditing 호출 없음, 기존 선택 동작만
  #expect(captured == nil)
  #expect(context.store.selection.contains(textNode.id))
}
