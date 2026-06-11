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

  // resize/rotate/drawOverlay는 Task 7에서 구현 — 이 Task에서는 컴파일을 위한
  // 최소 본체만 둔다.
  func resize(
    to event: CanvasEvent, handle: SelectionHandle, baseBounds: CGRect, context: ToolContext
  ) {}

  func rotate(
    to event: CanvasEvent, center: CGPoint, startAngle: CGFloat, context: ToolContext
  ) {}

  func angle(from center: CGPoint, to point: CGPoint) -> CGFloat {
    atan2(point.y - center.y, point.x - center.x)
  }
}
