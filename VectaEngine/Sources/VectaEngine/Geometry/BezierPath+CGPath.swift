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
}
