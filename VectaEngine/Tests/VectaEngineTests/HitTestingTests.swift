import CoreGraphics
import Testing

@testable import VectaEngine

private func twoRectDocument() -> (VectorDocument, bottom: NodeID, top: NodeID) {
  let bottom = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)),
    style: Style(fill: .color(.black)))
  let top = PathNode(
    path: .rectangle(CGRect(x: 50, y: 50, width: 100, height: 100)),
    style: Style(fill: .color(.white)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(bottom), .path(top)]
  return (document, bottom.id, top.id)
}

@Test func topmostHitPrefersLaterNode() {
  let (document, _, top) = twoRectDocument()
  // 겹치는 영역 (75,75)은 위(top) 노드
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 75, y: 75), in: document, tolerance: 2) == top)
}

@Test func hitOutsideAllReturnsNil() {
  let (document, _, _) = twoRectDocument()
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 250, y: 250), in: document, tolerance: 2) == nil)
}

@Test func hiddenAndLockedLayersAreSkipped() {
  var (document, _, _) = twoRectDocument()
  document.layers[0].isLocked = true
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 75, y: 75), in: document, tolerance: 2) == nil)
  document.layers[0].isLocked = false
  document.layers[0].isVisible = false
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 75, y: 75), in: document, tolerance: 2) == nil)
}

@Test func strokeOnlyPathHitsOnOutlineNotInside() {
  let outlined = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)),
    style: Style(stroke: Stroke(paint: .black, width: 4)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(outlined)]
  // 윗변 위 → hit, 중앙(채움 없음) → miss
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 50, y: 0), in: document, tolerance: 2)
      == outlined.id)
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 50, y: 50), in: document, tolerance: 2) == nil)
}

@Test func transformedNodeHitsAtTransformedPosition() {
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(translationX: 200, y: 200)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 205, y: 205), in: document, tolerance: 2)
      == node.id)
  #expect(HitTesting.topmostNodeID(at: CGPoint(x: 5, y: 5), in: document, tolerance: 2) == nil)
}

@Test func groupHitsAsWhole() {
  let child = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(children: [.path(child)])
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  // 그룹 자식에 닿으면 그룹 id 반환 (선택 도구는 그룹 통째 선택 — 스펙 §7)
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 5, y: 5), in: document, tolerance: 2) == group.id)
}

@Test func marqueeCollectsIntersectingTopLevelNodes() {
  let (document, bottom, top) = twoRectDocument()
  let both = HitTesting.topLevelNodeIDs(
    intersecting: CGRect(x: 40, y: 40, width: 30, height: 30), in: document)
  #expect(both == [bottom, top])
  let onlyBottom = HitTesting.topLevelNodeIDs(
    intersecting: CGRect(x: 0, y: 0, width: 20, height: 20), in: document)
  #expect(onlyBottom == [bottom])
}

// --- VectorDocument+Editing ---

@Test func updateTopLevelNodesAppliesChangeToMatchingIDs() {
  var (document, bottom, top) = twoRectDocument()
  document.updateTopLevelNodes(ids: [bottom]) {
    NodeTransformer.translated($0, by: CGVector(dx: 10, dy: 0))
  }
  #expect(document.topLevelNode(id: bottom)?.bounds.minX == 10)
  #expect(document.topLevelNode(id: top)?.bounds.minX == 50)
}

@Test func removeTopLevelNodesDeletesOnlyMatching() {
  var (document, bottom, top) = twoRectDocument()
  document.removeTopLevelNodes(ids: [top])
  #expect(document.topLevelNodeIDs == [bottom])
}

@Test func singularTransformNodeIsNeverHit() {
  // scaleX 0 → 특이 행렬: 조용한 오판정 대신 미스
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(scaleX: 0, y: 1)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 0, y: 50), in: document, tolerance: 4) == nil)
}

@Test func scaledGroupCompensatesTolerance() {
  // 2배 스케일 그룹: 부모 공간 tolerance 4 → 로컬 2.
  // 자식 rect (0..10), stroke width 1 → 히트 반경 = 0.5 + 2 = 2.5 (로컬).
  // 부모 점 (26,5) → 로컬 (13,2.5): 가장자리(x=10)에서 3 > 2.5 → 미스
  let child = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
    style: Style(stroke: Stroke(paint: .black, width: 1)))
  let group = GroupNode(
    children: [.path(child)],
    transform: Transform2D(CGAffineTransform(scaleX: 2, y: 2)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 26, y: 5), in: document, tolerance: 4) == nil)
  // 가장자리 안쪽 근처(부모 (19,5) → 로컬 (9.5,2.5)): 가장자리에서 0.5 < 2.5 → hit
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 19, y: 5), in: document, tolerance: 4)
      == group.id)
}

@Test func topmostPathNodeIDDescendsIntoGroups() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  // 그룹 ID가 아니라 내부 패스 ID를 반환한다 (직접 선택의 내부 진입)
  let hit = HitTesting.topmostPathNodeID(
    at: CGPoint(x: 120, y: 20), in: document, tolerance: 4)
  #expect(hit == inner.id)
  #expect(
    HitTesting.topmostPathNodeID(at: CGPoint(x: 20, y: 20), in: document, tolerance: 4)
      == nil)
}
