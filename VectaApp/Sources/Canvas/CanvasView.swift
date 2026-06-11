import AppKit
import Combine
import VectaEngine

/// 아트보드 크기 frame의 문서 뷰. 모델 좌표 = 뷰 좌표(flipped).
/// NSEvent → CanvasEvent 변환과 활성 도구 디스패치만 담당하는 얇은 셸.
final class CanvasView: NSView {
  private static let viewHitTolerance: CGFloat = 4

  private let store: DocumentStore
  private let toolState: ToolState
  // ToolKind.allCases × makeTool()로 전 케이스가 보장된다 (팩토리가 망라 switch).
  // 도구 인스턴스는 제스처 상태를 보유하므로 여기서 1회 생성 후 캐시한다.
  private let tools: [ToolKind: CanvasTool] = Dictionary(
    uniqueKeysWithValues: ToolKind.allCases.map { ($0, $0.makeTool()) })
  private lazy var toolContext = ToolContext(store: store) { [weak self] in
    self?.needsDisplay = true
  }
  private var subscriptions: Set<AnyCancellable> = []
  private var canvasTrackingArea: NSTrackingArea?
  private var currentToolKind: ToolKind

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  private var activeTool: CanvasTool { tools[toolState.activeTool]! }

  private var magnification: CGFloat {
    enclosingScrollView?.magnification ?? 1
  }

  init(store: DocumentStore, toolState: ToolState) {
    self.store = store
    self.toolState = toolState
    self.currentToolKind = toolState.activeTool
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
    let newKind = toolState.activeTool
    guard newKind != currentToolKind else { return }
    // 이전 도구의 미완 작업 정리 (펜: 미완 패스 완결, 직접선택: 편집 해제,
    // 선택: transient 취소).
    tools[currentToolKind]?.deactivate(context: toolContext)
    store.cancelTransient()
    currentToolKind = newKind
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: activeTool.cursorKind.nsCursor)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let canvasTrackingArea {
      removeTrackingArea(canvasTrackingArea)
    }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    canvasTrackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    activeTool.mouseMoved(canvasEvent(from: event), context: toolContext)
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
    case "a": toolState.activeTool = .directSelect
    case "p": toolState.activeTool = .pen
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
