import CoreGraphics

/// PDF 패스 구성 연산자(m l c v y h re) → BezierPath. 좌표는 PDF 사용자
/// 공간 그대로 유지 — CTM·플립은 페인팅 시점에 적용된다 (파서 내부 타입).
struct PDFPathBuilder: Equatable {
  private var subpaths: [Subpath] = []
  private var segments: [PathSegment] = []
  private var currentPoint: CGPoint = .zero
  private var subpathStart: CGPoint = .zero

  mutating func move(to point: CGPoint) {
    flush(isClosed: false)
    currentPoint = point
    subpathStart = point
    segments = [.move(to: point)]
  }

  mutating func line(to point: CGPoint) {
    ensureOpenSubpath()
    segments.append(.line(to: point))
    currentPoint = point
  }

  mutating func curve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
    ensureOpenSubpath()
    segments.append(.curve(to: point, control1: control1, control2: control2))
    currentPoint = point
  }

  /// v 연산자 — control1 = 현재 점.
  mutating func curveV(to point: CGPoint, control2: CGPoint) {
    curve(to: point, control1: currentPoint, control2: control2)
  }

  /// y 연산자 — control2 = 종점.
  mutating func curveY(to point: CGPoint, control1: CGPoint) {
    curve(to: point, control1: control1, control2: point)
  }

  /// h 연산자 — 닫고, 이후 세그먼트는 시작점에서 새 subpath.
  mutating func close() {
    flush(isClosed: true)
    currentPoint = subpathStart
  }

  /// re 연산자 — 닫힌 사각형 subpath 추가, 현재 점 = 원점.
  mutating func rect(_ rect: CGRect) {
    flush(isClosed: false)
    segments = [
      .move(to: rect.origin),
      .line(to: CGPoint(x: rect.maxX, y: rect.minY)),
      .line(to: CGPoint(x: rect.maxX, y: rect.maxY)),
      .line(to: CGPoint(x: rect.minX, y: rect.maxY)),
    ]
    flush(isClosed: true)
    currentPoint = rect.origin
    subpathStart = rect.origin
  }

  /// 잔여 세그먼트를 포함한 전체 패스를 반환하고 리셋한다.
  mutating func finish() -> BezierPath {
    flush(isClosed: false)
    let path = BezierPath(subpaths: subpaths)
    subpaths = []
    return path
  }

  private mutating func flush(isClosed: Bool) {
    if !segments.isEmpty {
      subpaths.append(Subpath(segments: segments, isClosed: isClosed))
    }
    segments = []
  }

  private mutating func ensureOpenSubpath() {
    if segments.isEmpty {
      segments = [.move(to: currentPoint)]
      subpathStart = currentPoint
    }
  }
}
