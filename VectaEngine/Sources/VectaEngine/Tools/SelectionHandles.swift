import CoreGraphics

/// 선택 바운드의 8개 리사이즈 핸들 (순수 함수 — 도구·오버레이가 공유).
public enum SelectionHandle: CaseIterable, Equatable, Sendable {
  case topLeft, topCenter, topRight
  case middleLeft, middleRight
  case bottomLeft, bottomCenter, bottomRight

  public func position(in bounds: CGRect) -> CGPoint {
    switch self {
    case .topLeft: return CGPoint(x: bounds.minX, y: bounds.minY)
    case .topCenter: return CGPoint(x: bounds.midX, y: bounds.minY)
    case .topRight: return CGPoint(x: bounds.maxX, y: bounds.minY)
    case .middleLeft: return CGPoint(x: bounds.minX, y: bounds.midY)
    case .middleRight: return CGPoint(x: bounds.maxX, y: bounds.midY)
    case .bottomLeft: return CGPoint(x: bounds.minX, y: bounds.maxY)
    case .bottomCenter: return CGPoint(x: bounds.midX, y: bounds.maxY)
    case .bottomRight: return CGPoint(x: bounds.maxX, y: bounds.maxY)
    }
  }

  public var opposite: SelectionHandle {
    switch self {
    case .topLeft: return .bottomRight
    case .topCenter: return .bottomCenter
    case .topRight: return .bottomLeft
    case .middleLeft: return .middleRight
    case .middleRight: return .middleLeft
    case .bottomLeft: return .topRight
    case .bottomCenter: return .topCenter
    case .bottomRight: return .topLeft
    }
  }

  /// 리사이즈 고정점 = 반대편 핸들 위치.
  public func anchor(in bounds: CGRect) -> CGPoint {
    opposite.position(in: bounds)
  }

  public var scalesX: Bool {
    switch self {
    case .topCenter, .bottomCenter: return false
    default: return true
    }
  }

  public var scalesY: Bool {
    switch self {
    case .middleLeft, .middleRight: return false
    default: return true
    }
  }

  /// 점이 닿는 핸들 (체비쇼프 거리 ≤ tolerance).
  public static func hitHandle(
    at point: CGPoint, bounds: CGRect, tolerance: CGFloat
  ) -> SelectionHandle? {
    allCases.first { handle in
      let position = handle.position(in: bounds)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }
  }

  /// 모서리 바깥 회전 존 (스펙 §7): 코너에서 (tolerance, 3×tolerance] 거리,
  /// 바운드 외부, 핸들 미적중일 때.
  public static func isInRotationZone(
    _ point: CGPoint, bounds: CGRect, tolerance: CGFloat
  ) -> Bool {
    guard !bounds.contains(point) else { return false }
    guard hitHandle(at: point, bounds: bounds, tolerance: tolerance) == nil else { return false }
    let corners: [SelectionHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    return corners.contains { corner in
      let position = corner.position(in: bounds)
      let distance = hypot(point.x - position.x, point.y - position.y)
      return distance <= tolerance * 3
    }
  }
}
