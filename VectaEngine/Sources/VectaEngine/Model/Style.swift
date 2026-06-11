import CoreGraphics

public struct GradientStop: Equatable, Codable, Sendable {
  public var location: Double
  public var color: RGBA

  public init(location: Double, color: RGBA) {
    self.location = location
    self.color = color
  }
}

/// start/end는 객체 로컬 좌표 (스펙 4절).
/// 선형: start → end 방향으로 색이 진행한다.
/// 원형(radial): start = 중심, end = 원주 위 한 점 (start–end 거리 = 반지름).
public struct Gradient: Equatable, Codable, Sendable {
  public var stops: [GradientStop]
  public var start: CGPoint
  public var end: CGPoint

  public init(stops: [GradientStop], start: CGPoint, end: CGPoint) {
    self.stops = stops
    self.start = start
    self.end = end
  }
}

public enum Paint: Equatable, Codable, Sendable {
  case color(RGBA)
  case linearGradient(Gradient)
  case radialGradient(Gradient)
}

public enum LineCap: String, Codable, Sendable {
  case butt, round, square
}

public enum LineJoin: String, Codable, Sendable {
  case miter, round, bevel
}

public struct Stroke: Equatable, Codable, Sendable {
  /// 선의 채색. 의도적으로 단색만 지원한다 (스펙 4절 — 선 그라디언트는 비목표).
  /// 그라디언트 선이 필요해지면 `Paint`로 전환하되 직렬화 호환을 함께 검토할 것.
  public var paint: RGBA
  public var width: CGFloat
  public var cap: LineCap
  public var join: LineJoin
  public var dash: [CGFloat]

  public init(
    paint: RGBA, width: CGFloat,
    cap: LineCap = .butt, join: LineJoin = .miter, dash: [CGFloat] = []
  ) {
    self.paint = paint
    self.width = width
    self.cap = cap
    self.join = join
    self.dash = dash
  }
}

public struct Style: Equatable, Codable, Sendable {
  public var fill: Paint?
  public var stroke: Stroke?
  public var opacity: Double

  public init(fill: Paint? = nil, stroke: Stroke? = nil, opacity: Double = 1) {
    self.fill = fill
    self.stroke = stroke
    self.opacity = opacity
  }

  /// 새 도형의 기본 스타일 (파란 면 + 검정 1pt 선).
  public static let defaultShape = Style(
    fill: .color(RGBA(red: 0.27, green: 0.51, blue: 0.96)),
    stroke: Stroke(paint: .black, width: 1))
}
