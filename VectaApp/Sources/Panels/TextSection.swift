import AppKit
import SwiftUI
import VectaEngine

/// 텍스트 섹션 행 레이블 폭 — 폰트/크기/색 행의 컨트롤 좌단을 한 열로 정렬
/// (TransformSection의 레이블 정렬 idiom과 동일한 의도).
private let textRowLabelWidth: CGFloat = 28

/// 인스펙터 텍스트 섹션 — 폰트 패밀리, 크기, 색.
/// 각 행은 표시 중인 노드 id를 직접 타겟해 변경한다(선택 상태 비의존).
struct TextSection: View {
  @ObservedObject var store: DocumentStore
  let textNode: TextNode

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("텍스트").font(.headline)
      FontFamilyRow(store: store, textNode: textNode)
      FontSizeRow(store: store, textNode: textNode)
      TextColorRow(store: store, textNode: textNode).id(textNode.id)
    }
  }
}

// MARK: - Private subviews

/// 폰트 패밀리 Picker — 시스템에 설치된 폰트 목록.
private struct FontFamilyRow: View {
  @ObservedObject var store: DocumentStore
  let textNode: TextNode

  private static let availableFamilies: [String] = {
    NSFontManager.shared.availableFontFamilies.sorted()
  }()

  /// 현재 fontName에 맞는 패밀리. PostScript명(예: "ArialMT")이면 패밀리명("Arial")으로
  /// 역산해 임포트 텍스트가 엉뚱한 패밀리로 표시되는 것을 막는다. 그래도 없으면 첫 패밀리.
  private var currentFamily: String {
    let name = textNode.fontName
    if Self.availableFamilies.contains(name) { return name }
    if let resolved = NSFont(name: name, size: 12)?.familyName,
      Self.availableFamilies.contains(resolved)
    {
      return resolved
    }
    return Self.availableFamilies.first ?? name
  }

  var body: some View {
    HStack(spacing: 4) {
      Text("폰트").foregroundStyle(.secondary)
        .frame(width: textRowLabelWidth, alignment: .trailing)
      Picker("폰트", selection: familyBinding) {
        ForEach(Self.availableFamilies, id: \.self) { family in
          Text(family).tag(family)
        }
      }
      .labelsHidden()
      .accessibilityLabel("폰트 패밀리")
    }
  }

  private var familyBinding: Binding<String> {
    Binding(
      get: { currentFamily },
      set: { newFamily in
        store.updateTextNode(id: textNode.id, actionName: "폰트 변경") { $0.fontName = newFamily }
      })
  }
}

/// 폰트 크기 필드 — Enter/포커스 아웃 시 확정, 최소값 1.
private struct FontSizeRow: View {
  @ObservedObject var store: DocumentStore
  let textNode: TextNode

  var body: some View {
    HStack(spacing: 4) {
      Text("크기").foregroundStyle(.secondary)
        .frame(width: textRowLabelWidth, alignment: .trailing)
      CommittingNumberField(value: CGFloat(textNode.fontSize)) { newSize in
        let clamped = max(1, newSize)
        store.updateTextNode(id: textNode.id, actionName: "글자 크기 변경") {
          $0.fontSize = Double(clamped)
        }
      }
      .frame(width: InspectorLayout.fieldWidth)
      Text("pt").foregroundStyle(.secondary)
    }
  }
}

/// 텍스트 색. SwiftUI ColorPicker는 macOS에서 computed binding의 set을 신뢰성 있게
/// 호출하지 않으므로 로컬 @State에 바인딩하고 .onChange로 반영한다. 변경은 표시 중인
/// 노드 id를 직접 타겟하고(선택 비결합), 모델과 다를 때만 적용해 되돌림 루프를 막는다.
/// (.id(textNode.id)로 노드별 @State가 보존되어 stale 리셋이 없으므로 별도 resync 불필요.)
private struct TextColorRow: View {
  @ObservedObject var store: DocumentStore
  let textNode: TextNode

  var body: some View {
    HStack(spacing: 4) {
      Text("색").foregroundStyle(.secondary)
        .frame(width: textRowLabelWidth, alignment: .trailing)
      ColorWellView(color: Self.rgba(of: textNode).nsColor) { newColor in
        let rgba = RGBA(srgb: newColor)
        store.updateTextNode(id: textNode.id, actionName: "텍스트 색 변경") {
          $0.fill = .color(rgba)
        }
      }
      .frame(width: 44, height: 22)
      Spacer()
    }
  }

  private static func rgba(of node: TextNode) -> RGBA {
    if case .color(let rgba) = node.fill { return rgba }
    return RGBA(red: 0, green: 0, blue: 0, alpha: 1)
  }
}

/// AppKit NSColorWell 래퍼. SwiftUI ColorPicker의 공유 NSColorPanel 재진입
/// 오실레이션(색→검정 되쏨)을 피하려고 직접 감싼다. 액션이 모델에 쓰고,
/// updateNSView는 값이 다를 때만 모델→well 동기화해 피드백 루프를 막는다.
private struct ColorWellView: NSViewRepresentable {
  let color: NSColor
  let onChange: (NSColor) -> Void

  func makeNSView(context: Context) -> NSColorWell {
    let well = NSColorWell()
    well.colorWellStyle = .minimal
    well.color = color
    well.target = context.coordinator
    well.action = #selector(Coordinator.colorChanged(_:))
    return well
  }

  func updateNSView(_ well: NSColorWell, context: Context) {
    context.coordinator.onChange = onChange
    // 모델 → well 동기화는 값이 실제로 다를 때만 (재렌더 시 되쏨/피드백 차단).
    if !well.color.isApproximately(color) { well.color = color }
  }

  func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

  final class Coordinator: NSObject {
    var onChange: (NSColor) -> Void
    init(onChange: @escaping (NSColor) -> Void) { self.onChange = onChange }
    @objc func colorChanged(_ sender: NSColorWell) { onChange(sender.color) }
  }
}

extension NSColor {
  /// sRGB 성분 근사 비교 (피드백 루프 방지용).
  fileprivate func isApproximately(_ other: NSColor) -> Bool {
    guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else {
      return self == other
    }
    let epsilon = 1.0 / 512.0
    return abs(a.redComponent - b.redComponent) < epsilon
      && abs(a.greenComponent - b.greenComponent) < epsilon
      && abs(a.blueComponent - b.blueComponent) < epsilon
      && abs(a.alphaComponent - b.alphaComponent) < epsilon
  }
}

extension RGBA {
  fileprivate var nsColor: NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }
  fileprivate init(srgb nsColor: NSColor) {
    let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
    self.init(
      red: c.redComponent, green: c.greenComponent, blue: c.blueComponent,
      alpha: c.alphaComponent)
  }
}
