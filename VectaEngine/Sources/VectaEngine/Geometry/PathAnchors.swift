import CoreGraphics

/// 패스 앵커 주소: subpaths[subpathIndex].segments[segmentIndex]의 종점.
public struct AnchorRef: Equatable, Sendable {
  public var subpathIndex: Int
  public var segmentIndex: Int

  public init(subpathIndex: Int, segmentIndex: Int) {
    self.subpathIndex = subpathIndex
    self.segmentIndex = segmentIndex
  }
}

public enum ControlKind: Equatable, Sendable {
  case control1  // 세그먼트 시작 앵커의 나가는 핸들
  case control2  // 세그먼트 끝 앵커의 들어오는 핸들
}

public struct ControlRef: Equatable, Sendable {
  public var subpathIndex: Int
  public var segmentIndex: Int
  public var kind: ControlKind

  public init(subpathIndex: Int, segmentIndex: Int, kind: ControlKind) {
    self.subpathIndex = subpathIndex
    self.segmentIndex = segmentIndex
    self.kind = kind
  }
}

extension PathSegment {
  /// 세그먼트 종점 (앵커 위치).
  public var endPoint: CGPoint {
    switch self {
    case .move(let point), .line(let point): return point
    case .curve(let point, _, _): return point
    }
  }
}

extension BezierPath {
  /// 편집 가능한 앵커 목록. 닫힌 서브패스에서 마지막 세그먼트 종점이
  /// 시작점(move)과 일치하면 — 명시적 닫힘 곡선 — 시작 앵커는 마지막
  /// 세그먼트가 대표하고 move는 목록에서 제외한다 (중복 앵커 방지).
  public func anchors() -> [(ref: AnchorRef, position: CGPoint)] {
    var result: [(ref: AnchorRef, position: CGPoint)] = []
    for (subpathIndex, subpath) in subpaths.enumerated() {
      for (segmentIndex, segment) in subpath.segments.enumerated() {
        if segmentIndex == 0 && subpath.lastClosesOnStart { continue }
        result.append(
          (AnchorRef(subpathIndex: subpathIndex, segmentIndex: segmentIndex), segment.endPoint))
      }
    }
    return result
  }

  public func anchorPosition(_ ref: AnchorRef) -> CGPoint? {
    guard subpaths.indices.contains(ref.subpathIndex) else { return nil }
    let segments = subpaths[ref.subpathIndex].segments
    guard segments.indices.contains(ref.segmentIndex) else { return nil }
    return segments[ref.segmentIndex].endPoint
  }

  /// 앵커 이동 — 부착 핸들(이 세그먼트 control2, 다음 세그먼트 control1)이
  /// 같은 델타로 따라온다. 닫힘 대표 앵커는 move와 첫 세그먼트 핸들도 이동.
  public func movingAnchor(_ ref: AnchorRef, to newPosition: CGPoint) -> BezierPath {
    guard let oldPosition = anchorPosition(ref) else { return self }
    let delta = CGVector(dx: newPosition.x - oldPosition.x, dy: newPosition.y - oldPosition.y)
    var copy = self
    copy.subpaths[ref.subpathIndex] =
      copy.subpaths[ref.subpathIndex].movingAnchor(at: ref.segmentIndex, by: delta)
    return copy
  }

  /// 컨트롤 핸들만 이동 (곡선 세그먼트가 아니면 무시).
  public func movingControl(_ ref: ControlRef, to newPosition: CGPoint) -> BezierPath {
    guard subpaths.indices.contains(ref.subpathIndex) else { return self }
    var copy = self
    let segments = copy.subpaths[ref.subpathIndex].segments
    guard segments.indices.contains(ref.segmentIndex),
      case .curve(let to, let control1, let control2) = segments[ref.segmentIndex]
    else { return self }
    let updated: PathSegment
    switch ref.kind {
    case .control1:
      updated = .curve(to: to, control1: newPosition, control2: control2)
    case .control2:
      updated = .curve(to: to, control1: control1, control2: newPosition)
    }
    copy.subpaths[ref.subpathIndex].segments[ref.segmentIndex] = updated
    return copy
  }

  /// 앵커에 부착된 컨트롤 핸들 (들어오는 control2, 나가는 control1 — 최대 2개).
  public func controlHandles(
    forAnchor ref: AnchorRef
  ) -> [(ref: ControlRef, position: CGPoint)] {
    guard subpaths.indices.contains(ref.subpathIndex) else { return [] }
    let subpath = subpaths[ref.subpathIndex]
    let segments = subpath.segments
    guard segments.indices.contains(ref.segmentIndex) else { return [] }
    var result: [(ref: ControlRef, position: CGPoint)] = []
    // 들어오는 핸들: 이 세그먼트의 control2
    if case .curve(_, _, let control2) = segments[ref.segmentIndex] {
      result.append(
        (
          ControlRef(
            subpathIndex: ref.subpathIndex, segmentIndex: ref.segmentIndex, kind: .control2),
          control2
        ))
    }
    // 나가는 핸들: 다음 세그먼트의 control1 (닫힘 대표 앵커는 인덱스 1로 래핑)
    var nextIndex = ref.segmentIndex + 1
    if nextIndex >= segments.count, subpath.lastClosesOnStart {
      nextIndex = 1
    }
    if segments.indices.contains(nextIndex), case .curve(_, let control1, _) = segments[nextIndex] {
      result.append(
        (
          ControlRef(subpathIndex: ref.subpathIndex, segmentIndex: nextIndex, kind: .control1),
          control1
        ))
    }
    return result
  }
}

extension Subpath {
  /// 닫힌 서브패스의 마지막 세그먼트가 시작점으로 복귀하는가 (명시적 닫힘).
  var lastClosesOnStart: Bool {
    guard isClosed, segments.count > 1, case .move(let start) = segments[0] else { return false }
    return segments[segments.count - 1].endPoint == start
  }

  func movingAnchor(at index: Int, by delta: CGVector) -> Subpath {
    var copy = self
    copy.moveEndPoint(at: index, by: delta)
    copy.moveControl1(at: index + 1, by: delta)
    if index == segments.count - 1, lastClosesOnStart, case .move(let start) = segments[0] {
      copy.segments[0] = .move(to: CGPoint(x: start.x + delta.dx, y: start.y + delta.dy))
      copy.moveControl1(at: 1, by: delta)
    }
    return copy
  }

  private mutating func moveEndPoint(at index: Int, by delta: CGVector) {
    guard segments.indices.contains(index) else { return }
    switch segments[index] {
    case .move(let to):
      segments[index] = .move(to: CGPoint(x: to.x + delta.dx, y: to.y + delta.dy))
    case .line(let to):
      segments[index] = .line(to: CGPoint(x: to.x + delta.dx, y: to.y + delta.dy))
    case .curve(let to, let control1, let control2):
      segments[index] = .curve(
        to: CGPoint(x: to.x + delta.dx, y: to.y + delta.dy),
        control1: control1,
        control2: CGPoint(x: control2.x + delta.dx, y: control2.y + delta.dy))
    }
  }

  private mutating func moveControl1(at index: Int, by delta: CGVector) {
    guard segments.indices.contains(index),
      case .curve(let to, let control1, let control2) = segments[index]
    else { return }
    segments[index] = .curve(
      to: to,
      control1: CGPoint(x: control1.x + delta.dx, y: control1.y + delta.dy),
      control2: control2)
  }
}
