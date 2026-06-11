import CoreGraphics

/// 씬그래프를 CGContext에 그린다. 캔버스(NSView)와 PDF 익스포트가 공유한다.
///
/// 계약: 호출 시점의 CTM이 모델 좌표(top-left 원점, y 아래 방향)를 매핑해야
/// 한다. flipped NSView는 그대로, PDF 컨텍스트는 플립 후 호출한다.
public enum SceneRenderer {
  public static func render(_ document: VectorDocument, in context: CGContext) {
    for layer in document.layers where layer.isVisible {
      for node in layer.nodes {
        render(node, in: context)
      }
    }
  }

  static func render(_ node: Node, in context: CGContext) {
    switch node {
    case .path(let pathNode):
      render(pathNode, in: context)
    case .group(let groupNode):
      render(groupNode, in: context)
    case .text, .image:
      // M4(임포트)·M5(도구)에서 구현 예정. M1 모델은 생성 경로가 없다.
      break
    }
  }

  static func render(_ group: GroupNode, in context: CGContext) {
    context.saveGState()
    context.concatenate(group.transform.cgAffineTransform)
    if let clipPath = group.clipPath {
      context.addPath(clipPath.cgPath)
      context.clip()
    }
    for child in group.children {
      render(child, in: context)
    }
    context.restoreGState()
  }

  static func render(_ pathNode: PathNode, in context: CGContext) {
    context.saveGState()
    context.concatenate(pathNode.transform.cgAffineTransform)
    context.setAlpha(CGFloat(pathNode.style.opacity))
    if let fill = pathNode.style.fill {
      renderFill(fill, path: pathNode.path, in: context)
    }
    if let stroke = pathNode.style.stroke {
      renderStroke(stroke, path: pathNode.path, in: context)
    }
    context.restoreGState()
  }

  private static func renderFill(_ paint: Paint, path: BezierPath, in context: CGContext) {
    switch paint {
    case .color(let color):
      context.setFillColor(color.cgColor)
      context.addPath(path.cgPath)
      context.fillPath()
    case .linearGradient, .radialGradient:
      break  // M3에서 CGShading으로 구현
    }
  }

  private static func renderStroke(_ stroke: Stroke, path: BezierPath, in context: CGContext) {
    context.setStrokeColor(stroke.paint.cgColor)
    context.setLineWidth(stroke.width)
    context.setLineCap(stroke.cap.cgLineCap)
    context.setLineJoin(stroke.join.cgLineJoin)
    context.setLineDash(phase: 0, lengths: stroke.dash)
    context.addPath(path.cgPath)
    context.strokePath()
  }
}

extension RGBA {
  var cgColor: CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
  }
}

extension LineCap {
  var cgLineCap: CGLineCap {
    switch self {
    case .butt: return .butt
    case .round: return .round
    case .square: return .square
    }
  }
}

extension LineJoin {
  var cgLineJoin: CGLineJoin {
    switch self {
    case .miter: return .miter
    case .round: return .round
    case .bevel: return .bevel
    }
  }
}
