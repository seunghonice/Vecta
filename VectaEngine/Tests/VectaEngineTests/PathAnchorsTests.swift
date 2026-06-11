import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private let rect = BezierPath.rectangle(CGRect(x: 0, y: 0, width: 100, height: 50))
private let ellipse = BezierPath.ellipse(in: CGRect(x: 0, y: 0, width: 100, height: 100))

@Test func rectangleHasFourAnchors() {
  let anchors = rect.anchors()
  #expect(anchors.count == 4)
  #expect(anchors[0].position == CGPoint(x: 0, y: 0))
  #expect(anchors[1].position == CGPoint(x: 100, y: 0))
  #expect(anchors[2].position == CGPoint(x: 100, y: 50))
  #expect(anchors[3].position == CGPoint(x: 0, y: 50))
}

@Test func ellipseDeduplicatesClosingAnchor() {
  // move(east) + 4 curves(마지막이 east로 복귀) → 시작 앵커는 마지막 세그먼트가 대표
  let anchors = ellipse.anchors()
  #expect(anchors.count == 4)
  // 대표 앵커는 마지막 곡선의 종점 (east)
  #expect(anchors.contains { $0.position == CGPoint(x: 100, y: 50) })
  // move(인덱스 0)는 목록에 없다
  #expect(!anchors.contains { $0.ref.segmentIndex == 0 })
}

@Test func movingLineAnchorMovesOnlyThatPoint() {
  let moved = rect.movingAnchor(
    AnchorRef(subpathIndex: 0, segmentIndex: 1), to: CGPoint(x: 120, y: -10))
  let anchors = moved.anchors()
  #expect(anchors[1].position == CGPoint(x: 120, y: -10))
  #expect(anchors[0].position == CGPoint(x: 0, y: 0))
  #expect(anchors[2].position == CGPoint(x: 100, y: 50))
}

@Test func movingCurveAnchorCarriesAttachedHandles() {
  // ellipse의 south 앵커(세그먼트 1) 이동 → 그 세그먼트 control2와
  // 다음 세그먼트 control1이 같은 델타로 따라온다
  let ref = AnchorRef(subpathIndex: 0, segmentIndex: 1)
  let before = ellipse.subpaths[0].segments
  guard case .curve(_, _, let beforeC2) = before[1], case .curve(_, let beforeNextC1, _) = before[2]
  else {
    Issue.record("곡선 세그먼트가 아님")
    return
  }
  let moved = ellipse.movingAnchor(ref, to: CGPoint(x: 50, y: 120))  // (50,100) → +20 y
  let after = moved.subpaths[0].segments
  guard case .curve(let afterTo, _, let afterC2) = after[1],
    case .curve(_, let afterNextC1, _) = after[2]
  else {
    Issue.record("곡선 세그먼트가 아님")
    return
  }
  #expect(afterTo == CGPoint(x: 50, y: 120))
  #expect(afterC2 == CGPoint(x: beforeC2.x, y: beforeC2.y + 20))
  #expect(afterNextC1 == CGPoint(x: beforeNextC1.x, y: beforeNextC1.y + 20))
}

@Test func movingClosingAnchorMovesStartToo() {
  // ellipse 대표 시작 앵커(마지막 세그먼트) 이동 → move(시작점)와
  // 첫 곡선(인덱스 1) control1도 함께 이동
  let lastIndex = ellipse.subpaths[0].segments.count - 1
  let ref = AnchorRef(subpathIndex: 0, segmentIndex: lastIndex)
  let moved = ellipse.movingAnchor(ref, to: CGPoint(x: 110, y: 60))  // east (100,50) → +10,+10
  guard case .move(let newStart) = moved.subpaths[0].segments[0] else {
    Issue.record("move가 아님")
    return
  }
  #expect(newStart == CGPoint(x: 110, y: 60))
  #expect(moved.subpaths[0].segments[lastIndex].endPoint == CGPoint(x: 110, y: 60))
}

@Test func movingControlChangesOnlyThatHandle() {
  let ref = ControlRef(subpathIndex: 0, segmentIndex: 1, kind: .control2)
  let moved = ellipse.movingControl(ref, to: CGPoint(x: 80, y: 130))
  guard case .curve(let to, let c1, let c2) = moved.subpaths[0].segments[1],
    case .curve(_, let beforeC1, _) = ellipse.subpaths[0].segments[1]
  else {
    Issue.record("곡선이 아님")
    return
  }
  #expect(c2 == CGPoint(x: 80, y: 130))
  #expect(c1 == beforeC1)
  #expect(to == ellipse.subpaths[0].segments[1].endPoint)
}

@Test func controlHandlesForAnchorReturnsAdjacentHandles() {
  // south 앵커(세그먼트 1): 들어오는 = segments[1].control2, 나가는 = segments[2].control1
  let handles = ellipse.controlHandles(forAnchor: AnchorRef(subpathIndex: 0, segmentIndex: 1))
  #expect(handles.count == 2)
  #expect(handles.contains { $0.ref.kind == .control2 && $0.ref.segmentIndex == 1 })
  #expect(handles.contains { $0.ref.kind == .control1 && $0.ref.segmentIndex == 2 })
}

@Test func closingAnchorHandlesWrapAround() {
  // 대표 시작 앵커(마지막 세그먼트): 들어오는 = 마지막 control2, 나가는 = segments[1].control1
  let lastIndex = ellipse.subpaths[0].segments.count - 1
  let handles = ellipse.controlHandles(
    forAnchor: AnchorRef(subpathIndex: 0, segmentIndex: lastIndex))
  #expect(handles.count == 2)
  #expect(handles.contains { $0.ref.kind == .control2 && $0.ref.segmentIndex == lastIndex })
  #expect(handles.contains { $0.ref.kind == .control1 && $0.ref.segmentIndex == 1 })
}

@Test func lineAnchorHasNoHandles() {
  #expect(rect.controlHandles(forAnchor: AnchorRef(subpathIndex: 0, segmentIndex: 1)).isEmpty)
}

@Test func transformInvertedOrNilRejectsSingular() {
  #expect(Transform2D(CGAffineTransform(scaleX: 0, y: 1)).invertedOrNil == nil)
  #expect(Transform2D.identity.invertedOrNil == .identity)
}
