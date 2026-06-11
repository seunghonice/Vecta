import CoreGraphics

/// 노드 변환 순수 함수. 부모(모델) 좌표계 기준 연산을 노드 transform 뒤에
/// 합성한다: point' = point × node.transform × operation.
public enum NodeTransformer {
  public static func translated(_ node: Node, by delta: CGVector) -> Node {
    applying(CGAffineTransform(translationX: delta.dx, y: delta.dy), to: node)
  }

  /// anchor(부모 좌표)를 고정점으로 스케일.
  public static func resized(
    _ node: Node, anchor: CGPoint, scaleX: CGFloat, scaleY: CGFloat
  ) -> Node {
    let operation = CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
      .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
      .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y))
    return applying(operation, to: node)
  }

  /// center(부모 좌표) 기준 회전. 모델이 y-아래 좌표계이므로 양의 angle은
  /// 화면상 시계 방향이다.
  public static func rotated(_ node: Node, around center: CGPoint, by angle: CGFloat) -> Node {
    let operation = CGAffineTransform(translationX: -center.x, y: -center.y)
      .concatenating(CGAffineTransform(rotationAngle: angle))
      .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    return applying(operation, to: node)
  }

  private static func applying(_ operation: CGAffineTransform, to node: Node) -> Node {
    switch node {
    case .path(var pathNode):
      pathNode.transform = composed(pathNode.transform, operation)
      return .path(pathNode)
    case .group(var group):
      group.transform = composed(group.transform, operation)
      return .group(group)
    case .text(var text):
      text.transform = composed(text.transform, operation)
      return .text(text)
    case .image(var image):
      image.transform = composed(image.transform, operation)
      return .image(image)
    }
  }

  private static func composed(_ base: Transform2D, _ operation: CGAffineTransform) -> Transform2D {
    Transform2D(base.cgAffineTransform.concatenating(operation))
  }
}
