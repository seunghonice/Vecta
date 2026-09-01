import AppKit
import VectaEngine

/// 캔버스 위 `NSTextView` 오버레이로 점 텍스트를 인라인 입력·편집하는 세션.
///
/// 엔진은 배치(생성/편집 판정)만 하고, 실제 문자 입력은 AppKit이 담당한다
/// (한글 IME·캐럿·선택·텍스트 내 복붙은 네이티브). flipped 호스트 뷰에서
/// 모델 좌표 = 뷰 좌표이며, 스크롤뷰 magnification이 서브뷰를 자동 스케일하므로
/// 폰트는 모델 포인트 크기 그대로 쓴다.
@MainActor
final class TextEditingSession: NSObject, NSTextViewDelegate {
  /// 빈/짧은 텍스트의 최소 폭 (캐럿이 들어갈 공간). 내용이 길어지면 자동 확장된다.
  private static let minimumWidth: CGFloat = 8
  /// 마지막 글자/캐럿이 잘리지 않도록 두는 뒤쪽 여유.
  private static let trailingPad: CGFloat = 3

  private unowned let host: NSView
  private let store: DocumentStore
  private let textView: NSTextView
  private let mode: Mode

  /// 확정 1회 보장 — Esc·바깥클릭·도구전환·창비활성이 겹쳐도 한 번만 실행.
  private var hasCommitted = false
  /// 프로그램적 제거가 트리거하는 `textDidEndEditing` 재진입 차단.
  private var isCommitting = false

  /// 확정 후 호스트에 종료를 통지 (editingNodeID 해제·리드로우·포커스 복귀).
  private let onFinish: () -> Void

  private enum Mode {
    case create(at: CGPoint)
    case edit(id: NodeID)
  }

  /// 생성/편집 요청으로 세션을 시작한다.
  init?(
    request: TextEditRequest, host: NSView, store: DocumentStore,
    onFinish: @escaping () -> Void
  ) {
    self.host = host
    self.store = store
    self.onFinish = onFinish

    let seed: Seed
    switch request {
    case .create(let point):
      mode = .create(at: point)
      seed = Seed.creating(at: point)
    case .edit(let id):
      guard case .text(let textNode)? = store.document.topLevelNode(id: id) else { return nil }
      mode = .edit(id: id)
      seed = Seed.editing(textNode)
    }

    textView = TextEditingSession.makeTextView(seed: seed)
    super.init()
    textView.delegate = self
    begin()
  }

  /// 편집 대상 노드 ID — 호스트가 렌더에서 제외(`excluding`)할 노드.
  var editingNodeID: NodeID? {
    if case .edit(let id) = mode { return id }
    return nil
  }

  // MARK: - 시작

  private func begin() {
    host.addSubview(textView)
    host.window?.makeFirstResponder(textView)
    textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
    sizeToFitContent()
  }

  private static func makeTextView(seed: Seed) -> NSTextView {
    let font = seed.font
    let frame = textViewFrame(seed: seed, font: font)
    let textView = NSTextView(frame: frame)
    textView.isRichText = false
    textView.drawsBackground = false
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.font = font
    textView.textColor = seed.fill.nsColor
    textView.string = seed.string
    // 점 텍스트 — soft-wrap 금지(명시적 \n만 줄바꿈). 컨테이너를 무한폭으로 두고
    // 내용 크기로 그린다(아래 sizeToFitContent): 오버레이가 글자에 딱 맞아야
    // 바깥 클릭이 캔버스에 닿아 확정된다(넓으면 클릭이 투명 텍스트뷰에 먹힘).
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = true
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.containerSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.minSize = frame.size
    textView.maxSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    return textView
  }

  /// 모델 baseline → flipped 뷰 top 보정 (첫 줄 ascent만큼 위로). 폭은 최소폭으로
  /// 시작하고 내용에 맞춰 sizeToFitContent가 확장한다.
  private static func textViewFrame(seed: Seed, font: NSFont) -> NSRect {
    let originX = seed.position.x
    let originY = seed.position.y - font.ascender
    let height = font.ascender - font.descender + font.leading
    return NSRect(x: originX, y: originY, width: Self.minimumWidth, height: height)
  }

  /// 텍스트뷰 프레임을 내용 크기로 맞춘다 — 오버레이를 글자에 딱 맞게 유지해
  /// 바깥 클릭이 캔버스(확정)로 전달되게 한다. 원점(baseline 기준)은 보존.
  private func sizeToFitContent() {
    guard let layoutManager = textView.layoutManager,
      let container = textView.textContainer
    else { return }
    layoutManager.ensureLayout(for: container)
    let used = layoutManager.usedRect(for: container)
    var frame = textView.frame
    frame.size.width = max(Self.minimumWidth, ceil(used.width) + Self.trailingPad)
    frame.size.height = max(frame.size.height, ceil(used.height))
    textView.frame = frame
  }

  /// 타이핑할 때마다 오버레이를 내용 크기로 재조정.
  func textDidChange(_ notification: Notification) {
    sizeToFitContent()
  }

  // MARK: - 확정

  /// 텍스트뷰 내용을 엔진에 반영하고 세션을 종료한다 (1회만 실행).
  func commit() {
    guard !hasCommitted else { return }
    hasCommitted = true
    isCommitting = true
    let string = textView.string
    switch mode {
    case .create(let point):
      commitCreate(string: string, at: point)
    case .edit(let id):
      store.commitTextEdit(id: id, string: string)
    }
    textView.removeFromSuperview()
    isCommitting = false
    onFinish()
  }

  private func commitCreate(string: String, at point: CGPoint) {
    guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let node = TextNode(
      string: string, fontName: TextDefaults.fontName,
      fontSize: Double(TextDefaults.fontSize), fill: .color(TextDefaults.fill),
      position: point)
    store.appendNodeToActiveLayer(.text(node), actionName: "텍스트 추가")
    store.select([node.id])
  }

  // MARK: - 확정 트리거

  /// Esc — 현재 텍스트 확정 (결정 a: 별도 취소 없음, 되돌리기는 undo).
  /// 멀티라인이므로 Enter/Return(`insertNewline:`)은 가로채지 않고 줄바꿈으로 둔다.
  func textView(
    _ textView: NSTextView, doCommandBy commandSelector: Selector
  ) -> Bool {
    guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
    commit()
    return true
  }

  /// 포커스 상실 — 바깥 클릭·창 비활성·도구 전환으로 first responder 이동.
  /// 프로그램적 제거(commit)는 `isCommitting` 가드로 재진입 차단.
  func textDidEndEditing(_ notification: Notification) {
    guard !isCommitting else { return }
    commit()
  }
}

/// 생성 모드 기본 서식 — 임의 하드코딩 대신 의미 있는 상수 단일 출처.
private enum TextDefaults {
  static let fontName = "Helvetica"
  static let fontSize: CGFloat = 24
  static let fill: RGBA = .black
}

/// 텍스트뷰 초기 상태 (생성/편집 공통 시드).
private struct Seed {
  let string: String
  let fontName: String
  let fontSize: CGFloat
  let fill: RGBA
  let position: CGPoint

  var font: NSFont {
    NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
  }

  static func creating(at point: CGPoint) -> Seed {
    Seed(
      string: "", fontName: TextDefaults.fontName,
      fontSize: TextDefaults.fontSize, fill: TextDefaults.fill, position: point)
  }

  static func editing(_ node: TextNode) -> Seed {
    Seed(
      string: node.string, fontName: node.fontName,
      fontSize: CGFloat(node.fontSize), fill: node.fillColor, position: node.position)
  }
}

extension TextNode {
  /// 편집 시드용 텍스트 색 — 단색이면 그 색, 아니면 검정.
  fileprivate var fillColor: RGBA {
    if case .color(let rgba) = fill { return rgba }
    return .black
  }
}

extension RGBA {
  /// sRGB 성분 → NSColor (텍스트뷰 textColor용).
  fileprivate var nsColor: NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }
}
