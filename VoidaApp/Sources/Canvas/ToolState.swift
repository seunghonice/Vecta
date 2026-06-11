import Foundation

enum ShapeKind: String, CaseIterable {
  case rectangle
  case ellipse

  var koreanName: String {
    switch self {
    case .rectangle: return "사각형"
    case .ellipse: return "타원"
    }
  }

  var symbolName: String {
    switch self {
    case .rectangle: return "rectangle"
    case .ellipse: return "circle"
    }
  }
}

final class ToolState: ObservableObject {
  @Published var activeShape: ShapeKind = .rectangle
}
