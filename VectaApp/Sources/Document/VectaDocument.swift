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
    // 자식(캔버스 scrollView 등)이 행 높이를 가득 채우게 한다 — 기본 .centerY는
    // scrollView를 intrinsic 높이(없음)로 찌그러뜨려 캔버스가 작아진다.
    horizontal.alignment = .height
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
    // 본문 행이 남는 세로 공간을 모두 채우도록 한다 — 기본 .gravityAreas는
    // horizontal을 intrinsic 높이로만 배치해 캔버스가 윈도우 끝까지 안 닿는다.
    vertical.distribution = .fill
    // 배너는 고정 높이(콘텐츠 크기) 유지 — 늘어나는 건 본문 행이다.
    banner.setContentHuggingPriority(.required, for: .vertical)
    banner.setContentCompressionResistancePriority(.required, for: .vertical)
    vertical.spacing = 0
    return vertical
  }

  /// 현재 importReport로 배너 뷰 모델을 만든다 — 열기·되돌리기 공용 단일 출처.
  private func makeBanner() -> ImportReportBanner {
    ImportReportBanner(report: importReport) { [weak self] in
      self?.bannerHost?.isHidden = true
    }
  }

  /// 배너 뷰를 NSHostingView로 감싼다 — makeContentView 전용 헬퍼.
  private func makeBannerView() -> NSHostingView<ImportReportBanner> {
    let banner = NSHostingView(rootView: makeBanner())
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
      // importReport는 이 블록 위에서 이미 할당됐으므로 makeBanner()가 최신값을 읽는다.
      if let host = bannerHost {
        host.rootView = makeBanner()
        host.isHidden = importReport.isEmpty
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

  // MARK: - 패스파인더 액션 (오브젝트 메뉴 — MainMenuBuilder가 연결)

  @objc func pathfinderUnite(_ sender: Any?) {
    store.applyPathfinder(.unite)
  }

  @objc func pathfinderSubtract(_ sender: Any?) {
    store.applyPathfinder(.subtract)
  }

  @objc func pathfinderIntersect(_ sender: Any?) {
    store.applyPathfinder(.intersect)
  }

  @objc func pathfinderExclude(_ sender: Any?) {
    store.applyPathfinder(.exclude)
  }

  // MARK: - 편집 메뉴 클립보드 액션

  @objc func copy(_ sender: Any?) {
    writeSelectionToPasteboard()
  }

  @objc func cut(_ sender: Any?) {
    guard writeSelectionToPasteboard() else { return }
    store.deleteSelection()
  }

  @objc func paste(_ sender: Any?) {
    let type = NSPasteboard.PasteboardType(NodeClipboard.pasteboardType)
    guard let data = NSPasteboard.general.data(forType: type),
      let nodes = NodeClipboard.decode(data)
    else { return }
    store.pasteNodes(nodes)
  }

  // 이름이 `duplicate(_:)`이면 NSDocument의 문서 복제 셀렉터와 충돌(#selector
  // 모호 + 타이틀바 복제 동작 변경)하므로 선택 복제 전용 이름을 쓴다.
  @objc func duplicateSelection(_ sender: Any?) {
    store.duplicateSelection()
  }

  /// 선택 노드를 NSPasteboard 커스텀 타입으로 쓴다. 빈 선택이면 false.
  @discardableResult
  private func writeSelectionToPasteboard() -> Bool {
    let nodes = store.copyableSelection()
    guard !nodes.isEmpty, let data = NodeClipboard.encode(nodes) else { return false }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setData(
      data, forType: NSPasteboard.PasteboardType(NodeClipboard.pasteboardType))
    return true
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
    case #selector(pathfinderUnite(_:)), #selector(pathfinderSubtract(_:)),
      #selector(pathfinderIntersect(_:)), #selector(pathfinderExclude(_:)):
      return store.combinablePathCount >= 2
    case #selector(copy(_:)), #selector(cut(_:)), #selector(duplicateSelection(_:)):
      return !store.selection.isEmpty
    case #selector(paste(_:)):
      // 데이터 전체를 역직렬화하지 않고 타입 존재만 확인 (메뉴 갱신마다 호출됨).
      let type = NSPasteboard.PasteboardType(NodeClipboard.pasteboardType)
      return NSPasteboard.general.availableType(from: [type]) != nil
    default:
      return super.validateUserInterfaceItem(item)
    }
  }
}
