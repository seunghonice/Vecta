import AppKit
import SwiftUI
import VectaEngine

/// 텍스트 섹션 행 레이블 폭 — 폰트/크기/색 행의 컨트롤 좌단을 한 열로 정렬
/// (TransformSection의 레이블 정렬 idiom과 동일한 의도).
private let textRowLabelWidth: CGFloat = 28

/// 인스펙터 텍스트 섹션 — 폰트 패밀리, 크기, 색.
struct TextSection: View {
  @ObservedObject var store: DocumentStore
  let textNode: TextNode

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("텍스트").font(.headline)
      FontFamilyRow(store: store, textNode: textNode)
      FontSizeRow(store: store, textNode: textNode)
      TextColorRow(store: store, textNode: textNode)
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
        store.updateSelectedTextNodes(actionName: "폰트 변경") { $0.fontName = newFamily }
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
        store.updateSelectedTextNodes(actionName: "글자 크기 변경") { $0.fontSize = Double(clamped) }
      }
      .frame(width: InspectorLayout.fieldWidth)
      Text("pt").foregroundStyle(.secondary)
    }
  }
}

/// 텍스트 색 — FillSection 단색 편집과 동일하게 변경 시 apply 1회 (undo 1단계).
private struct TextColorRow: View {
  @ObservedObject var store: DocumentStore
  let textNode: TextNode

  var body: some View {
    HStack(spacing: 4) {
      Text("색").foregroundStyle(.secondary)
        .frame(width: textRowLabelWidth, alignment: .trailing)
      ColorPicker("색", selection: colorBinding).labelsHidden()
      Spacer()
    }
  }

  private var currentRGBA: RGBA {
    if case .color(let rgba) = textNode.fill { return rgba }
    return RGBA(red: 0, green: 0, blue: 0, alpha: 1)
  }

  private var colorBinding: Binding<Color> {
    Binding(
      get: { currentRGBA.swiftUIColor },
      set: { newColor in
        let rgba = RGBA(newColor)
        store.updateSelectedTextNodes(actionName: "텍스트 색 변경") { $0.fill = .color(rgba) }
      })
  }
}
