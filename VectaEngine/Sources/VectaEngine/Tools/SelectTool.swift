import CoreGraphics

/// 선택 도구 (V): 클릭/Shift 토글/마퀴 선택, 드래그 이동,
/// 핸들 리사이즈·코너 바깥 회전 (Task 7에서 확장).
@MainActor
public final class SelectTool: CanvasTool {
  enum DragState {
    case idle
    case movingSelection(start: CGPoint)
    case marquee(start: CGPoint, current: CGPoint)
    case resizing(handle: SelectionHandle, baseBounds: CGRect)
    case rotating(center: CGPoint, startAngle: CGFloat)
  }

  var dragState: DragState = .idle
  public var cursorKind: CursorKind { .arrow }

  public init() {}

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    let store = context.store
    if let bounds = store.selectionBounds {
      let handleTolerance = event.hitTolerance * 1.5
      if let handle = SelectionHandle.hitHandle(
        at: event.point, bounds: bounds, tolerance: handleTolerance)
      {
        store.beginTransient()
        dragState = .resizing(handle: handle, baseBounds: bounds)
        return
      }
      if SelectionHandle.isInRotationZone(
        event.point, bounds: bounds, tolerance: handleTolerance)
      {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        store.beginTransient()
        dragState = .rotating(center: center, startAngle: angle(from: center, to: event.point))
        return
      }
    }
    if let hitID = HitTesting.topmostNodeID(
      at: event.point, in: store.document, tolerance: event.hitTolerance)
    {
      if event.isShiftPressed {
        store.toggleSelection(hitID)
      } else if !store.selection.contains(hitID) {
        store.select([hitID])
      }
      if store.selection.contains(hitID) {
        store.beginTransient()
        dragState = .movingSelection(start: event.point)
      }
      return
    }
    if !event.isShiftPressed {
      store.clearSelection()
    }
    dragState = .marquee(start: event.point, current: event.point)
    context.invalidateOverlay()
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .movingSelection(let start):
      let delta = CGVector(dx: event.point.x - start.x, dy: event.point.y - start.y)
      let ids = context.store.selection
      context.store.updateTransient { document in
        document.updateTopLevelNodes(ids: ids) {
          NodeTransformer.translated($0, by: delta)
        }
      }
    case .marquee(let start, _):
      dragState = .marquee(start: start, current: event.point)
      context.invalidateOverlay()
    case .resizing(let handle, let baseBounds):
      resize(to: event, handle: handle, baseBounds: baseBounds, context: context)
    case .rotating(let center, let startAngle):
      rotate(to: event, center: center, startAngle: startAngle, context: context)
    case .idle:
      break
    }
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .movingSelection:
      context.store.commitTransient(actionName: "이동")
    case .resizing:
      context.store.commitTransient(actionName: "크기 조절")
    case .rotating:
      context.store.commitTransient(actionName: "회전")
    case .marquee(let start, _):
      let rect = CGRect(corner: start, oppositeCorner: event.point)
      let hits = HitTesting.topLevelNodeIDs(intersecting: rect, in: context.store.document)
      if event.isShiftPressed {
        context.store.select(context.store.selection.union(hits))
      } else {
        context.store.select(hits)
      }
      context.invalidateOverlay()
    case .idle:
      break
    }
    dragState = .idle
  }

  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool {
    switch key {
    case .delete:
      context.store.deleteSelection()
      return true
    case .escape:
      if case .idle = dragState {
        context.store.clearSelection()
      } else {
        context.store.cancelTransient()
        dragState = .idle
        context.invalidateOverlay()
      }
      return true
    case .enter:
      return false
    }
  }

  private static let minimumScaleDenominator: CGFloat = 0.001
  private static let minimumScale: CGFloat = 0.01

  func resize(
    to event: CanvasEvent, handle: SelectionHandle, baseBounds: CGRect, context: ToolContext
  ) {
    let anchor = handle.anchor(in: baseBounds)
    let handleStart = handle.position(in: baseBounds)
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    if handle.scalesX {
      scaleX = safeRatio(event.point.x - anchor.x, handleStart.x - anchor.x)
    }
    if handle.scalesY {
      scaleY = safeRatio(event.point.y - anchor.y, handleStart.y - anchor.y)
    }
    if event.isShiftPressed && handle.scalesX && handle.scalesY {
      let uniform = max(abs(scaleX), abs(scaleY))
      scaleX = scaleX < 0 ? -uniform : uniform
      scaleY = scaleY < 0 ? -uniform : uniform
    }
    let ids = context.store.selection
    context.store.updateTransient { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.resized($0, anchor: anchor, scaleX: scaleX, scaleY: scaleY)
      }
    }
  }

  func rotate(
    to event: CanvasEvent, center: CGPoint, startAngle: CGFloat, context: ToolContext
  ) {
    let delta = angle(from: center, to: event.point) - startAngle
    let ids = context.store.selection
    context.store.updateTransient { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.rotated($0, around: center, by: delta)
      }
    }
  }

  /// 분모가 0에 가까우면 1, 결과가 0에 가까우면 최소 스케일로 클램프
  /// (특이 행렬 방지 — 0 스케일은 역변환 불가).
  private func safeRatio(_ numerator: CGFloat, _ denominator: CGFloat) -> CGFloat {
    guard abs(denominator) > Self.minimumScaleDenominator else { return 1 }
    let ratio = numerator / denominator
    if abs(ratio) < Self.minimumScale {
      return ratio < 0 ? -Self.minimumScale : Self.minimumScale
    }
    return ratio
  }

  func angle(from center: CGPoint, to point: CGPoint) -> CGFloat {
    atan2(point.y - center.y, point.x - center.x)
  }

  // MARK: - 오버레이

  private static let handleScreenSize: CGFloat = 8
  private static let selectionLineScreenWidth: CGFloat = 1

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    if let bounds = context.store.selectionBounds {
      drawSelectionChrome(bounds: bounds, in: cgContext, scale: scale)
    }
    if case .marquee(let start, let current) = dragState {
      drawMarquee(
        rect: CGRect(corner: start, oppositeCorner: current), in: cgContext, scale: scale)
    }
  }

  private func drawSelectionChrome(bounds: CGRect, in cgContext: CGContext, scale: CGFloat) {
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setLineWidth(Self.selectionLineScreenWidth / scale)
    cgContext.stroke(bounds)
    let side = Self.handleScreenSize / scale
    cgContext.setFillColor(CGColor.white)
    for handle in SelectionHandle.allCases {
      let position = handle.position(in: bounds)
      let rect = CGRect(
        x: position.x - side / 2, y: position.y - side / 2, width: side, height: side)
      cgContext.fill(rect)
      cgContext.stroke(rect)
    }
    cgContext.restoreGState()
  }

  private func drawMarquee(rect: CGRect, in cgContext: CGContext, scale: CGFloat) {
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setFillColor(CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 0.1))
    cgContext.setLineWidth(Self.selectionLineScreenWidth / scale)
    cgContext.setLineDash(phase: 0, lengths: [4 / scale, 4 / scale])
    cgContext.fill(rect)
    cgContext.stroke(rect)
    cgContext.restoreGState()
  }
}
