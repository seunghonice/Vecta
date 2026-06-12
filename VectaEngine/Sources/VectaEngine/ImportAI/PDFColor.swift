import CoreGraphics

/// PDF 색공간 상태와 성분 → RGBA 변환 (스펙 §5 — CMYK/Gray→RGB).
/// 파서 내부 타입 — 공개 API가 아니다.
enum PDFColorSpace: Equatable {
  case deviceGray
  case deviceRGB
  case deviceCMYK
  case pattern
  case unsupported(name: String)

  static func named(_ name: String) -> PDFColorSpace {
    switch name {
    case "DeviceGray", "G", "CalGray": return .deviceGray
    case "DeviceRGB", "RGB", "CalRGB": return .deviceRGB
    case "DeviceCMYK", "CMYK": return .deviceCMYK
    case "Pattern": return .pattern
    default: return .unsupported(name: name)
    }
  }

  var componentCount: Int {
    switch self {
    case .deviceGray: return 1
    case .deviceRGB: return 3
    case .deviceCMYK: return 4
    case .pattern, .unsupported: return 0
    }
  }

  /// 성분 배열 → RGBA. 성분 수 부족·비색상 공간이면 nil.
  func color(from components: [CGFloat]) -> RGBA? {
    switch self {
    case .deviceGray where components.count >= 1:
      let gray = Double(components[0])
      return RGBA(red: gray, green: gray, blue: gray)
    case .deviceRGB where components.count >= 3:
      return RGBA(
        red: Double(components[0]), green: Double(components[1]),
        blue: Double(components[2]))
    case .deviceCMYK where components.count >= 4:
      let (c, m, y, k) = (
        Double(components[0]), Double(components[1]),
        Double(components[2]), Double(components[3])
      )
      return RGBA(red: (1 - c) * (1 - k), green: (1 - m) * (1 - k), blue: (1 - y) * (1 - k))
    default:
      return nil
    }
  }
}
