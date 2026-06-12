import CoreGraphics
import Testing

@testable import VectaEngine

private func rect(at origin: CGPoint) -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(origin: origin, size: CGSize(width: 50, height: 50))),
      style: Style(fill: .color(.black))))
}

private func makeDocument(nodes: [Node]) -> VectorDocument {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return document
}

// MARK: - 그룹

@Test func groupReplacesFrontmostAndPreservesZOrder() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let c = rect(at: CGPoint(x: 120, y: 0))
  var document = makeDocument(nodes: [a, b, c])
  let groupID = document.groupTopLevelNodes(ids: [a.id, c.id])
  #expect(groupID != nil)
  let nodes = document.layers[0].nodes
  #expect(nodes.count == 2)
  #expect(nodes[0].id == b.id)
  guard case .group(let group) = nodes[1] else {
    Issue.record("그룹이 아님")
    return
  }
  #expect(group.id == groupID)
  #expect(group.children.map(\.id) == [a.id, c.id])  // 문서 z-순서 유지
}

@Test func groupAcrossLayersGathersIntoFrontmostLayer() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  var document = makeDocument(nodes: [a])
  document.layers.append(Layer(name: "레이어 2", nodes: [b]))
  document.groupTopLevelNodes(ids: [a.id, b.id])
  #expect(document.layers[0].nodes.isEmpty)
  #expect(document.layers[1].nodes.count == 1)
  guard case .group(let group) = document.layers[1].nodes[0] else {
    Issue.record("그룹이 아님")
    return
  }
  #expect(group.children.map(\.id) == [a.id, b.id])
}

@Test func groupSingleNodeWrapsIt() {
  let a = rect(at: .zero)
  var document = makeDocument(nodes: [a])
  let groupID = document.groupTopLevelNodes(ids: [a.id])
  guard case .group(let group)? = document.topLevelNode(id: groupID!) else {
    Issue.record("그룹이 아님")
    return
  }
  #expect(group.children.map(\.id) == [a.id])
}

@Test func groupEmptySelectionReturnsNil() {
  var document = makeDocument(nodes: [rect(at: .zero)])
  #expect(document.groupTopLevelNodes(ids: []) == nil)
  #expect(document.layers[0].nodes.count == 1)
}

// MARK: - 그룹 해제

@Test func ungroupReleasesChildrenWithComposedTransformInPlace() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 200, y: 0))
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = makeDocument(nodes: [a, .group(group), b])
  let released = document.ungroupTopLevelNodes(ids: [group.id])
  #expect(released == [inner.id])
  let nodes = document.layers[0].nodes
  // 그룹 자리(z-위치)에 자식이 풀린다
  #expect(nodes.map(\.id) == [a.id, inner.id, b.id])
  // 그룹 변환이 자식에 합성된다: bounds (0,0,50,50) → (100,0,50,50)
  #expect(nodes[1].bounds == CGRect(x: 100, y: 0, width: 50, height: 50))
}

@Test func ungroupLeavesNonGroupNodesUntouched() {
  let a = rect(at: .zero)
  var document = makeDocument(nodes: [a])
  let released = document.ungroupTopLevelNodes(ids: [a.id])
  #expect(released.isEmpty)
  #expect(document.layers[0].nodes.map(\.id) == [a.id])
}

@Test func ungroupDropsClipPath() {
  // 해제 시 클립은 폐기한다 (Illustrator 클리핑 마스크 해제 의미 — 결정 기록 참조)
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    clipPath: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
  var document = makeDocument(nodes: [.group(group)])
  document.ungroupTopLevelNodes(ids: [group.id])
  // 자식만 남고 클립은 어디에도 남지 않는다
  #expect(document.layers[0].nodes.map(\.id) == [inner.id])
}

// MARK: - 앞뒤 순서

@Test func bringForwardSwapsWithNodeAbove() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let c = rect(at: CGPoint(x: 120, y: 0))
  var document = makeDocument(nodes: [a, b, c])
  document.bringForwardTopLevelNodes(ids: [a.id])
  #expect(document.layers[0].nodes.map(\.id) == [b.id, a.id, c.id])
}

@Test func bringForwardAtTopIsNoOp() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  var document = makeDocument(nodes: [a, b])
  document.bringForwardTopLevelNodes(ids: [b.id])
  #expect(document.layers[0].nodes.map(\.id) == [a.id, b.id])
}

@Test func bringForwardKeepsAdjacentSelectionBlock() {
  // 맨 위가 선택에 포함되면 인접 선택 묶음 전체가 막힌다
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let c = rect(at: CGPoint(x: 120, y: 0))
  var document = makeDocument(nodes: [a, b, c])
  document.bringForwardTopLevelNodes(ids: [b.id, c.id])
  #expect(document.layers[0].nodes.map(\.id) == [a.id, b.id, c.id])
}

@Test func sendBackwardSwapsWithNodeBelow() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let c = rect(at: CGPoint(x: 120, y: 0))
  var document = makeDocument(nodes: [a, b, c])
  document.sendBackwardTopLevelNodes(ids: [b.id])
  #expect(document.layers[0].nodes.map(\.id) == [b.id, a.id, c.id])
}

@Test func sendBackwardAtBottomIsNoOp() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  var document = makeDocument(nodes: [a, b])
  document.sendBackwardTopLevelNodes(ids: [a.id])
  #expect(document.layers[0].nodes.map(\.id) == [a.id, b.id])
}
