import CoreGraphics

/// 펜 도구 (P): 클릭=코너, 드래그=스무스, 시작점 클릭=닫기, Esc/Enter=종료.
/// 패스는 도구 로컬(PenPathBuilder)에서 작성되고 종료 시 apply 1회 = undo 1단계.
@MainActor
public final class PenTool: CanvasTool {
  private var builder = PenPathBuilder()
  private var isDraggingHandle = false
  private var rubberBandPoint: CGPoint?

  public var cursorKind: CursorKind { .crosshair }

  public init() {}

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    // 이중 mouseDown 이벤트 방어 (mouseUp 누락 시 앵커 중복 방지 — M2b 이월).
    guard !isDraggingHandle else { return }
    if builder.canClose(at: event.point, tolerance: event.hitTolerance * 1.5) {
      let path = builder.close()
      commit(path, context: context)
      return
    }
    builder.addAnchor(at: event.point)
    isDraggingHandle = true
    context.invalidateOverlay()
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    guard isDraggingHandle else { return }
    builder.dragHandle(to: event.point)
    context.invalidateOverlay()
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    isDraggingHandle = false
  }

  public func mouseMoved(_ event: CanvasEvent, context: ToolContext) {
    rubberBandPoint = event.point
    if builder.anchorCount > 0 {
      context.invalidateOverlay()
    }
  }

  /// 도구 전환 시 작성 중 패스를 완결한다 (Illustrator 동작 — 작업 보존).
  /// 앵커 2개 미만이면 버려진다.
  public func deactivate(context: ToolContext) {
    let path = builder.finishOpen()
    commit(path, context: context)
  }

  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool {
    switch key {
    case .enter, .escape:
      let path = builder.finishOpen()
      commit(path, context: context)
      return true
    case .delete:
      return false
    }
  }

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    guard builder.anchorCount > 0 else { return }
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setLineWidth(1 / scale)
    // builder.segments[0]은 항상 .move (addAnchor 첫 호출이 보장하는 불변식).
    assert(builder.segments.first?.isMove == true)
    // 작성 중 세그먼트
    let preview = BezierPath(subpaths: [Subpath(segments: builder.segments, isClosed: false)])
    cgContext.addPath(preview.cgPath)
    cgContext.strokePath()
    // 러버밴드 (마지막 앵커 → 마우스)
    if let last = builder.lastAnchor, let rubber = rubberBandPoint {
      cgContext.setLineDash(phase: 0, lengths: [3 / scale, 3 / scale])
      cgContext.move(to: last)
      cgContext.addLine(to: rubber)
      cgContext.strokePath()
      cgContext.setLineDash(phase: 0, lengths: [])
    }
    // 드래그 중 핸들 라인
    if let last = builder.lastAnchor, let handle = builder.pendingHandle {
      let mirrored = CGPoint(x: 2 * last.x - handle.x, y: 2 * last.y - handle.y)
      cgContext.move(to: mirrored)
      cgContext.addLine(to: handle)
      cgContext.strokePath()
    }
    // 앵커 사각형
    let side = 6 / scale
    cgContext.setFillColor(CGColor.white)
    for segment in builder.segments {
      let position = segment.endPoint
      let rect = CGRect(
        x: position.x - side / 2, y: position.y - side / 2, width: side, height: side)
      cgContext.fill(rect)
      cgContext.stroke(rect)
    }
    cgContext.restoreGState()
  }

  private func commit(_ path: BezierPath?, context: ToolContext) {
    rubberBandPoint = nil
    defer { context.invalidateOverlay() }
    guard let path else { return }
    context.store.appendNodeToActiveLayer(
      .path(PathNode(path: path, style: .defaultShape)), actionName: "패스 생성")
  }
}
