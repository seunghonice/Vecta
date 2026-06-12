import SwiftUI
import VectaEngine

extension RGBA {
  var swiftUIColor: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }

  /// ColorPicker 출력 → sRGB 성분. 변환 실패 시 검정 (방어적 폴백).
  init(_ color: Color) {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
    self.init(
      red: nsColor.redComponent, green: nsColor.greenComponent,
      blue: nsColor.blueComponent, alpha: nsColor.alphaComponent)
  }
}
