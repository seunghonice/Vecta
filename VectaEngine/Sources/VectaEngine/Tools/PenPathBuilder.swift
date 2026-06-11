import CoreGraphics

/// 펜 도구의 패스 작성 상태 머신 (순수 값 타입 — 헤드리스 테스트 대상).
/// 클릭 = 코너 앵커, 앵커 직후 드래그 = 스무스(대칭 핸들), 시작점 근처
/// 클릭 = 닫기, finishOpen = 열린 패스로 종료.
public struct PenPathBuilder: Equatable {
  public private(set) var segments: [PathSegment] = []
  private var pendingLeadingControl: CGPoint?
  private var startLeadingControl: CGPoint?

  public init() {}

  public var anchorCount: Int { segments.count }

  public var startPoint: CGPoint? {
    if case .move(let point)? = segments.first { return point }
    return nil
  }

  public var lastAnchor: CGPoint? { segments.last?.endPoint }

  /// 현재 나가는 핸들 (오버레이 표시용).
  public var pendingHandle: CGPoint? { pendingLeadingControl }

  public mutating func addAnchor(at point: CGPoint) {
    guard !segments.isEmpty else {
      segments = [.move(to: point)]
      return
    }
    if let leading = pendingLeadingControl {
      segments.append(.curve(to: point, control1: leading, control2: point))
    } else {
      segments.append(.line(to: point))
    }
    pendingLeadingControl = nil
  }

  /// 마지막 앵커에서 핸들 드래그 — 나가는 핸들 = point, 들어오는 핸들 = 미러.
  public mutating func dragHandle(to point: CGPoint) {
    guard let anchor = lastAnchor else { return }
    let mirrored = CGPoint(x: 2 * anchor.x - point.x, y: 2 * anchor.y - point.y)
    let lastIndex = segments.count - 1
    switch segments[lastIndex] {
    case .move:
      startLeadingControl = point
    case .line(let to):
      let previousAnchor = lastIndex >= 1 ? segments[lastIndex - 1].endPoint : to
      segments[lastIndex] = .curve(to: to, control1: previousAnchor, control2: mirrored)
    case .curve(let to, let control1, _):
      segments[lastIndex] = .curve(to: to, control1: control1, control2: mirrored)
    }
    pendingLeadingControl = point
  }

  public func canClose(at point: CGPoint, tolerance: CGFloat) -> Bool {
    guard anchorCount >= 2, let start = startPoint else { return false }
    return hypot(point.x - start.x, point.y - start.y) <= tolerance
  }

  /// 시작점으로 닫는다. 핸들이 전혀 없으면 isClosed의 암묵적 닫힘 변을 쓰고,
  /// 핸들이 있으면 명시적 닫힘 곡선을 추가한다 (시작 핸들 미러).
  public mutating func close() -> BezierPath? {
    guard anchorCount >= 2, let start = startPoint else { return nil }
    var closingSegments = segments
    if pendingLeadingControl != nil || startLeadingControl != nil {
      let incoming: CGPoint
      if let startLeading = startLeadingControl {
        incoming = CGPoint(x: 2 * start.x - startLeading.x, y: 2 * start.y - startLeading.y)
      } else {
        incoming = start
      }
      let outgoing = pendingLeadingControl ?? (lastAnchor ?? start)
      closingSegments.append(.curve(to: start, control1: outgoing, control2: incoming))
    }
    reset()
    return BezierPath(subpaths: [Subpath(segments: closingSegments, isClosed: true)])
  }

  /// 열린 패스로 종료. 앵커 2개 미만이면 nil (버림).
  public mutating func finishOpen() -> BezierPath? {
    defer { reset() }
    guard anchorCount >= 2 else { return nil }
    return BezierPath(subpaths: [Subpath(segments: segments, isClosed: false)])
  }

  private mutating func reset() {
    segments = []
    pendingLeadingControl = nil
    startLeadingControl = nil
  }
}
