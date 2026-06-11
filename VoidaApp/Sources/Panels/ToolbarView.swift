import SwiftUI

private enum ToolbarLayout {
  static let buttonSide: CGFloat = 36
  static let stripWidth: CGFloat = 56
  static let buttonSpacing: CGFloat = 8
  static let topPadding: CGFloat = 12
  static let iconSize: CGFloat = 18
  static let cornerRadius: CGFloat = 6
}

struct ToolbarView: View {
  @ObservedObject var toolState: ToolState

  var body: some View {
    VStack(spacing: ToolbarLayout.buttonSpacing) {
      ForEach(ShapeKind.allCases, id: \.self) { kind in
        Button {
          toolState.activeShape = kind
        } label: {
          Image(systemName: kind.symbolName)
            .font(.system(size: ToolbarLayout.iconSize))
            .frame(width: ToolbarLayout.buttonSide, height: ToolbarLayout.buttonSide)
        }
        .buttonStyle(.borderless)
        .background(
          toolState.activeShape == kind
            ? Color.accentColor.opacity(0.25) : .clear,
          in: RoundedRectangle(cornerRadius: ToolbarLayout.cornerRadius)
        )
        .help(kind.koreanName)
        .accessibilityLabel(kind.koreanName)
      }
      Spacer()
    }
    .padding(.top, ToolbarLayout.topPadding)
    .frame(width: ToolbarLayout.stripWidth)
  }
}
