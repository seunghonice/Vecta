import AppKit
import Combine
import VectaEngine

/// 아트보드 크기와 동일한 frame을 갖는 문서 뷰. 모델 좌표 = 뷰 좌표(flipped).
final class CanvasView: NSView {
  private let store: DocumentStore
  private let toolState: ToolState
  private var dragStart: CGPoint?
  private var dragCurrent: CGPoint?
  private var storeSubscription: AnyCancellable?

  override var isFlipped: Bool { true }

  init(store: DocumentStore, toolState: ToolState) {
    self.store = store
    self.toolState = toolState
    super.init(frame: NSRect(origin: .zero, size: store.document.artboard.size))
    // objectWillChange는 변경 직전에 발행되지만 DispatchQueue 스케줄러는 항상
    // async 디스패치하므로 sink는 다음 런루프 틱(변경 완료 후)에 실행된다.
    storeSubscription = store.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.documentDidChange() }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Interface Builder를 사용하지 않는다")
  }

  private func documentDidChange() {
    // M1에서 아트보드 크기는 고정. 크기 변경 기능이 생기면 스크롤 위치 보존 필요.
    setFrameSize(store.document.artboard.size)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.setFillColor(CGColor.white)
    context.fill(CGRect(origin: .zero, size: store.document.artboard.size))
    SceneRenderer.render(store.document, in: context)
    drawDragPreview(in: context)
  }

  // MARK: - 도형 드래그

  override func mouseDown(with event: NSEvent) {
    // convert(_:from: nil)은 윈도우 좌표 → 뷰 좌표 변환으로,
    // NSScrollView magnification을 뷰 계층을 통해 자동 반영한다.
    dragStart = convert(event.locationInWindow, from: nil)
    dragCurrent = dragStart
  }

  override func mouseDragged(with event: NSEvent) {
    guard dragStart != nil else { return }
    dragCurrent = convert(event.locationInWindow, from: nil)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      dragStart = nil
      dragCurrent = nil
      needsDisplay = true
    }
    guard let start = dragStart else { return }
    let end = convert(event.locationInWindow, from: nil)
    let rect = CGRect(corner: start, oppositeCorner: end)
    guard rect.width >= 1, rect.height >= 1 else { return }
    let path = makePath(in: rect)
    store.apply(actionName: "도형 추가") { document in
      document.layers[0].nodes.append(
        .path(PathNode(path: path, style: .defaultShape)))
    }
  }

  private func makePath(in rect: CGRect) -> BezierPath {
    switch toolState.activeShape {
    case .rectangle: return .rectangle(rect)
    case .ellipse: return .ellipse(in: rect)
    }
  }

  private func drawDragPreview(in context: CGContext) {
    guard let start = dragStart, let current = dragCurrent else { return }
    let rect = CGRect(corner: start, oppositeCorner: current)
    guard case .color(let fillColor) = Style.defaultShape.fill else { return }
    context.saveGState()
    context.setAlpha(0.5)
    context.addPath(makePath(in: rect).cgPath)
    context.setFillColor(fillColor.cgColor)
    context.fillPath()
    context.restoreGState()
  }
}
