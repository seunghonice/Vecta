import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@Test func pathBoundsMatchesRect() {
  let path = BezierPath.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50))
  #expect(path.bounds == CGRect(x: 10, y: 20, width: 100, height: 50))
}

@Test func pathNodeBoundsAppliesTransform() {
  let node = Node.path(
    PathNode(
      path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
      style: Style(),
      transform: Transform2D(CGAffineTransform(translationX: 30, y: 40))))
  #expect(node.bounds == CGRect(x: 30, y: 40, width: 10, height: 10))
}

@Test func rotatedNodeBoundsIsTight() {
  // 10×10 정사각형을 중심 (5,5) 기준 45° 회전 → 대각선 길이 ≈ 14.142의 AABB
  let rotation = CGAffineTransform(translationX: 5, y: 5)
    .rotated(by: .pi / 4).translatedBy(x: -5, y: -5)
  let node = Node.path(
    PathNode(
      path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
      style: Style(),
      transform: Transform2D(rotation)))
  let bounds = node.bounds
  #expect(abs(bounds.width - 14.142) < 0.01)
  #expect(abs(bounds.midX - 5) < 0.001)
  #expect(abs(bounds.midY - 5) < 0.001)
}

@Test func groupBoundsUnionsChildrenAndAppliesTransform() {
  let childA = Node.path(
    PathNode(path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: Style()))
  let childB = Node.path(
    PathNode(path: .rectangle(CGRect(x: 20, y: 20, width: 10, height: 10)), style: Style()))
  let group = Node.group(
    GroupNode(
      children: [childA, childB],
      transform: Transform2D(CGAffineTransform(translationX: 100, y: 0))))
  #expect(group.bounds == CGRect(x: 100, y: 0, width: 30, height: 30))
}

@Test func imageNodeBoundsUsesFrame() {
  let node = Node.image(
    ImageNode(imageData: Data(), frame: CGRect(x: 5, y: 6, width: 7, height: 8)))
  #expect(node.bounds == CGRect(x: 5, y: 6, width: 7, height: 8))
}
