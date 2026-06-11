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
    // read(from:ofType:)는 SDK상 nonisolated이지만 canConcurrentlyReadDocuments
    // (기본 false)를 재정의하지 않는 한 메인 스레드에서 호출된다.
    // 이 클래스에서 canConcurrentlyReadDocuments를 절대 재정의하지 말 것.
    let vectorDocument = try AIFileReader.document(from: data)
    try MainActor.assumeIsolated {
      store.load(vectorDocument)
    }
  }
}
