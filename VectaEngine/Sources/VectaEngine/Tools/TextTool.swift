import CoreGraphics

/// 텍스트 생성/편집 도구 (T).
/// 클릭 지점의 최상위 노드가 TextNode이면 편집 요청,
/// 비어있거나 다른 노드이면 새 텍스트 생성 요청을 발행한다.
@MainActor
public final class TextTool: CanvasTool {
  public var cursorKind: CursorKind { .iBeam }

  public init() {}

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    let request = textEditRequest(for: event, in: context)
    context.requestTextEditing(request)
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {}
  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {}
}

// MARK: - 텍스트 히트 판정

extension TextTool {
  private func textEditRequest(
    for event: CanvasEvent, in context: ToolContext
  ) -> TextEditRequest {
    guard
      let hitID = HitTesting.topmostNodeID(
        at: event.point, in: context.store.document, tolerance: event.hitTolerance),
      case .text = context.store.document.topLevelNode(id: hitID)
    else {
      return .create(at: event.point)
    }
    return .edit(hitID)
  }
}
