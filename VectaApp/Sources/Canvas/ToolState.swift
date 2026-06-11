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
    case .rectangle: return "사각형"
    case .ellipse: return "타원"
    }
  }

  var symbolName: String {
    switch self {
    case .select: return "cursorarrow"
    case .rectangle: return "rectangle"
    case .ellipse: return "circle"
    }
  }
}
