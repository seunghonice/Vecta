import CoreGraphics

/// 캔버스 마우스 이벤트의 플랫폼 독립 표현. point는 모델 좌표.
public struct CanvasEvent: Equatable, Sendable {
  public var point: CGPoint
  public var isShiftPressed: Bool
  public var clickCount: Int
  /// 줌 반영 히트 허용 오차 (뷰 ~4pt ÷ magnification, 모델 좌표 단위).
  public var hitTolerance: CGFloat

  public init(
    point: CGPoint, isShiftPressed: Bool = false,
    clickCount: Int = 1, hitTolerance: CGFloat = 4
  ) {
    self.point = point
    self.isShiftPressed = isShiftPressed
    self.clickCount = clickCount
    self.hitTolerance = hitTolerance
  }
}

public enum CanvasKey: Equatable, Sendable {
  case delete
  case escape
  case enter
}

/// 앱 레이어가 NSCursor로 매핑한다 (엔진은 AppKit 비의존 — 스펙 §7).
public enum CursorKind: Equatable, Sendable {
  case arrow
  case crosshair
}

public enum ToolKind: String, CaseIterable, Equatable, Sendable {
  case select
  case rectangle
  case ellipse
}
