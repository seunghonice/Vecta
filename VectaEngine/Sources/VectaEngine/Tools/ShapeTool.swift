import CoreGraphics

/// 사각형/타원 생성 도구 (M/L). 드래그 미리보기는 오버레이로 그리고
/// mouseUp에 apply 1회 (= undo 1단계).
@MainActor
public final class ShapeTool: CanvasTool {
  public enum Shape {
    case rectangle
    case ellipse
  }

  private let shape: Shape
  private var dragStart: CGPoint?
  private var dragCurrent: CGPoint?
  private var shiftPressed = false

  public var cursorKind: CursorKind { .crosshair }

  public init(shape: Shape) {
    self.shape = shape
  }

  /// 드래그 두 점 → 정규화 rect. Shift면 큰 변 기준 정사각형 (방향 유지).
  public nonisolated static func dragRect(
    from start: CGPoint, to end: CGPoint, constrainSquare: Bool
  ) -> CGRect {
    guard constrainSquare else {
      return CGRect(corner: start, oppositeCorner: end)
    }
    let side = max(abs(end.x - start.x), abs(end.y - start.y))
    let constrainedEnd = CGPoint(
      x: start.x + (end.x < start.x ? -side : side),
      y: start.y + (end.y < start.y ? -side : side))
    return CGRect(corner: start, oppositeCorner: constrainedEnd)
  }

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    dragStart = event.point
    dragCurrent = event.point
    shiftPressed = event.isShiftPressed
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    guard dragStart != nil else { return }
    dragCurrent = event.point
    shiftPressed = event.isShiftPressed
    context.invalidateOverlay()
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    defer {
      dragStart = nil
      dragCurrent = nil
      context.invalidateOverlay()
    }
    guard let start = dragStart else { return }
    // 확정 결과가 마지막 프리뷰와 일치하도록(WYSIWYG) 저장된 Shift 상태를
    // 사용한다 — mouseUp 시점의 modifier가 아니라 마지막 드래그 기준.
    let rect = Self.dragRect(from: start, to: event.point, constrainSquare: shiftPressed)
    guard rect.width >= 1, rect.height >= 1 else { return }
    let path = makePath(in: rect)
    context.store.apply(actionName: "도형 추가") { document in
      document.layers[0].nodes.append(.path(PathNode(path: path, style: .defaultShape)))
    }
  }

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    guard let start = dragStart, let current = dragCurrent else { return }
    let rect = Self.dragRect(from: start, to: current, constrainSquare: shiftPressed)
    guard case .color(let fill) = Style.defaultShape.fill else { return }
    cgContext.saveGState()
    cgContext.setAlpha(0.5)
    cgContext.addPath(makePath(in: rect).cgPath)
    cgContext.setFillColor(fill.cgColor)
    cgContext.fillPath()
    cgContext.restoreGState()
  }

  private func makePath(in rect: CGRect) -> BezierPath {
    switch shape {
    case .rectangle: return .rectangle(rect)
    case .ellipse: return .ellipse(in: rect)
    }
  }
}
