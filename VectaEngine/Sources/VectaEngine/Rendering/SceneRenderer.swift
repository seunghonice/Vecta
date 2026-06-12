import CoreGraphics
import CoreText
import Foundation

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
    case .image(let imageNode):
      render(imageNode, in: context)
    case .text(let textNode):
      render(textNode, in: context)
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
    // opacity < 1이면 fill+stroke를 한 덩어리로 합성한 뒤 노드 전체에
    // 불투명도를 적용한다 (Illustrator 의미론). setAlpha는 transparency
    // layer 합성 시점에 곱해진다.
    let needsGroupCompositing = pathNode.style.opacity < 1
    if needsGroupCompositing {
      context.setAlpha(CGFloat(pathNode.style.opacity))
      context.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    if let fill = pathNode.style.fill {
      renderFill(fill, path: pathNode.path, fillRule: pathNode.fillRule, in: context)
    }
    if let stroke = pathNode.style.stroke {
      renderStroke(stroke, path: pathNode.path, in: context)
    }
    if needsGroupCompositing {
      context.endTransparencyLayer()
    }
    context.restoreGState()
  }

  static func render(_ imageNode: ImageNode, in context: CGContext) {
    guard let cgImage = CGImageCoding.cgImage(fromData: imageNode.imageData) else { return }
    context.saveGState()
    context.concatenate(imageNode.transform.cgAffineTransform)
    context.interpolationQuality = .high
    // CGImage는 bottom-up — 모델(top-down) frame에 정립으로 그리려면 frame 내부에서 상하 플립.
    // frame 중심선 기준 상하 반전 — 임의 frame에서도 정립(임포트는 항상 unit square).
    context.translateBy(x: 0, y: imageNode.frame.maxY + imageNode.frame.minY)
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: imageNode.frame)
    context.restoreGState()
  }

  static func render(_ textNode: TextNode, in context: CGContext) {
    guard !textNode.string.isEmpty, case .color(let rgba) = textNode.fill else { return }
    context.saveGState()
    context.concatenate(textNode.transform.cgAffineTransform)
    let ctLine = TextRendering.line(
      textNode.string, fontName: textNode.fontName,
      fontSize: CGFloat(textNode.fontSize), color: rgba.cgColor)
    // 모델은 top-down(y-down). renderToBitmap이 scale(1,-1)로 컨텍스트를 플립하므로
    // SceneRenderer 호출 시점의 y는 위 방향. position으로 이동 후 로컬에서 다시 플립하면
    // CoreText가 정립(y-up 베이스라인 위로 오름)으로 그려진다.
    context.translateBy(x: textNode.position.x, y: textNode.position.y)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(ctLine, context)
    context.restoreGState()
  }

  private static func renderFill(
    _ paint: Paint, path: BezierPath, fillRule: FillRule, in context: CGContext
  ) {
    switch paint {
    case .color(let color):
      context.setFillColor(color.cgColor)
      // fillPath()/strokePath()는 current path를 소비하므로 각 함수가 독립적으로 path를 추가해야 한다.
      context.addPath(path.cgPath)
      context.fillPath(using: fillRule.cgFillRule)
    case .linearGradient(let gradient):
      renderGradientFill(gradient, isRadial: false, path: path, fillRule: fillRule, in: context)
    case .radialGradient(let gradient):
      renderGradientFill(gradient, isRadial: true, path: path, fillRule: fillRule, in: context)
    }
  }

  /// 패스를 클립한 뒤 그라디언트를 그린다. 스펙 §4 — start/end는 객체 로컬
  /// 좌표, radial은 start=중심·end=원주 위 한 점. 퇴화 케이스(스톱 1개,
  /// 길이 0 선분)는 첫 스톱 단색으로, 스톱 0개는 그리지 않는다.
  private static func renderGradientFill(
    _ gradient: Gradient, isRadial: Bool, path: BezierPath, fillRule: FillRule,
    in context: CGContext
  ) {
    guard let firstStop = gradient.stops.first else { return }
    if gradient.stops.count == 1 || gradient.start == gradient.end {
      context.setFillColor(firstStop.color.cgColor)
      context.addPath(path.cgPath)
      context.fillPath(using: fillRule.cgFillRule)
      return
    }
    guard let cgGradient = gradient.cgGradient else { return }
    context.saveGState()
    context.addPath(path.cgPath)
    context.clip(using: fillRule.cgFillRule)
    let options: CGGradientDrawingOptions = [
      .drawsBeforeStartLocation, .drawsAfterEndLocation,
    ]
    if isRadial {
      let radius = hypot(
        gradient.end.x - gradient.start.x, gradient.end.y - gradient.start.y)
      context.drawRadialGradient(
        cgGradient, startCenter: gradient.start, startRadius: 0,
        endCenter: gradient.start, endRadius: radius, options: options)
    } else {
      context.drawLinearGradient(
        cgGradient, start: gradient.start, end: gradient.end, options: options)
    }
    context.restoreGState()
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

extension FillRule {
  var cgFillRule: CGPathFillRule {
    switch self {
    case .winding: return .winding
    case .evenOdd: return .evenOdd
    }
  }
}

extension Gradient {
  /// 위치 순 정렬된 스톱으로 CGGradient를 만든다 (스톱 2개 미만이면 nil).
  fileprivate var cgGradient: CGGradient? {
    guard stops.count >= 2 else { return nil }
    let sorted = stops.sorted { $0.location < $1.location }
    return CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: sorted.map(\.color.cgColor) as CFArray,
      locations: sorted.map { CGFloat($0.location) })
  }
}
