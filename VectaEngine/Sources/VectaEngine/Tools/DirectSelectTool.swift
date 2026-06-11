import CoreGraphics

/// 직접 선택 도구 (A): 최상위 패스 노드의 앵커·컨트롤 핸들을 드래그 편집한다.
/// M2b 범위: 그룹 내부 진입과 앵커 추가/삭제는 비목표 (M3 이후).
@MainActor
public final class DirectSelectTool: CanvasTool {
  private enum DragState {
    case idle
    case anchor(NodeID, AnchorRef)
    case control(NodeID, ControlRef)
  }

  private var dragState: DragState = .idle
  public private(set) var editNodeID: NodeID?
  public private(set) var selectedAnchor: AnchorRef?

  public var cursorKind: CursorKind { .arrow }

  public init() {}

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    if case .idle = dragState {
    } else {
      context.store.cancelTransient()
      dragState = .idle
    }
    let store = context.store
    let handleTolerance = event.hitTolerance * 1.5
    if let nodeID = editNodeID, let pathNode = topLevelPathNode(nodeID, in: store.document) {
      // 앵커가 핸들보다 우선 — 핸들이 앵커와 겹치면 앵커가 잡힌다 (Illustrator/Figma 동일).
      if let hitAnchor = hitAnchor(in: pathNode, at: event.point, tolerance: handleTolerance) {
        selectedAnchor = hitAnchor
        store.beginTransient()
        dragState = .anchor(nodeID, hitAnchor)
        context.invalidateOverlay()
        return
      }
      if let anchor = selectedAnchor,
        let hitControl = hitControl(
          in: pathNode, anchor: anchor, at: event.point, tolerance: handleTolerance)
      {
        store.beginTransient()
        dragState = .control(nodeID, hitControl)
        return
      }
    }
    if let hitID = HitTesting.topmostNodeID(
      at: event.point, in: store.document, tolerance: event.hitTolerance),
      case .path? = store.document.topLevelNode(id: hitID)
    {
      editNodeID = hitID
      selectedAnchor = nil
      context.invalidateOverlay()
      return
    }
    editNodeID = nil
    selectedAnchor = nil
    context.invalidateOverlay()
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .anchor(let nodeID, let ref):
      editPath(of: nodeID, context: context) { pathNode in
        guard let local = self.localPoint(event.point, in: pathNode) else { return pathNode.path }
        return pathNode.path.movingAnchor(ref, to: local)
      }
    case .control(let nodeID, let ref):
      editPath(of: nodeID, context: context) { pathNode in
        guard let local = self.localPoint(event.point, in: pathNode) else { return pathNode.path }
        return pathNode.path.movingControl(ref, to: local)
      }
    case .idle:
      break
    }
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    let finished = dragState
    dragState = .idle
    switch finished {
    case .anchor:
      context.store.commitTransient(actionName: "앵커 이동")
    case .control:
      context.store.commitTransient(actionName: "핸들 이동")
    case .idle:
      break
    }
  }

  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool {
    guard key == .escape else { return false }
    if case .idle = dragState {
    } else {
      context.store.cancelTransient()
      dragState = .idle
    }
    editNodeID = nil
    selectedAnchor = nil
    context.invalidateOverlay()
    return true
  }

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    guard let nodeID = editNodeID,
      let pathNode = topLevelPathNode(nodeID, in: context.store.document)
    else { return }
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    let transform = pathNode.transform.cgAffineTransform
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setLineWidth(1 / scale)
    var pathTransform = transform
    if let outline = pathNode.path.cgPath.copy(using: &pathTransform) {
      cgContext.addPath(outline)
      cgContext.strokePath()
    }
    let side = 7 / scale
    for (ref, localPosition) in pathNode.path.anchors() {
      let position = localPosition.applying(transform)
      let rect = CGRect(
        x: position.x - side / 2, y: position.y - side / 2, width: side, height: side)
      cgContext.setFillColor(ref == selectedAnchor ? accent : CGColor.white)
      cgContext.fill(rect)
      cgContext.stroke(rect)
    }
    if let anchor = selectedAnchor, let anchorLocal = pathNode.path.anchorPosition(anchor) {
      let anchorPosition = anchorLocal.applying(transform)
      for (_, handleLocal) in pathNode.path.controlHandles(forAnchor: anchor) {
        let handlePosition = handleLocal.applying(transform)
        cgContext.move(to: anchorPosition)
        cgContext.addLine(to: handlePosition)
        cgContext.strokePath()
        let radius = 3.5 / scale
        cgContext.setFillColor(accent)
        cgContext.fillEllipse(
          in: CGRect(
            x: handlePosition.x - radius, y: handlePosition.y - radius,
            width: radius * 2, height: radius * 2))
      }
    }
    cgContext.restoreGState()
  }

  // MARK: - 헬퍼

  private func topLevelPathNode(_ id: NodeID, in document: VectorDocument) -> PathNode? {
    guard case .path(let pathNode)? = document.topLevelNode(id: id) else { return nil }
    return pathNode
  }

  private func localPoint(_ point: CGPoint, in pathNode: PathNode) -> CGPoint? {
    guard let inverse = pathNode.transform.invertedOrNil else { return nil }
    return point.applying(inverse)
  }

  private func hitAnchor(
    in pathNode: PathNode, at point: CGPoint, tolerance: CGFloat
  ) -> AnchorRef? {
    let transform = pathNode.transform.cgAffineTransform
    return pathNode.path.anchors().first { _, localPosition in
      let position = localPosition.applying(transform)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }?.ref
  }

  private func hitControl(
    in pathNode: PathNode, anchor: AnchorRef, at point: CGPoint, tolerance: CGFloat
  ) -> ControlRef? {
    let transform = pathNode.transform.cgAffineTransform
    return pathNode.path.controlHandles(forAnchor: anchor).first { _, localPosition in
      let position = localPosition.applying(transform)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }?.ref
  }

  private func editPath(
    of nodeID: NodeID, context: ToolContext, _ newPath: @escaping (PathNode) -> BezierPath
  ) {
    context.store.updateTransient { document in
      document.updateTopLevelNodes(ids: [nodeID]) { node in
        guard case .path(var pathNode) = node else { return node }
        pathNode.path = newPath(pathNode)
        return .path(pathNode)
      }
    }
  }
}
