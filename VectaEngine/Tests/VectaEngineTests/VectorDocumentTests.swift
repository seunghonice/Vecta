import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func sampleDocument() -> VectorDocument {
  let rect = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 30)),
    style: .defaultShape)
  let group = GroupNode(children: [
    .path(
      PathNode(
        path: .ellipse(in: CGRect(x: 0, y: 0, width: 20, height: 20)),
        style: Style(fill: .color(.black))))
  ])
  let layer = Layer(name: "레이어 1", nodes: [.path(rect), .group(group)])
  return VectorDocument(
    artboard: Artboard(size: CGSize(width: 400, height: 300)),
    layers: [layer])
}

@Test func documentCodableRoundTripPreservesNestedTree() throws {
  let original = sampleDocument()
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(VectorDocument.self, from: data)
  #expect(decoded == original)
}

@Test func nodeExposesUnifiedID() {
  let pathNode = PathNode(
    path: .rectangle(.zero), style: Style())
  #expect(Node.path(pathNode).id == pathNode.id)
}

@Test func emptyDocumentHasOneVisibleUnlockedLayer() {
  let document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  #expect(document.layers.count == 1)
  #expect(document.layers[0].isVisible)
  #expect(!document.layers[0].isLocked)
  #expect(document.layers[0].nodes.isEmpty)
  #expect(document.artboard.size == CGSize(width: 100, height: 100))
}

@Test func emptyDocumentDefaultSizeIsA4() {
  let document = VectorDocument.empty()
  #expect(document.artboard.size == CGSize(width: 595, height: 842))
}

@Test func pathNodeLookupAccumulatesWorldTransform() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(translationX: 10, y: 0)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 5)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  let found = document.pathNode(id: inner.id)
  #expect(found?.node.id == inner.id)
  // 월드 변환 = 노드 × 그룹: 로컬 (0,0) → (110, 5)
  let world = CGPoint.zero.applying(found!.worldTransform)
  #expect(world == CGPoint(x: 110, y: 5))
}

@Test func pathNodeLookupAccumulatesNestedGroupChain() {
  // 2단 중첩 그룹 — 재귀 누적 방향 고정: 월드 = 노드 × 내부그룹 × 외부그룹
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(translationX: 1, y: 0)))
  let innerGroup = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(scaleX: 2, y: 2)))
  let outerGroup = GroupNode(
    children: [.group(innerGroup)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(outerGroup)]
  let found = document.pathNode(id: inner.id)
  // 로컬 (0,0) → 노드 평행이동 (1,0) → 내부그룹 스케일 (2,0) → 외부그룹 평행이동 (102,0)
  let world = CGPoint.zero.applying(found!.worldTransform)
  #expect(world == CGPoint(x: 102, y: 0))
}

@Test func updatePathNodeReachesNestedPath() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(children: [.path(inner)])
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  document.updatePathNode(id: inner.id) { pathNode in
    pathNode.style.opacity = 0.5
  }
  guard case .group(let updated) = document.layers[0].nodes[0],
    case .path(let updatedInner) = updated.children[0]
  else {
    Issue.record("구조가 다름")
    return
  }
  #expect(updatedInner.style.opacity == 0.5)
}
