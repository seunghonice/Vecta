import AppKit
import SwiftUI
import VectaEngine

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

  /// 현재 fontName이 목록에 없으면 첫 번째 패밀리로 폴백.
  private var currentFamily: String {
    let name = textNode.fontName
    return Self.availableFamilies.contains(name) ? name : (Self.availableFamilies.first ?? name)
  }

  var body: some View {
    Picker("폰트", selection: familyBinding) {
      ForEach(Self.availableFamilies, id: \.self) { family in
        Text(family).tag(family)
      }
    }
    .labelsHidden()
  }

  private var familyBinding: Binding<String> {
    Binding(
      get: { currentFamily },
      set: { newFamily in
        store.updateSelectedTextNodes(actionName: "폰트") { $0.fontName = newFamily }
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
      CommittingNumberField(value: CGFloat(textNode.fontSize)) { newSize in
        let clamped = max(1, newSize)
        store.updateSelectedTextNodes(actionName: "글자 크기") { $0.fontSize = Double(clamped) }
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
    ColorPicker("색", selection: colorBinding)
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
        store.updateSelectedTextNodes(actionName: "텍스트 색") { $0.fill = .color(rgba) }
      })
  }
}
