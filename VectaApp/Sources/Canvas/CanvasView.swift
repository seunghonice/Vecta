import AppKit
import Combine
import VectaEngine

/// 아트보드 크기 frame의 문서 뷰. 모델 좌표 = 뷰 좌표(flipped).
/// NSEvent → CanvasEvent 변환과 활성 도구 디스패치만 담당하는 얇은 셸.
final class CanvasView: NSView {
  private static let viewHitTolerance: CGFloat = 4

  private let store: DocumentStore
  private let toolState: ToolState
  private let tools: [ToolKind: CanvasTool] = [
    .select: SelectTool(),
    .rectangle: ShapeTool(shape: .rectangle),
    .ellipse: ShapeTool(shape: .ellipse),
  ]
  private lazy var toolContext = ToolContext(store: store) { [weak self] in
    self?.needsDisplay = true
  }
  private var subscriptions: Set<AnyCancellable> = []

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  private var activeTool: CanvasTool { tools[toolState.activeTool]! }

  private var magnification: CGFloat {
    enclosingScrollView?.magnification ?? 1
  }

  init(store: DocumentStore, toolState: ToolState) {
    self.store = store
    self.toolState = toolState
    super.init(frame: NSRect(origin: .zero, size: store.document.artboard.size))
    // objectWillChange는 변경 직전 발행되지만 DispatchQueue 스케줄러는 항상
    // async 디스패치하므로 sink는 변경 완료 후 실행된다.
    store.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.documentDidChange() }
      .store(in: &subscriptions)
    toolState.$activeTool
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.activeToolDidChange() }
      .store(in: &subscriptions)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Interface Builder를 사용하지 않는다")
  }

  private func documentDidChange() {
    setFrameSize(store.document.artboard.size)
    needsDisplay = true
  }

  private func activeToolDidChange() {
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: activeTool.cursorKind.nsCursor)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
    cgContext.setFillColor(CGColor.white)
    cgContext.fill(CGRect(origin: .zero, size: store.document.artboard.size))
    SceneRenderer.render(store.document, in: cgContext)
    activeTool.drawOverlay(in: cgContext, scale: magnification, context: toolContext)
  }

  // MARK: - 이벤트 → CanvasEvent

  private func canvasEvent(from event: NSEvent) -> CanvasEvent {
    CanvasEvent(
      point: convert(event.locationInWindow, from: nil),
      isShiftPressed: event.modifierFlags.contains(.shift),
      clickCount: event.clickCount,
      hitTolerance: Self.viewHitTolerance / magnification)
  }

  override func mouseDown(with event: NSEvent) {
    activeTool.mouseDown(canvasEvent(from: event), context: toolContext)
  }

  override func mouseDragged(with event: NSEvent) {
    activeTool.mouseDragged(canvasEvent(from: event), context: toolContext)
  }

  override func mouseUp(with event: NSEvent) {
    activeTool.mouseUp(canvasEvent(from: event), context: toolContext)
  }

  // MARK: - 키보드

  override func keyDown(with event: NSEvent) {
    if handleToolShortcut(event) || handleToolKey(event) {
      return
    }
    super.keyDown(with: event)
  }

  private func handleToolShortcut(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
      let characters = event.charactersIgnoringModifiers?.lowercased()
    else { return false }
    switch characters {
    case "v": toolState.activeTool = .select
    case "m": toolState.activeTool = .rectangle
    case "l": toolState.activeTool = .ellipse
    default: return false
    }
    return true
  }

  private func handleToolKey(_ event: NSEvent) -> Bool {
    guard let key = canvasKey(from: event) else { return false }
    return activeTool.keyDown(key, context: toolContext)
  }

  private func canvasKey(from event: NSEvent) -> CanvasKey? {
    switch event.keyCode {
    case 51, 117: return .delete  // backspace, forward delete
    case 53: return .escape
    case 36, 76: return .enter  // return, keypad enter
    default: return nil
    }
  }

  override func selectAll(_ sender: Any?) {
    store.select(store.document.topLevelNodeIDs)
  }
}

extension CursorKind {
  var nsCursor: NSCursor {
    switch self {
    case .arrow: return .arrow
    case .crosshair: return .crosshair
    }
  }
}
