import SwiftUI
import VectaEngine

/// 인스펙터 면(fill) 섹션 — 페인트 타입 전환 + 단색/그라디언트 에디터.
struct FillSection: View {
  @ObservedObject var store: DocumentStore
  let style: Style

  private enum PaintKind: String, CaseIterable, Identifiable {
    case none = "없음"
    case color = "단색"
    case linear = "선형"
    case radial = "원형"
    var id: String { rawValue }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("면").font(.headline)
      Picker("페인트", selection: kindBinding) {
        ForEach(PaintKind.allCases) { kind in
          Text(kind.rawValue).tag(kind)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      switch style.fill {
      case .color(let rgba):
        ColorPicker("색", selection: colorBinding(current: rgba))
      case .linearGradient(let gradient):
        GradientEditor(store: store, gradient: gradient, isRadial: false)
      case .radialGradient(let gradient):
        GradientEditor(store: store, gradient: gradient, isRadial: true)
      case nil:
        EmptyView()
      }
    }
  }

  private var currentKind: PaintKind {
    switch style.fill {
    case nil: return .none
    case .color: return .color
    case .linearGradient: return .linear
    case .radialGradient: return .radial
    }
  }

  private var kindBinding: Binding<PaintKind> {
    Binding(
      get: { currentKind },
      set: { newKind in
        guard newKind != currentKind else { return }
        store.updateSelectionStyles(actionName: "면 페인트 변경") { style, bounds in
          style.fill = Self.convertedFill(style.fill, to: newKind, bounds: bounds)
        }
      })
  }

  /// 페인트 타입 전환 — 기존 색(또는 첫 스톱 색)을 보존한다.
  private static func convertedFill(
    _ fill: Paint?, to kind: PaintKind, bounds: CGRect
  ) -> Paint? {
    let baseColor: RGBA
    switch fill {
    case .color(let rgba):
      baseColor = rgba
    case .linearGradient(let gradient), .radialGradient(let gradient):
      baseColor = gradient.stops.first?.color ?? .black
    case nil:
      baseColor = .black
    }
    switch kind {
    case .none: return nil
    case .color: return .color(baseColor)
    case .linear: return .linearGradient(.defaultLinear(from: baseColor, in: bounds))
    case .radial: return .radialGradient(.defaultRadial(from: baseColor, in: bounds))
    }
  }

  private func colorBinding(current: RGBA) -> Binding<Color> {
    Binding(
      get: { current.swiftUIColor },
      set: { newColor in
        let rgba = RGBA(newColor)
        store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
          style.fill = .color(rgba)
        }
      })
  }
}

/// 그라디언트 스톱·각도 에디터. 스톱은 최소 2개 유지.
struct GradientEditor: View {
  @ObservedObject var store: DocumentStore
  let gradient: VectaEngine.Gradient
  let isRadial: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !isRadial {
        angleRow
      }
      ForEach(Array(gradient.stops.enumerated()), id: \.offset) { index, stop in
        stopRow(index: index, stop: stop)
      }
      Button {
        addStop()
      } label: {
        Label("스톱 추가", systemImage: "plus")
      }
      .buttonStyle(.borderless)
    }
  }

  private var angleRow: some View {
    HStack(spacing: 4) {
      Text("각도").foregroundStyle(.secondary)
      CommittingNumberField(
        value: CGFloat(GradientGeometry.angleDegrees(of: gradient))
      ) { newAngle in
        updateGradient(actionName: "그라디언트 각도") { gradient, bounds in
          let line = GradientGeometry.line(angleDegrees: Double(newAngle), in: bounds)
          gradient.start = line.start
          gradient.end = line.end
        }
      }
      .frame(width: InspectorLayout.fieldWidth)
      Text("°").foregroundStyle(.secondary)
    }
  }

  private func stopRow(index: Int, stop: GradientStop) -> some View {
    HStack(spacing: 6) {
      ColorPicker(
        "",
        selection: Binding(
          get: { stop.color.swiftUIColor },
          set: { newColor in
            let rgba = RGBA(newColor)
            updateGradient(actionName: "스톱 색 변경") { gradient, _ in
              guard gradient.stops.indices.contains(index) else { return }
              gradient.stops[index].color = rgba
            }
          })
      )
      .labelsHidden()
      .frame(width: 36)
      Slider(
        value: Binding(
          get: { stop.location },
          set: { newLocation in
            updateGradientTransient { gradient, _ in
              guard gradient.stops.indices.contains(index) else { return }
              gradient.stops[index].location = min(max(newLocation, 0), 1)
            }
          }),
        in: 0...1,
        onEditingChanged: { editing in
          if editing {
            store.beginTransient()
          } else {
            store.commitTransient(actionName: "스톱 위치 변경")
          }
        })
      Button {
        updateGradient(actionName: "스톱 삭제") { gradient, _ in
          guard gradient.stops.count > 2, gradient.stops.indices.contains(index) else { return }
          gradient.stops.remove(at: index)
        }
      } label: {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .disabled(gradient.stops.count <= 2)
    }
  }

  private func addStop() {
    updateGradient(actionName: "스톱 추가") { gradient, _ in
      let color = gradient.stops.last?.color ?? .black
      gradient.stops.append(GradientStop(location: 0.5, color: color))
      gradient.stops.sort { $0.location < $1.location }
    }
  }

  /// 현재 fill의 그라디언트(선형/원형 불문)를 제자리 변경한다.
  private func updateGradient(
    actionName: String,
    _ change: @escaping (inout VectaEngine.Gradient, CGRect) -> Void
  ) {
    store.updateSelectionStyles(actionName: actionName) { style, bounds in
      Self.mutateGradient(in: &style, bounds: bounds, change)
    }
  }

  private func updateGradientTransient(
    _ change: @escaping (inout VectaEngine.Gradient, CGRect) -> Void
  ) {
    store.updateSelectionStylesTransient { style, bounds in
      Self.mutateGradient(in: &style, bounds: bounds, change)
    }
  }

  private static func mutateGradient(
    in style: inout Style, bounds: CGRect,
    _ change: (inout VectaEngine.Gradient, CGRect) -> Void
  ) {
    switch style.fill {
    case .linearGradient(var gradient):
      change(&gradient, bounds)
      style.fill = .linearGradient(gradient)
    case .radialGradient(var gradient):
      change(&gradient, bounds)
      style.fill = .radialGradient(gradient)
    default:
      break
    }
  }
}
