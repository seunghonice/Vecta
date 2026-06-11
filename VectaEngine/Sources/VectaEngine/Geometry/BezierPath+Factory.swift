import CoreGraphics

extension BezierPath {
  /// 원호 1/4을 3차 베지어로 근사할 때의 컨트롤 포인트 비율.
  private static let circleApproximationKappa = 0.5522847498307936

  public static func rectangle(_ rect: CGRect) -> BezierPath {
    let segments: [PathSegment] = [
      .move(to: CGPoint(x: rect.minX, y: rect.minY)),
      .line(to: CGPoint(x: rect.maxX, y: rect.minY)),
      .line(to: CGPoint(x: rect.maxX, y: rect.maxY)),
      .line(to: CGPoint(x: rect.minX, y: rect.maxY)),
    ]
    return BezierPath(subpaths: [Subpath(segments: segments, isClosed: true)])
  }

  public static func ellipse(in rect: CGRect) -> BezierPath {
    let offsetX = rect.width / 2 * circleApproximationKappa
    let offsetY = rect.height / 2 * circleApproximationKappa
    let east = CGPoint(x: rect.maxX, y: rect.midY)
    let south = CGPoint(x: rect.midX, y: rect.maxY)
    let west = CGPoint(x: rect.minX, y: rect.midY)
    let north = CGPoint(x: rect.midX, y: rect.minY)
    let segments: [PathSegment] = [
      .move(to: east),
      .curve(
        to: south,
        control1: CGPoint(x: rect.maxX, y: rect.midY + offsetY),
        control2: CGPoint(x: rect.midX + offsetX, y: rect.maxY)),
      .curve(
        to: west,
        control1: CGPoint(x: rect.midX - offsetX, y: rect.maxY),
        control2: CGPoint(x: rect.minX, y: rect.midY + offsetY)),
      .curve(
        to: north,
        control1: CGPoint(x: rect.minX, y: rect.midY - offsetY),
        control2: CGPoint(x: rect.midX - offsetX, y: rect.minY)),
      .curve(
        to: east,
        control1: CGPoint(x: rect.midX + offsetX, y: rect.minY),
        control2: CGPoint(x: rect.maxX, y: rect.midY - offsetY)),
    ]
    return BezierPath(subpaths: [Subpath(segments: segments, isClosed: true)])
  }
}
