import SwiftUI
import VectaEngine

/// 우측 도킹 패널 — 위 인스펙터, 아래 레이어 패널 (스펙 §8).
struct SidePanelView: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VSplitView {
      InspectorView(store: store)
        .frame(minHeight: 280)
      LayerPanelView(store: store)
        .frame(minHeight: 140)
    }
  }
}
