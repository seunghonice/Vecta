import SwiftUI
import VectaEngine

enum InspectorLayout {
  static let sectionSpacing: CGFloat = 14
  static let fieldWidth: CGFloat = 64
  static let padding: CGFloat = 10
}

/// 우측 인스펙터 (스펙 §8) — 면/선/불투명도/변환 수치. 패스파인더·정렬은 M5.
struct InspectorView: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    ScrollView {
      if store.selection.isEmpty {
        Text("선택된 객체 없음")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.top, 24)
      } else {
        VStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
          if let style = store.selectionPathStyle {
            FillSection(store: store, style: style)
            Divider()
            StrokeSection(store: store, style: style)
            Divider()
            OpacitySection(store: store, style: style)
            Divider()
          }
          TransformSection(store: store)
        }
        .padding(InspectorLayout.padding)
      }
    }
  }
}

/// 불투명도 — 슬라이더 드래그는 transient로 묶어 undo 1단계.
struct OpacitySection: View {
  @ObservedObject var store: DocumentStore
  let style: Style

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("불투명도").font(.headline)
      HStack {
        Slider(
          value: opacityBinding, in: 0...1,
          onEditingChanged: { editing in
            if editing {
              store.beginTransient()
            } else {
              store.commitTransient(actionName: "불투명도")
            }
          })
        Text(style.opacity.formatted(.percent.precision(.fractionLength(0))))
          .monospacedDigit()
          .frame(width: 44, alignment: .trailing)
      }
    }
  }

  private var opacityBinding: Binding<Double> {
    Binding(
      get: { style.opacity },
      set: { newValue in
        store.updateSelectionStylesTransient { style, _ in
          style.opacity = newValue
        }
      })
  }
}

/// X/Y/W/H/회전 수치 입력 — 커밋(Enter/포커스 아웃) 시 1회 적용.
struct TransformSection: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("변환").font(.headline)
      if let bounds = store.selectionBounds {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
          GridRow {
            numericField("X", value: bounds.minX) { store.moveSelection(x: $0) }
            numericField("Y", value: bounds.minY) { store.moveSelection(y: $0) }
          }
          GridRow {
            numericField("W", value: bounds.width) { store.resizeSelection(width: $0) }
            numericField("H", value: bounds.height) { store.resizeSelection(height: $0) }
          }
          GridRow {
            numericField("회전", value: currentRotationDegrees) { newAngle in
              store.rotateSelection(byDegrees: newAngle - currentRotationDegrees)
            }
          }
        }
      }
    }
  }

  /// 단일 선택이면 그 노드의 절대각, 다중이면 0 (입력값 = 추가 회전 델타).
  private var currentRotationDegrees: CGFloat {
    guard store.selection.count == 1, let id = store.selection.first,
      let node = store.document.topLevelNode(id: id)
    else { return 0 }
    return CGFloat(node.rotationDegrees)
  }

  private func numericField(
    _ label: String, value: CGFloat, commit: @escaping (CGFloat) -> Void
  ) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(minWidth: 24, alignment: .trailing)
      CommittingNumberField(value: value, onCommit: commit)
        .frame(width: InspectorLayout.fieldWidth)
    }
  }
}

/// Enter/포커스 아웃에서만 커밋하는 숫자 필드 — 키스트로크마다 apply 방지.
struct CommittingNumberField: View {
  let value: CGFloat
  let onCommit: (CGFloat) -> Void
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    TextField("", text: $text)
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.trailing)
      .focused($isFocused)
      .onSubmit(commit)
      .onChange(of: isFocused) { _, focused in
        if !focused { commit() }
      }
      .onChange(of: value, initial: true) { _, newValue in
        if !isFocused { text = format(newValue) }
      }
  }

  private func commit() {
    guard let parsed = Double(text) else {
      text = format(value)  // 파싱 실패 → 현재 값 복원
      return
    }
    onCommit(CGFloat(parsed))
  }

  private func format(_ number: CGFloat) -> String {
    let style = FloatingPointFormatStyle<Double>()
      .grouping(.never)
      .precision(.fractionLength(0...2))
    return Double(number).formatted(style)
  }
}
