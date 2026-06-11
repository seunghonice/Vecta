import CoreGraphics
import Testing

@testable import VectaEngine

private let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

@Test func handlePositionsAreOnBounds() {
  #expect(SelectionHandle.topLeft.position(in: bounds) == CGPoint(x: 0, y: 0))
  #expect(SelectionHandle.topCenter.position(in: bounds) == CGPoint(x: 50, y: 0))
  #expect(SelectionHandle.bottomRight.position(in: bounds) == CGPoint(x: 100, y: 100))
  #expect(SelectionHandle.middleLeft.position(in: bounds) == CGPoint(x: 0, y: 50))
}

@Test func anchorIsOppositeHandle() {
  #expect(SelectionHandle.bottomRight.anchor(in: bounds) == CGPoint(x: 0, y: 0))
  #expect(SelectionHandle.topCenter.anchor(in: bounds) == CGPoint(x: 50, y: 100))
}

@Test func cornerHandlesScaleBothAxes() {
  #expect(SelectionHandle.topLeft.scalesX && SelectionHandle.topLeft.scalesY)
  #expect(!SelectionHandle.topCenter.scalesX && SelectionHandle.topCenter.scalesY)
  #expect(SelectionHandle.middleRight.scalesX && !SelectionHandle.middleRight.scalesY)
}

@Test func hitHandleFindsNearbyHandle() {
  #expect(
    SelectionHandle.hitHandle(at: CGPoint(x: 98, y: 102), bounds: bounds, tolerance: 5)
      == .bottomRight)
  #expect(
    SelectionHandle.hitHandle(at: CGPoint(x: 50, y: 50), bounds: bounds, tolerance: 5) == nil)
}

@Test func rotationZoneIsOutsideCorners() {
  // 코너 (100,0)에서 바깥 대각선 방향 ~10pt — 회전 존
  #expect(
    SelectionHandle.isInRotationZone(
      CGPoint(x: 108, y: -8), bounds: bounds, tolerance: 5))
  // 핸들 바로 위(거리 ≤ tolerance)는 회전 존이 아님 (핸들 우선)
  #expect(
    !SelectionHandle.isInRotationZone(
      CGPoint(x: 101, y: 1), bounds: bounds, tolerance: 5))
  // 바운드 내부는 회전 존이 아님
  #expect(
    !SelectionHandle.isInRotationZone(
      CGPoint(x: 90, y: 10), bounds: bounds, tolerance: 5))
}
