import CoreGraphics

extension CGRect {
  /// 드래그 시작·끝점처럼 순서가 보장되지 않는 두 모서리에서 정규화된 rect 생성.
  public init(corner: CGPoint, oppositeCorner: CGPoint) {
    self.init(
      x: min(corner.x, oppositeCorner.x),
      y: min(corner.y, oppositeCorner.y),
      width: abs(corner.x - oppositeCorner.x),
      height: abs(corner.y - oppositeCorner.y))
  }
}
