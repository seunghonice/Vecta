import CoreGraphics

extension BezierPath {
  /// 곡선을 포함한 타이트 바운딩 박스 (컨트롤 포인트 박스가 아님).
  public var bounds: CGRect {
    let box = cgPath.boundingBoxOfPath
    return box.isNull ? .zero : box
  }
}

extension Node {
  /// 부모 좌표계 기준 바운드 (자기 transform 적용 후). 선택 UI·마퀴 판정용.
  public var bounds: CGRect {
    switch self {
    case .path(let pathNode):
      var transform = pathNode.transform.cgAffineTransform
      let transformed = pathNode.path.cgPath.copy(using: &transform) ?? pathNode.path.cgPath
      let box = transformed.boundingBoxOfPath
      return box.isNull ? .zero : box
    case .group(let group):
      let union = group.children.reduce(CGRect.null) { $0.union($1.bounds) }
      let inner = group.clipPath.map { union.intersection($0.bounds) } ?? union
      guard !inner.isNull else { return .zero }
      return inner.applying(group.transform.cgAffineTransform)
    case .text(let text):
      // 정밀 텍스트 바운드는 M5에서. 현재는 위치 점.
      return CGRect(origin: text.position, size: .zero)
        .applying(text.transform.cgAffineTransform)
    case .image(let image):
      return image.frame.applying(image.transform.cgAffineTransform)
    }
  }
}
