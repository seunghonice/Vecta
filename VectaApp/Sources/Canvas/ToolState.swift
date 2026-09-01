import Foundation
import VectaEngine

// M1의 ShapeKind 기반에서 ToolKind 기반으로 교체 (M2a).
final class ToolState: ObservableObject {
  @Published var activeTool: ToolKind = .select
}

extension ToolKind {
  var koreanName: String {
    switch self {
    case .select: return "선택"
    case .directSelect: return "직접 선택"
    case .pen: return "펜"
    case .rectangle: return "사각형"
    case .ellipse: return "타원"
    case .text: return "텍스트"
    }
  }

  var symbolName: String {
    switch self {
    case .select: return "cursorarrow"
    case .directSelect: return "hand.point.up.left"
    case .pen: return "pencil.tip"
    case .rectangle: return "rectangle"
    case .ellipse: return "circle"
    case .text: return "textformat"
    }
  }
}
