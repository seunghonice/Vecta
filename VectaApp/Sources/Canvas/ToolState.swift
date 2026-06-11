// M2에서 Tool 프로토콜(스펙 7절)로 교체 예정.
// activeShape 기반 분기와 CanvasView 인라인 마우스 핸들러는 그때 삭제한다.
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
