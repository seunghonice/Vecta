import CoreGraphics
import Testing

@testable import VectaEngine

private func squareNode() -> Node {
  .path(
    PathNode(path: .rectangle(CGRect(x: 10, y: 10, width: 20, height: 20)), style: Style()))
}

@Test func translatedMovesBounds() {
  let moved = NodeTransformer.translated(squareNode(), by: CGVector(dx: 5, dy: -3))
  #expect(moved.bounds == CGRect(x: 15, y: 7, width: 20, height: 20))
}

@Test func translatedPreservesNodeID() {
  let node = squareNode()
  #expect(NodeTransformer.translated(node, by: CGVector(dx: 1, dy: 1)).id == node.id)
}

@Test func resizedScalesAroundAnchor() {
  // anchor = 좌상단 (10,10), 2배 확대 → (10,10) 고정, 40×40
  let resized = NodeTransformer.resized(
    squareNode(), anchor: CGPoint(x: 10, y: 10), scaleX: 2, scaleY: 2)
  #expect(resized.bounds == CGRect(x: 10, y: 10, width: 40, height: 40))
}

@Test func resizedNegativeScaleMirrors() {
  // anchor = 우하단 (30,30), scaleX -1 → x로 미러: (30,10)~(50,30)
  let resized = NodeTransformer.resized(
    squareNode(), anchor: CGPoint(x: 30, y: 30), scaleX: -1, scaleY: 1)
  #expect(resized.bounds == CGRect(x: 30, y: 10, width: 20, height: 20))
}

@Test func rotatedKeepsCenter() {
  let rotated = NodeTransformer.rotated(
    squareNode(), around: CGPoint(x: 20, y: 20), by: .pi / 2)
  #expect(abs(rotated.bounds.midX - 20) < 0.001)
  #expect(abs(rotated.bounds.midY - 20) < 0.001)
  #expect(abs(rotated.bounds.width - 20) < 0.001)
}

@Test func transformsComposeOnExistingTransform() {
  // 이미 이동된 노드를 다시 이동하면 합성된다
  let once = NodeTransformer.translated(squareNode(), by: CGVector(dx: 10, dy: 0))
  let twice = NodeTransformer.translated(once, by: CGVector(dx: 10, dy: 0))
  #expect(twice.bounds == CGRect(x: 30, y: 10, width: 20, height: 20))
}
