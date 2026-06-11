import SwiftUI

struct ToolbarView: View {
  @ObservedObject var toolState: ToolState

  var body: some View {
    VStack(spacing: 8) {
      ForEach(ShapeKind.allCases, id: \.self) { kind in
        Button {
          toolState.activeShape = kind
        } label: {
          Image(systemName: kind.symbolName)
            .font(.system(size: 18))
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
        .background(
          toolState.activeShape == kind
            ? Color.accentColor.opacity(0.25) : .clear,
          in: RoundedRectangle(cornerRadius: 6)
        )
        .help(kind.koreanName)
        .accessibilityLabel(kind.koreanName)
      }
      Spacer()
    }
    .padding(.top, 12)
    .frame(width: 56)
  }
}
