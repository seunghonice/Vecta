import AppKit
import VoidaEngine

final class VoidaDocument: NSDocument {
  private(set) lazy var store = DocumentStore(document: .empty()) {
    [weak self] in self?.undoManager
  }

  override class var autosavesInPlace: Bool { true }

  override func makeWindowControllers() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.center()
    addWindowController(NSWindowController(window: window))
  }
}
