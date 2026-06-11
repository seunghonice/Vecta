import CoreGraphics

/// 그라디언트 선분 ↔ 각도 매핑 (인스펙터 각도 편집용). 각도는 도 단위,
/// 모델 y-아래 좌표계 기준 0° = 오른쪽(→), 90° = 아래(↓), 시계 방향 양수.
public enum GradientGeometry {
  /// bounds 중심을 지나고 양 끝이 bounds 경계에 내접하는 angle 방향 선분.
  public static func line(
    angleDegrees: Double, in bounds: CGRect
  ) -> (start: CGPoint, end: CGPoint) {
    let radians = angleDegrees * .pi / 180
    let direction = CGVector(dx: cos(radians), dy: sin(radians))
    // bounds를 방향 벡터에 사영한 반길이 — 끝점이 경계에 닿는다.
    let halfLength =
      (abs(direction.dx) * bounds.width + abs(direction.dy) * bounds.height) / 2
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    return (
      CGPoint(
        x: center.x - direction.dx * halfLength,
        y: center.y - direction.dy * halfLength),
      CGPoint(
        x: center.x + direction.dx * halfLength,
        y: center.y + direction.dy * halfLength)
    )
  }

  /// 그라디언트 선분의 각도 (도). 길이 0이면 0.
  public static func angleDegrees(of gradient: Gradient) -> Double {
    let dx = gradient.end.x - gradient.start.x
    let dy = gradient.end.y - gradient.start.y
    guard dx != 0 || dy != 0 else { return 0 }
    return atan2(dy, dx) * 180 / .pi
  }
}

extension Gradient {
  /// 단색에서 전환할 때의 기본 선형 그라디언트 — 기존 색 → 흰색, 0°.
  /// bounds는 객체 로컬 패스 바운드 (그라디언트 좌표는 객체 로컬 — 스펙 §4).
  public static func defaultLinear(from color: RGBA, in bounds: CGRect) -> Gradient {
    let line = GradientGeometry.line(angleDegrees: 0, in: bounds)
    return Gradient(
      stops: [
        GradientStop(location: 0, color: color),
        GradientStop(location: 1, color: .white),
      ],
      start: line.start, end: line.end)
  }

  /// 기본 원형 그라디언트 — bounds 중심에서 우하단 모서리까지.
  public static func defaultRadial(from color: RGBA, in bounds: CGRect) -> Gradient {
    Gradient(
      stops: [
        GradientStop(location: 0, color: color),
        GradientStop(location: 1, color: .white),
      ],
      start: CGPoint(x: bounds.midX, y: bounds.midY),
      end: CGPoint(x: bounds.maxX, y: bounds.maxY))
  }
}
