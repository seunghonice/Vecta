import AppKit
import SwiftUI
import VectaEngine

final class VectaDocument: NSDocument {
  private(set) lazy var store = DocumentStore(document: .empty()) {
    [weak self] in self?.undoManager
  }
  private let toolState = ToolState()
  /// 마지막 열기에서 수집된 임포트 리포트 (배너 표시용 — Task 13).
  private(set) var importReport = ImportReport.empty
  /// 항상 마운트된 배너 호스팅 뷰 — 되돌리기(Revert) 갱신에도 사용.
  private weak var bannerHost: NSHostingView<ImportReportBanner>?

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
    let sidePanel = NSHostingView(rootView: SidePanelView(store: store))
    let horizontal = NSStackView(views: [toolbar, scrollView, sidePanel])
    horizontal.orientation = .horizontal
    horizontal.distribution = .fill
    horizontal.spacing = 0
    sidePanel.widthAnchor.constraint(equalToConstant: 260).isActive = true

    // 배너는 항상 마운트 — NSStackView가 isHidden 뷰를 레이아웃에서 분리하므로
    // 빈 리포트일 때도 시각 결과는 동일. 이렇게 하면 Revert 재실행 시
    // 배너 마운트 포인트가 보장된다.
    let banner = makeBannerView()
    bannerHost = banner
    let vertical = NSStackView(views: [banner, horizontal])
    vertical.orientation = .vertical
    vertical.alignment = .width
    vertical.spacing = 0
    return vertical
  }

  /// 리포트로 배너를 만들거나 숨긴다 — 열기(윈도우 생성)와 되돌리기(read 재실행) 양쪽에서 호출.
  private func makeBannerView() -> NSHostingView<ImportReportBanner> {
    let banner = NSHostingView(
      rootView: ImportReportBanner(report: importReport) { [weak self] in
        self?.bannerHost?.isHidden = true
      })
    banner.isHidden = importReport.isEmpty
    return banner
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
    let result = try AIFileReader.read(from: data)
    MainActor.assumeIsolated {
      store.load(result.document)
      importReport = result.report
      // Revert 경로: makeWindowControllers 없이 read가 재실행되므로
      // 기존 bannerHost를 새 리포트로 갱신한다.
      if let host = bannerHost {
        host.rootView = ImportReportBanner(report: result.report) { [weak self] in
          self?.bannerHost?.isHidden = true
        }
        host.isHidden = result.report.isEmpty
      }
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
