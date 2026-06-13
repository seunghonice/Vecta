import SwiftUI
import VectaEngine

enum InspectorLayout {
  static let sectionSpacing: CGFloat = 14
  static let fieldWidth: CGFloat = 64
  static let padding: CGFloat = 10
  /// 패스파인더·정렬 아이콘 버튼 한 변 크기.
  static let iconButtonSide: CGFloat = 28
}

/// 패스파인더·정렬 섹션 공용 아이콘 버튼 (bordered + 툴팁 + 접근성 레이블).
private func inspectorIconButton(
  _ label: String, systemName: String, action: @escaping () -> Void
) -> some View {
  Button(action: action) {
    Image(systemName: systemName)
      .frame(width: InspectorLayout.iconButtonSide, height: InspectorLayout.iconButtonSide)
  }
  .buttonStyle(.bordered)
  .help(label)
  .accessibilityLabel(label)
}

/// 우측 인스펙터 (스펙 §8) — 면/선/불투명도/변환 수치 + 패스파인더·정렬.
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
          if let textNode = store.selectionTextNode {
            TextSection(store: store, textNode: textNode)
            Divider()
          }
          if let style = store.selectionPathStyle {
            FillSection(store: store, style: style)
            Divider()
            StrokeSection(store: store, style: style)
            Divider()
            OpacitySection(store: store, style: style)
            Divider()
          }
          TransformSection(store: store)
          Divider()
          PathfinderSection(store: store)
          Divider()
          AlignSection(store: store)
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

/// 패스파인더 4종 — 선택된 패스 2개 이상에서 활성화 (스펙 §8).
struct PathfinderSection: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("패스파인더").font(.headline)
      HStack(spacing: 6) {
        inspectorIconButton("합치기", systemName: "plus.square.on.square") {
          store.applyPathfinder(.unite)
        }
        inspectorIconButton("빼기", systemName: "minus.square") {
          store.applyPathfinder(.subtract)
        }
        inspectorIconButton("교차", systemName: "square.on.square.intersection.dashed") {
          store.applyPathfinder(.intersect)
        }
        inspectorIconButton(
          "제외", systemName: "square.on.square.squareshape.controlhandles"
        ) {
          store.applyPathfinder(.exclude)
        }
      }
      .disabled(store.combinablePathCount < 2)
    }
  }
}

/// 정렬 6종 — 선택된 노드 2개 이상에서 활성화 (스펙 §8).
struct AlignSection: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("정렬").font(.headline)
      // 제목은 항상 활성, 버튼 행만 비활성화한다.
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          inspectorIconButton("왼쪽 정렬", systemName: "align.horizontal.left") {
            store.alignSelection(edge: .left)
          }
          inspectorIconButton("가로 가운데 정렬", systemName: "align.horizontal.center") {
            store.alignSelection(edge: .centerHorizontal)
          }
          inspectorIconButton("오른쪽 정렬", systemName: "align.horizontal.right") {
            store.alignSelection(edge: .right)
          }
        }
        HStack(spacing: 6) {
          inspectorIconButton("위 정렬", systemName: "align.vertical.top") {
            store.alignSelection(edge: .top)
          }
          inspectorIconButton("세로 가운데 정렬", systemName: "align.vertical.center") {
            store.alignSelection(edge: .centerVertical)
          }
          inspectorIconButton("아래 정렬", systemName: "align.vertical.bottom") {
            store.alignSelection(edge: .bottom)
          }
        }
      }
      .disabled(store.selection.count < 2)
    }
  }
}
