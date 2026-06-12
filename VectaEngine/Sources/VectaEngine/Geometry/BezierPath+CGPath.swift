import CoreGraphics

extension BezierPath {
  public var cgPath: CGPath {
    let path = CGMutablePath()
    for subpath in subpaths {
      for segment in subpath.segments {
        switch segment {
        case .move(let point):
          path.move(to: point)
        case .line(let point):
          path.addLine(to: point)
        case .curve(let point, let control1, let control2):
          path.addCurve(to: point, control1: control1, control2: control2)
        }
      }
      if subpath.isClosed {
        path.closeSubpath()
      }
    }
    return path
  }

  /// CGPath → BezierPath 역변환 (클립 교차 결과 수용 등 — M4a).
  /// 2차(quad) 곡선은 3차로 승격: c1 = p0 + ⅔(q − p0), c2 = p + ⅔(q − p).
  public init(cgPath: CGPath) {
    var subpaths: [Subpath] = []
    var segments: [PathSegment] = []
    var isClosed = false
    var currentPoint = CGPoint.zero
    var subpathStart = CGPoint.zero

    func flush() {
      if !segments.isEmpty {
        subpaths.append(Subpath(segments: segments, isClosed: isClosed))
      }
      segments = []
      isClosed = false
    }
    // 닫힘 직후처럼 세그먼트가 비어 있으면 현재 점에서 새 subpath를 연다.
    func ensureOpenSubpath() {
      if segments.isEmpty {
        segments = [.move(to: currentPoint)]
        subpathStart = currentPoint
      }
    }

    cgPath.applyWithBlock { elementPointer in
      let element = elementPointer.pointee
      switch element.type {
      case .moveToPoint:
        flush()
        currentPoint = element.points[0]
        subpathStart = currentPoint
        segments = [.move(to: currentPoint)]
      case .addLineToPoint:
        ensureOpenSubpath()
        currentPoint = element.points[0]
        segments.append(.line(to: currentPoint))
      case .addQuadCurveToPoint:
        ensureOpenSubpath()
        let control = element.points[0]
        let end = element.points[1]
        let control1 = CGPoint(
          x: currentPoint.x + 2 * (control.x - currentPoint.x) / 3,
          y: currentPoint.y + 2 * (control.y - currentPoint.y) / 3)
        let control2 = CGPoint(
          x: end.x + 2 * (control.x - end.x) / 3,
          y: end.y + 2 * (control.y - end.y) / 3)
        segments.append(.curve(to: end, control1: control1, control2: control2))
        currentPoint = end
      case .addCurveToPoint:
        ensureOpenSubpath()
        let end = element.points[2]
        segments.append(
          .curve(to: end, control1: element.points[0], control2: element.points[1]))
        currentPoint = end
      case .closeSubpath:
        isClosed = true
        flush()
        currentPoint = subpathStart
      @unknown default:
        break
      }
    }
    flush()
    self.init(subpaths: subpaths)
  }

  /// 모든 점에 아핀 변환 적용 — 베지어는 제어점 변환으로 정확 (CTM 베이크용).
  public func applying(_ transform: CGAffineTransform) -> BezierPath {
    BezierPath(
      subpaths: subpaths.map { subpath in
        Subpath(
          segments: subpath.segments.map { segment in
            switch segment {
            case .move(let to):
              return .move(to: to.applying(transform))
            case .line(let to):
              return .line(to: to.applying(transform))
            case .curve(let to, let control1, let control2):
              return .curve(
                to: to.applying(transform),
                control1: control1.applying(transform),
                control2: control2.applying(transform))
            }
          }, isClosed: subpath.isClosed)
      })
  }
}
