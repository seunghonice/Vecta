import SwiftUI
import VectaEngine

/// 인스펙터 선(stroke) 섹션 — 켜기/끄기, 색, 두께, 캡, 조인.
struct StrokeSection: View {
  @ObservedObject var store: DocumentStore
  let style: Style

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("선").font(.headline)
        Spacer()
        Toggle("선 사용", isOn: enabledBinding)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.mini)
      }
      if let stroke = style.stroke {
        ColorPicker("색", selection: colorBinding(current: stroke.paint))
        HStack(spacing: 4) {
          Text("두께").foregroundStyle(.secondary)
          CommittingNumberField(value: stroke.width) { newWidth in
            guard newWidth > 0 else { return }
            update(actionName: "선 두께 변경") { $0.width = newWidth }
          }
          .frame(width: InspectorLayout.fieldWidth)
          Text("pt").foregroundStyle(.secondary)
        }
        Picker("캡", selection: capBinding(current: stroke.cap)) {
          Text("버트").tag(LineCap.butt)
          Text("라운드").tag(LineCap.round)
          Text("스퀘어").tag(LineCap.square)
        }
        .pickerStyle(.segmented)
        Picker("조인", selection: joinBinding(current: stroke.join)) {
          Text("마이터").tag(LineJoin.miter)
          Text("라운드").tag(LineJoin.round)
          Text("베벨").tag(LineJoin.bevel)
        }
        .pickerStyle(.segmented)
      }
    }
  }

  private var enabledBinding: Binding<Bool> {
    Binding(
      get: { style.stroke != nil },
      set: { enabled in
        store.updateSelectionStyles(actionName: enabled ? "선 추가" : "선 제거") { style, _ in
          style.stroke = enabled ? Stroke(paint: .black, width: 1) : nil
        }
      })
  }

  private func colorBinding(current: RGBA) -> Binding<Color> {
    Binding(
      get: { current.swiftUIColor },
      set: { newColor in
        let rgba = RGBA(newColor)
        update(actionName: "선 색 변경") { $0.paint = rgba }
      })
  }

  private func capBinding(current: LineCap) -> Binding<LineCap> {
    Binding(
      get: { current },
      set: { newCap in update(actionName: "선 캡 변경") { $0.cap = newCap } })
  }

  private func joinBinding(current: LineJoin) -> Binding<LineJoin> {
    Binding(
      get: { current },
      set: { newJoin in update(actionName: "선 조인 변경") { $0.join = newJoin } })
  }

  private func update(actionName: String, _ change: @escaping (inout Stroke) -> Void) {
    store.updateSelectionStyles(actionName: actionName) { style, _ in
      guard var stroke = style.stroke else { return }
      change(&stroke)
      style.stroke = stroke
    }
  }
}
