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

  override func data(ofType typeName: String) throws -> Data {
    // data(ofType:)는 NSDocument 문서화 상 메인 스레드 호출 보장.
    // Swift 6 격리 분석이 놓치므로 assumeIsolated로 명시.
    try MainActor.assumeIsolated {
      try AIFileWriter.data(for: store.document)
    }
  }

  override func read(from data: Data, ofType typeName: String) throws {
    // read(from:ofType:)도 메인 스레드 보장 — assumeIsolated 사용.
    let vectorDocument = try AIFileReader.document(from: data)
    MainActor.assumeIsolated {
      store.load(vectorDocument)
    }
  }
}
