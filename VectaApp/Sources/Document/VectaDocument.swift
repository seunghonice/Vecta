import AppKit
import SwiftUI
import VectaEngine

final class VectaDocument: NSDocument {
  private(set) lazy var store = DocumentStore(document: .empty()) {
    [weak self] in self?.undoManager
  }
  private let toolState = ToolState()

  override class var autosavesInPlace: Bool { true }

  override func makeWindowControllers() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    let canvasView = CanvasView(store: store, toolState: toolState)
    window.contentView = makeContentView(canvasView: canvasView)
    window.initialFirstResponder = canvasView
    window.center()
    addWindowController(NSWindowController(window: window))
  }

  private func makeContentView(canvasView: CanvasView) -> NSView {
    let scrollView = NSScrollView()
    scrollView.documentView = canvasView
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.1
    scrollView.maxMagnification = 64
    scrollView.backgroundColor = .windowBackgroundColor

    let toolbar = NSHostingView(rootView: ToolbarView(toolState: toolState))
    let stack = NSStackView(views: [toolbar, scrollView])
    stack.orientation = .horizontal
    stack.distribution = .fill
    stack.spacing = 0
    return stack
  }

  override func data(ofType typeName: String) throws -> Data {
    // data(ofType:)는 NSDocument 문서화 상 메인 스레드 호출 보장.
    // Swift 6 격리 분석이 놓치므로 assumeIsolated로 명시.
    try MainActor.assumeIsolated {
      try AIFileWriter.data(for: store.document)
    }
  }

  override func read(from data: Data, ofType typeName: String) throws {
    // read(from:ofType:)는 SDK상 nonisolated이지만 canConcurrentlyReadDocuments
    // (기본 false)를 재정의하지 않는 한 메인 스레드에서 호출된다.
    // 이 클래스에서 canConcurrentlyReadDocuments를 절대 재정의하지 말 것.
    let vectorDocument = try AIFileReader.document(from: data)
    MainActor.assumeIsolated {
      store.load(vectorDocument)
    }
  }

  // MARK: - 오브젝트 메뉴 액션 (응답 체인 — MainMenuBuilder가 연결)

  @objc func groupSelection(_ sender: Any?) {
    store.groupSelection()
  }

  @objc func ungroupSelection(_ sender: Any?) {
    store.ungroupSelection()
  }

  @objc func bringForward(_ sender: Any?) {
    store.bringSelectionForward()
  }

  @objc func sendBackward(_ sender: Any?) {
    store.sendSelectionBackward()
  }

  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(groupSelection(_:)), #selector(bringForward(_:)),
      #selector(sendBackward(_:)):
      return !store.selection.isEmpty
    case #selector(ungroupSelection(_:)):
      return store.selection.contains { id in
        if case .group? = store.document.topLevelNode(id: id) { return true }
        return false
      }
    default:
      return super.validateUserInterfaceItem(item)
    }
  }
}
