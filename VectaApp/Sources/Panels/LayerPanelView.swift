import SwiftUI
import VectaEngine

private enum LayerPanelLayout {
  static let rowHeight: CGFloat = 26
  static let iconSize: CGFloat = 12
  static let headerPadding: CGFloat = 8
  static let activeBackgroundOpacity: CGFloat = 0.18
}

/// 레이어 패널 (스펙 §8) — 목록(위 행 = 최상위 레이어)/눈/자물쇠/이름 더블클릭
/// 편집/드래그 순서 변경/클릭으로 활성 레이어 지정. 노드 트리는 M3 비목표.
struct LayerPanelView: View {
  @ObservedObject var store: DocumentStore
  @State private var editingLayerID: NodeID?
  @State private var draftName = ""
  @FocusState private var nameFieldFocused: Bool

  /// 표시 순서: 맨 위 행 = 최상위 레이어 (모델 배열의 역순).
  private var displayedLayers: [Layer] { store.document.layers.reversed() }

  private var activeLayerID: NodeID {
    store.document.layers[store.activeLayerIndex].id
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      List {
        ForEach(displayedLayers, id: \.id) { layer in
          row(for: layer)
        }
        .onMove(perform: moveDisplayedLayers)
      }
      .listStyle(.plain)
    }
  }

  private var header: some View {
    HStack {
      Text("레이어").font(.headline)
      Spacer()
      Button {
        store.addLayer()
      } label: {
        Image(systemName: "plus")
      }
      .buttonStyle(.borderless)
      .help("레이어 추가")
      Button {
        store.removeLayer(id: activeLayerID)
      } label: {
        Image(systemName: "minus")
      }
      .buttonStyle(.borderless)
      .disabled(store.document.layers.count <= 1)
      .help("활성 레이어 삭제")
    }
    .padding(LayerPanelLayout.headerPadding)
  }

  private func row(for layer: Layer) -> some View {
    HStack(spacing: 6) {
      Button {
        store.setLayerVisibility(id: layer.id, isVisible: !layer.isVisible)
      } label: {
        Image(systemName: layer.isVisible ? "eye" : "eye.slash")
          .font(.system(size: LayerPanelLayout.iconSize))
      }
      .buttonStyle(.borderless)
      .help(layer.isVisible ? "레이어 숨김" : "레이어 표시")
      Button {
        store.setLayerLocked(id: layer.id, isLocked: !layer.isLocked)
      } label: {
        Image(systemName: layer.isLocked ? "lock" : "lock.open")
          .font(.system(size: LayerPanelLayout.iconSize))
          .foregroundStyle(layer.isLocked ? .primary : .tertiary)
      }
      .buttonStyle(.borderless)
      .help(layer.isLocked ? "잠금 해제" : "잠금")
      nameView(for: layer)
      Spacer(minLength: 0)
    }
    .frame(height: LayerPanelLayout.rowHeight)
    .contentShape(Rectangle())
    .onTapGesture { store.setActiveLayer(id: layer.id) }
    .listRowBackground(
      layer.id == activeLayerID
        ? Color.accentColor.opacity(LayerPanelLayout.activeBackgroundOpacity)
        : Color.clear)
  }

  @ViewBuilder
  private func nameView(for layer: Layer) -> some View {
    if editingLayerID == layer.id {
      TextField("이름", text: $draftName)
        .textFieldStyle(.roundedBorder)
        .focused($nameFieldFocused)
        .onSubmit { commitRename(of: layer) }
        .onExitCommand { editingLayerID = nil }
    } else {
      Text(layer.name)
        .lineLimit(1)
        .onTapGesture(count: 2) {
          draftName = layer.name
          editingLayerID = layer.id
          nameFieldFocused = true
        }
    }
  }

  private func commitRename(of layer: Layer) {
    store.renameLayer(id: layer.id, to: draftName)
    editingLayerID = nil
  }

  /// List 표시(역순) 인덱스 → 모델 배열 인덱스로 변환해 이동한다.
  private func moveDisplayedLayers(from source: IndexSet, to destination: Int) {
    guard let displayFrom = source.first else { return }
    let layers = store.document.layers
    let displayTo = destination > displayFrom ? destination - 1 : destination
    let arrayFrom = layers.count - 1 - displayFrom
    let arrayTo = layers.count - 1 - displayTo
    store.moveLayer(id: layers[arrayFrom].id, toIndex: arrayTo)
  }
}
