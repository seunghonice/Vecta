# Vecta M2b — 직접 선택 + 펜 도구 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 직접 선택 도구(앵커포인트·컨트롤 핸들 드래그 편집)와 펜 도구(클릭=코너, 드래그=스무스, 닫기, Esc/Enter 종료)를 추가한다. (GitHub 이슈 #3, PR은 `Closes #3`)

**Architecture:** 패스 편집 기하(AnchorRef/ControlRef, movingAnchor/movingControl)와 펜 상태 머신(PenPathBuilder — 순수 struct)을 VectaEngine에 두고 헤드리스 테스트한다. 두 도구는 M2a의 CanvasTool 프로토콜 위에 올라가며, ToolKind에 `makeTool()` 팩토리를 추가해 도구 등록을 컴파일 타임에 강제한다(M2a 최종 리뷰의 강제 언래핑 지적 해소). 펜 러버밴드를 위해 CanvasTool에 mouseMoved(기본 no-op)를 추가하고 캔버스에 트래킹 영역을 단다.

**Tech Stack:** Swift 6.3 (언어 모드 v5), Swift Testing, CoreGraphics, AppKit/SwiftUI 셸, XcodeGen.

**참조:** 스펙 `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` §7, M2a 계획(컨벤션·transient 계약).

---

## 커밋 규칙 (전역 규칙 — M1/M2a와 동일)

매 커밋 전: ① `cd VectaEngine && swift build`(앱 변경 시 xcodebuild) → ② `swift test` → ③ `swift format --in-place --recursive Sources Tests`(앱은 `VectaApp/Sources`) → ④ commit. 한국어 메시지+접두사, Co-Authored-By 금지.

## 파일 구조 (M2b 추가/변경분)

```
VectaEngine/Sources/VectaEngine/
├── Geometry/
│   └── PathAnchors.swift            # AnchorRef/ControlRef, 앵커 열거·이동·핸들
├── Model/
│   └── Transform2D.swift  (수정)    # invertedOrNil (특이 행렬 방어 공용화)
└── Tools/
    ├── CanvasEvent.swift  (수정)    # ToolKind에 directSelect/pen 추가
    ├── CanvasTool.swift   (수정)    # mouseMoved 기본 구현 추가
    ├── ToolKind+Factory.swift       # makeTool() — 망라 switch (컴파일 타임 동기화)
    ├── PenPathBuilder.swift         # 펜 상태 머신 (순수 struct)
    ├── PenTool.swift
    └── DirectSelectTool.swift

VectaApp/Sources/
├── Canvas/CanvasView.swift  (수정)  # 팩토리 사용·트래킹 영역·mouseMoved·키 A/P
└── Canvas/ToolState.swift   (수정)  # 새 ToolKind 이름·심볼
```

핵심 계약 (기존 — 도구가 의존):
- transient: `beginTransient` → `updateTransient`(베이스 기준 절대 변경) → `commitTransient`/`cancelTransient`. 외부 개입 시 세션 파기, 이후 update는 조용한 no-op.
- 모델 top-left 좌표. `CanvasEvent.hitTolerance`는 줌 보정된 모델 좌표 허용 오차.
- M2b 범위 제한: 직접 선택은 **최상위 패스 노드만** 편집한다 (그룹 내부 진입은 그룹 생성이 가능해지는 M3에서 — 스펙 §7의 "직접 선택은 내부 진입"은 그때 구현). 앵커 추가/삭제도 비목표.

---

### Task 1: PathAnchors — 앵커/컨트롤 주소·열거·이동 기하

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Geometry/PathAnchors.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Model/Transform2D.swift` (invertedOrNil 추가)
- Test: `VectaEngine/Tests/VectaEngineTests/PathAnchorsTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
  guard case .curve(let afterTo, _, let afterC2) = after[1], case .curve(_, let afterNextC1, _) = after[2]
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
  let handles = ellipse.controlHandles(forAnchor: AnchorRef(subpathIndex: 0, segmentIndex: lastIndex))
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
```

- [ ] **Step 2: 실패 확인** — `cd VectaEngine && swift test` → FAIL (`cannot find 'AnchorRef'`)

- [ ] **Step 3: Transform2D 확장** — `Model/Transform2D.swift`에 추가

```swift
  /// 특이 행렬(행렬식 ≈ 0)이면 nil — `inverted()`가 원본을 반환하는 함정 방어.
  public var invertedOrNil: CGAffineTransform? {
    guard abs(a * d - b * c) > 1e-10 else { return nil }
    return cgAffineTransform.inverted()
  }
```

- [ ] **Step 4: PathAnchors 구현** — `Geometry/PathAnchors.swift`

```swift
import CoreGraphics

/// 패스 앵커 주소: subpaths[subpathIndex].segments[segmentIndex]의 종점.
public struct AnchorRef: Equatable, Sendable {
  public var subpathIndex: Int
  public var segmentIndex: Int

  public init(subpathIndex: Int, segmentIndex: Int) {
    self.subpathIndex = subpathIndex
    self.segmentIndex = segmentIndex
  }
}

public enum ControlKind: Equatable, Sendable {
  case control1  // 세그먼트 시작 앵커의 나가는 핸들
  case control2  // 세그먼트 끝 앵커의 들어오는 핸들
}

public struct ControlRef: Equatable, Sendable {
  public var subpathIndex: Int
  public var segmentIndex: Int
  public var kind: ControlKind

  public init(subpathIndex: Int, segmentIndex: Int, kind: ControlKind) {
    self.subpathIndex = subpathIndex
    self.segmentIndex = segmentIndex
    self.kind = kind
  }
}

extension PathSegment {
  /// 세그먼트 종점 (앵커 위치).
  public var endPoint: CGPoint {
    switch self {
    case .move(let point), .line(let point): return point
    case .curve(let point, _, _): return point
    }
  }
}

extension BezierPath {
  /// 편집 가능한 앵커 목록. 닫힌 서브패스에서 마지막 세그먼트 종점이
  /// 시작점(move)과 일치하면 — 명시적 닫힘 곡선 — 시작 앵커는 마지막
  /// 세그먼트가 대표하고 move는 목록에서 제외한다 (중복 앵커 방지).
  public func anchors() -> [(ref: AnchorRef, position: CGPoint)] {
    var result: [(ref: AnchorRef, position: CGPoint)] = []
    for (subpathIndex, subpath) in subpaths.enumerated() {
      for (segmentIndex, segment) in subpath.segments.enumerated() {
        if segmentIndex == 0 && subpath.lastClosesOnStart { continue }
        result.append(
          (AnchorRef(subpathIndex: subpathIndex, segmentIndex: segmentIndex), segment.endPoint))
      }
    }
    return result
  }

  public func anchorPosition(_ ref: AnchorRef) -> CGPoint? {
    guard subpaths.indices.contains(ref.subpathIndex) else { return nil }
    let segments = subpaths[ref.subpathIndex].segments
    guard segments.indices.contains(ref.segmentIndex) else { return nil }
    return segments[ref.segmentIndex].endPoint
  }

  /// 앵커 이동 — 부착 핸들(이 세그먼트 control2, 다음 세그먼트 control1)이
  /// 같은 델타로 따라온다. 닫힘 대표 앵커는 move와 첫 세그먼트 핸들도 이동.
  public func movingAnchor(_ ref: AnchorRef, to newPosition: CGPoint) -> BezierPath {
    guard let oldPosition = anchorPosition(ref) else { return self }
    let delta = CGVector(dx: newPosition.x - oldPosition.x, dy: newPosition.y - oldPosition.y)
    var copy = self
    copy.subpaths[ref.subpathIndex] =
      copy.subpaths[ref.subpathIndex].movingAnchor(at: ref.segmentIndex, by: delta)
    return copy
  }

  /// 컨트롤 핸들만 이동 (곡선 세그먼트가 아니면 무시).
  public func movingControl(_ ref: ControlRef, to newPosition: CGPoint) -> BezierPath {
    guard subpaths.indices.contains(ref.subpathIndex) else { return self }
    var copy = self
    let segments = copy.subpaths[ref.subpathIndex].segments
    guard segments.indices.contains(ref.segmentIndex),
      case .curve(let to, let control1, let control2) = segments[ref.segmentIndex]
    else { return self }
    let updated: PathSegment
    switch ref.kind {
    case .control1:
      updated = .curve(to: to, control1: newPosition, control2: control2)
    case .control2:
      updated = .curve(to: to, control1: control1, control2: newPosition)
    }
    copy.subpaths[ref.subpathIndex].segments[ref.segmentIndex] = updated
    return copy
  }

  /// 앵커에 부착된 컨트롤 핸들 (들어오는 control2, 나가는 control1 — 최대 2개).
  public func controlHandles(
    forAnchor ref: AnchorRef
  ) -> [(ref: ControlRef, position: CGPoint)] {
    guard subpaths.indices.contains(ref.subpathIndex) else { return [] }
    let subpath = subpaths[ref.subpathIndex]
    let segments = subpath.segments
    guard segments.indices.contains(ref.segmentIndex) else { return [] }
    var result: [(ref: ControlRef, position: CGPoint)] = []
    // 들어오는 핸들: 이 세그먼트의 control2
    if case .curve(_, _, let control2) = segments[ref.segmentIndex] {
      result.append(
        (ControlRef(subpathIndex: ref.subpathIndex, segmentIndex: ref.segmentIndex, kind: .control2),
         control2))
    }
    // 나가는 핸들: 다음 세그먼트의 control1 (닫힘 대표 앵커는 인덱스 1로 래핑)
    var nextIndex = ref.segmentIndex + 1
    if nextIndex >= segments.count, subpath.lastClosesOnStart {
      nextIndex = 1
    }
    if segments.indices.contains(nextIndex), case .curve(_, let control1, _) = segments[nextIndex] {
      result.append(
        (ControlRef(subpathIndex: ref.subpathIndex, segmentIndex: nextIndex, kind: .control1),
         control1))
    }
    return result
  }
}

extension Subpath {
  /// 닫힌 서브패스의 마지막 세그먼트가 시작점으로 복귀하는가 (명시적 닫힘).
  var lastClosesOnStart: Bool {
    guard isClosed, segments.count > 1, case .move(let start) = segments[0] else { return false }
    return segments[segments.count - 1].endPoint == start
  }

  func movingAnchor(at index: Int, by delta: CGVector) -> Subpath {
    var copy = self
    copy.moveEndPoint(at: index, by: delta)
    copy.moveControl1(at: index + 1, by: delta)
    if index == segments.count - 1, lastClosesOnStart, case .move(let start) = segments[0] {
      copy.segments[0] = .move(to: CGPoint(x: start.x + delta.dx, y: start.y + delta.dy))
      copy.moveControl1(at: 1, by: delta)
    }
    return copy
  }

  private mutating func moveEndPoint(at index: Int, by delta: CGVector) {
    guard segments.indices.contains(index) else { return }
    switch segments[index] {
    case .move(let to):
      segments[index] = .move(to: CGPoint(x: to.x + delta.dx, y: to.y + delta.dy))
    case .line(let to):
      segments[index] = .line(to: CGPoint(x: to.x + delta.dx, y: to.y + delta.dy))
    case .curve(let to, let control1, let control2):
      segments[index] = .curve(
        to: CGPoint(x: to.x + delta.dx, y: to.y + delta.dy),
        control1: control1,
        control2: CGPoint(x: control2.x + delta.dx, y: control2.y + delta.dy))
    }
  }

  private mutating func moveControl1(at index: Int, by delta: CGVector) {
    guard segments.indices.contains(index),
      case .curve(let to, let control1, let control2) = segments[index]
    else { return }
    segments[index] = .curve(
      to: to,
      control1: CGPoint(x: control1.x + delta.dx, y: control1.y + delta.dy),
      control2: control2)
  }
}
```

- [ ] **Step 5: 통과 확인** — `swift test` → PASS (119개)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 패스 앵커·컨트롤 핸들 편집 기하 추가"
```

---

### Task 2: PenPathBuilder — 펜 상태 머신 (순수 struct)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Tools/PenPathBuilder.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PenPathBuilderTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing
@testable import VectaEngine

@Test func cornerClicksBuildOpenPolyline() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.addAnchor(at: CGPoint(x: 50, y: 0))
  builder.addAnchor(at: CGPoint(x: 50, y: 50))
  let path = builder.finishOpen()
  #expect(path != nil)
  let segments = path!.subpaths[0].segments
  #expect(segments.count == 3)
  #expect(segments[0] == .move(to: .zero))
  #expect(segments[1] == .line(to: CGPoint(x: 50, y: 0)))
  #expect(segments[2] == .line(to: CGPoint(x: 50, y: 50)))
  #expect(!path!.subpaths[0].isClosed)
}

@Test func singleAnchorFinishDiscards() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: .zero)
  #expect(builder.finishOpen() == nil)
  #expect(builder.anchorCount == 0)  // finish 후 리셋
}

@Test func dragAfterAnchorCreatesSmoothSegments() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.dragHandle(to: CGPoint(x: 20, y: 0))  // 시작 앵커 나가는 핸들
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  let path = builder.finishOpen()!
  guard case .curve(let to, let control1, let control2) = path.subpaths[0].segments[1] else {
    Issue.record("곡선이 아님")
    return
  }
  #expect(to == CGPoint(x: 100, y: 0))
  #expect(control1 == CGPoint(x: 20, y: 0))  // pendingLeading 소비
  #expect(control2 == CGPoint(x: 100, y: 0))  // 아직 안 드래그된 끝 — 퇴화
}

@Test func dragOnLaterAnchorConvertsIncomingLineToCurve() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.addAnchor(at: CGPoint(x: 100, y: 0))  // line
  builder.dragHandle(to: CGPoint(x: 120, y: 20))  // 미러 = (80, -20)
  let path = builder.finishOpen()!
  guard case .curve(let to, let control1, let control2) = path.subpaths[0].segments[1] else {
    Issue.record("곡선 전환 안 됨")
    return
  }
  #expect(to == CGPoint(x: 100, y: 0))
  #expect(control1 == CGPoint(x: 0, y: 0))  // 이전 앵커 쪽 퇴화 핸들
  #expect(control2 == CGPoint(x: 80, y: -20))  // 미러
}

@Test func canCloseRequiresTwoAnchorsAndProximity() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  #expect(!builder.canClose(at: CGPoint(x: 1, y: 1), tolerance: 6))
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  #expect(builder.canClose(at: CGPoint(x: 3, y: 4), tolerance: 6))  // 거리 5 ≤ 6
  #expect(!builder.canClose(at: CGPoint(x: 30, y: 0), tolerance: 6))
}

@Test func closeAllLinesUsesImplicitClosingEdge() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  builder.addAnchor(at: CGPoint(x: 50, y: 80))
  let path = builder.close()!
  let subpath = path.subpaths[0]
  #expect(subpath.isClosed)
  #expect(subpath.segments.count == 3)  // 명시적 닫힘 세그먼트 없음
}

@Test func closeWithHandlesAppendsClosingCurveWithMirroredStart() {
  var builder = PenPathBuilder()
  builder.addAnchor(at: CGPoint(x: 0, y: 0))
  builder.dragHandle(to: CGPoint(x: 10, y: -10))  // 시작 나가는 핸들 → 미러 (−10, 10)
  builder.addAnchor(at: CGPoint(x: 100, y: 0))
  builder.dragHandle(to: CGPoint(x: 120, y: 10))
  let path = builder.close()!
  let subpath = path.subpaths[0]
  #expect(subpath.isClosed)
  guard case .curve(let to, let control1, let control2) = subpath.segments.last! else {
    Issue.record("닫힘 곡선이 아님")
    return
  }
  #expect(to == CGPoint(x: 0, y: 0))
  #expect(control1 == CGPoint(x: 120, y: 10))  // 마지막 나가는 핸들
  #expect(control2 == CGPoint(x: -10, y: 10))  // 시작 핸들 미러
  // 닫힘 패스는 디코드 불변식(.move 시작)도 유지
  #expect(subpath.segments.first == .move(to: .zero))
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`cannot find 'PenPathBuilder'`)

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Tools/PenPathBuilder.swift`

```swift
import CoreGraphics

/// 펜 도구의 패스 작성 상태 머신 (순수 값 타입 — 헤드리스 테스트 대상).
/// 클릭 = 코너 앵커, 앵커 직후 드래그 = 스무스(대칭 핸들), 시작점 근처
/// 클릭 = 닫기, finishOpen = 열린 패스로 종료.
public struct PenPathBuilder: Equatable {
  public private(set) var segments: [PathSegment] = []
  private var pendingLeadingControl: CGPoint?
  private var startLeadingControl: CGPoint?

  public init() {}

  public var anchorCount: Int { segments.count }

  public var startPoint: CGPoint? {
    if case .move(let point)? = segments.first { return point }
    return nil
  }

  public var lastAnchor: CGPoint? { segments.last?.endPoint }

  /// 현재 나가는 핸들 (오버레이 표시용).
  public var pendingHandle: CGPoint? { pendingLeadingControl }

  public mutating func addAnchor(at point: CGPoint) {
    guard !segments.isEmpty else {
      segments = [.move(to: point)]
      return
    }
    if let leading = pendingLeadingControl {
      segments.append(.curve(to: point, control1: leading, control2: point))
    } else {
      segments.append(.line(to: point))
    }
    pendingLeadingControl = nil
  }

  /// 마지막 앵커에서 핸들 드래그 — 나가는 핸들 = point, 들어오는 핸들 = 미러.
  public mutating func dragHandle(to point: CGPoint) {
    guard let anchor = lastAnchor else { return }
    let mirrored = CGPoint(x: 2 * anchor.x - point.x, y: 2 * anchor.y - point.y)
    let lastIndex = segments.count - 1
    switch segments[lastIndex] {
    case .move:
      startLeadingControl = point
    case .line(let to):
      let previousAnchor = lastIndex >= 1 ? segments[lastIndex - 1].endPoint : to
      segments[lastIndex] = .curve(to: to, control1: previousAnchor, control2: mirrored)
    case .curve(let to, let control1, _):
      segments[lastIndex] = .curve(to: to, control1: control1, control2: mirrored)
    }
    pendingLeadingControl = point
  }

  public func canClose(at point: CGPoint, tolerance: CGFloat) -> Bool {
    guard anchorCount >= 2, let start = startPoint else { return false }
    return hypot(point.x - start.x, point.y - start.y) <= tolerance
  }

  /// 시작점으로 닫는다. 핸들이 전혀 없으면 isClosed의 암묵적 닫힘 변을 쓰고,
  /// 핸들이 있으면 명시적 닫힘 곡선을 추가한다 (시작 핸들 미러).
  public mutating func close() -> BezierPath? {
    guard anchorCount >= 2, let start = startPoint else { return nil }
    var closingSegments = segments
    if pendingLeadingControl != nil || startLeadingControl != nil {
      let incoming: CGPoint
      if let startLeading = startLeadingControl {
        incoming = CGPoint(x: 2 * start.x - startLeading.x, y: 2 * start.y - startLeading.y)
      } else {
        incoming = start
      }
      let outgoing = pendingLeadingControl ?? (lastAnchor ?? start)
      closingSegments.append(.curve(to: start, control1: outgoing, control2: incoming))
    }
    reset()
    return BezierPath(subpaths: [Subpath(segments: closingSegments, isClosed: true)])
  }

  /// 열린 패스로 종료. 앵커 2개 미만이면 nil (버림).
  public mutating func finishOpen() -> BezierPath? {
    defer { reset() }
    guard anchorCount >= 2 else { return nil }
    return BezierPath(subpaths: [Subpath(segments: segments, isClosed: false)])
  }

  private mutating func reset() {
    segments = []
    pendingLeadingControl = nil
    startLeadingControl = nil
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → PASS (126개)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 펜 패스 작성 상태 머신 PenPathBuilder 추가"
```

---

### Task 3: DirectSelectTool

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Tools/DirectSelectTool.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DirectSelectToolTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

@MainActor
private func makeContext() -> (ToolContext, DirectSelectTool, NodeID) {
  // 100×50 사각형 (앵커: (10,10) (110,10) (110,60) (10,60))
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  let context = ToolContext(store: DocumentStore(document: document))
  return (context, DirectSelectTool(), node.id)
}

private func at(_ x: CGFloat, _ y: CGFloat) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), hitTolerance: 4)
}

@Test @MainActor func clickOnPathSetsEditTarget() {
  let (context, tool, nodeID) = makeContext()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  #expect(tool.editNodeID == nodeID)
  #expect(tool.selectedAnchor == nil)
}

@Test @MainActor func clickOnAnchorSelectsIt() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)  // 편집 대상 지정
  tool.mouseUp(at(50, 30), context: context)
  tool.mouseDown(at(110, 60), context: context)  // 우하단 앵커
  tool.mouseUp(at(110, 60), context: context)
  #expect(tool.selectedAnchor == AnchorRef(subpathIndex: 0, segmentIndex: 2))
}

@Test @MainActor func draggingAnchorMovesItWithSingleUndo() {
  let undoManager = UndoManager()
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 50)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  let store = DocumentStore(document: document) { undoManager }
  let context = ToolContext(store: store)
  let tool = DirectSelectTool()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  tool.mouseDown(at(110, 60), context: context)  // 앵커 잡기
  tool.mouseDragged(at(130, 80), context: context)
  tool.mouseDragged(at(140, 90), context: context)
  tool.mouseUp(at(140, 90), context: context)
  guard case .path(let edited)? = store.document.topLevelNode(id: node.id) else {
    Issue.record("패스가 아님")
    return
  }
  #expect(edited.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
    == CGPoint(x: 140, y: 90))
  undoManager.undo()
  guard case .path(let restored)? = store.document.topLevelNode(id: node.id) else { return }
  #expect(restored.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
    == CGPoint(x: 110, y: 60))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func draggingAnchorOnTransformedNodeUsesLocalCoordinates() {
  // 노드가 (100,0) 이동돼 있으면 모델 좌표 → 로컬 역변환 후 편집
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.path(node)]
  let context = ToolContext(store: DocumentStore(document: document))
  let tool = DirectSelectTool()
  tool.mouseDown(at(120, 20), context: context)  // 본체
  tool.mouseUp(at(120, 20), context: context)
  tool.mouseDown(at(150, 50), context: context)  // 모델 (150,50) = 로컬 (50,50) 앵커
  tool.mouseDragged(at(160, 60), context: context)
  tool.mouseUp(at(160, 60), context: context)
  guard case .path(let edited)? = context.store.document.topLevelNode(id: node.id) else { return }
  // 로컬 좌표로 (60,60)
  #expect(edited.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
    == CGPoint(x: 60, y: 60))
}

@Test @MainActor func clickEmptyClearsEditTarget() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  tool.mouseDown(at(250, 250), context: context)
  tool.mouseUp(at(250, 250), context: context)
  #expect(tool.editNodeID == nil)
}

@Test @MainActor func escapeClearsEditState() {
  let (context, tool, _) = makeContext()
  tool.mouseDown(at(50, 30), context: context)
  tool.mouseUp(at(50, 30), context: context)
  #expect(tool.keyDown(.escape, context: context))
  #expect(tool.editNodeID == nil)
  #expect(tool.selectedAnchor == nil)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`cannot find 'DirectSelectTool'`)

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Tools/DirectSelectTool.swift`

```swift
import CoreGraphics

/// 직접 선택 도구 (A): 최상위 패스 노드의 앵커·컨트롤 핸들을 드래그 편집한다.
/// M2b 범위: 그룹 내부 진입과 앵커 추가/삭제는 비목표 (M3 이후).
@MainActor
public final class DirectSelectTool: CanvasTool {
  private enum DragState {
    case idle
    case anchor(NodeID, AnchorRef)
    case control(NodeID, ControlRef)
  }

  private var dragState: DragState = .idle
  public private(set) var editNodeID: NodeID?
  public private(set) var selectedAnchor: AnchorRef?

  public var cursorKind: CursorKind { .arrow }

  public init() {}

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    if case .idle = dragState {
    } else {
      context.store.cancelTransient()
      dragState = .idle
    }
    let store = context.store
    let handleTolerance = event.hitTolerance * 1.5
    if let nodeID = editNodeID, let pathNode = topLevelPathNode(nodeID, in: store.document) {
      if let hitAnchor = hitAnchor(in: pathNode, at: event.point, tolerance: handleTolerance) {
        selectedAnchor = hitAnchor
        store.beginTransient()
        dragState = .anchor(nodeID, hitAnchor)
        context.invalidateOverlay()
        return
      }
      if let anchor = selectedAnchor,
        let hitControl = hitControl(
          in: pathNode, anchor: anchor, at: event.point, tolerance: handleTolerance) {
        store.beginTransient()
        dragState = .control(nodeID, hitControl)
        return
      }
    }
    if let hitID = HitTesting.topmostNodeID(
      at: event.point, in: store.document, tolerance: event.hitTolerance),
      case .path? = store.document.topLevelNode(id: hitID) {
      editNodeID = hitID
      selectedAnchor = nil
      context.invalidateOverlay()
      return
    }
    editNodeID = nil
    selectedAnchor = nil
    context.invalidateOverlay()
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .anchor(let nodeID, let ref):
      editPath(of: nodeID, context: context) { pathNode in
        guard let local = self.localPoint(event.point, in: pathNode) else { return pathNode.path }
        return pathNode.path.movingAnchor(ref, to: local)
      }
    case .control(let nodeID, let ref):
      editPath(of: nodeID, context: context) { pathNode in
        guard let local = self.localPoint(event.point, in: pathNode) else { return pathNode.path }
        return pathNode.path.movingControl(ref, to: local)
      }
    case .idle:
      break
    }
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .anchor:
      context.store.commitTransient(actionName: "앵커 이동")
    case .control:
      context.store.commitTransient(actionName: "핸들 이동")
    case .idle:
      break
    }
    dragState = .idle
  }

  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool {
    guard key == .escape else { return false }
    if case .idle = dragState {
    } else {
      context.store.cancelTransient()
      dragState = .idle
    }
    editNodeID = nil
    selectedAnchor = nil
    context.invalidateOverlay()
    return true
  }

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    guard let nodeID = editNodeID,
      let pathNode = topLevelPathNode(nodeID, in: context.store.document)
    else { return }
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    let transform = pathNode.transform.cgAffineTransform
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setLineWidth(1 / scale)
    var pathTransform = transform
    if let outline = pathNode.path.cgPath.copy(using: &pathTransform) {
      cgContext.addPath(outline)
      cgContext.strokePath()
    }
    let side = 7 / scale
    for (ref, localPosition) in pathNode.path.anchors() {
      let position = localPosition.applying(transform)
      let rect = CGRect(
        x: position.x - side / 2, y: position.y - side / 2, width: side, height: side)
      cgContext.setFillColor(ref == selectedAnchor ? accent : CGColor.white)
      cgContext.fill(rect)
      cgContext.stroke(rect)
    }
    if let anchor = selectedAnchor, let anchorLocal = pathNode.path.anchorPosition(anchor) {
      let anchorPosition = anchorLocal.applying(transform)
      for (_, handleLocal) in pathNode.path.controlHandles(forAnchor: anchor) {
        let handlePosition = handleLocal.applying(transform)
        cgContext.move(to: anchorPosition)
        cgContext.addLine(to: handlePosition)
        cgContext.strokePath()
        let radius = 3.5 / scale
        cgContext.setFillColor(accent)
        cgContext.fillEllipse(
          in: CGRect(
            x: handlePosition.x - radius, y: handlePosition.y - radius,
            width: radius * 2, height: radius * 2))
      }
    }
    cgContext.restoreGState()
  }

  // MARK: - 헬퍼

  private func topLevelPathNode(_ id: NodeID, in document: VectorDocument) -> PathNode? {
    guard case .path(let pathNode)? = document.topLevelNode(id: id) else { return nil }
    return pathNode
  }

  private func localPoint(_ point: CGPoint, in pathNode: PathNode) -> CGPoint? {
    guard let inverse = pathNode.transform.invertedOrNil else { return nil }
    return point.applying(inverse)
  }

  private func hitAnchor(
    in pathNode: PathNode, at point: CGPoint, tolerance: CGFloat
  ) -> AnchorRef? {
    let transform = pathNode.transform.cgAffineTransform
    return pathNode.path.anchors().first { _, localPosition in
      let position = localPosition.applying(transform)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }?.ref
  }

  private func hitControl(
    in pathNode: PathNode, anchor: AnchorRef, at point: CGPoint, tolerance: CGFloat
  ) -> ControlRef? {
    let transform = pathNode.transform.cgAffineTransform
    return pathNode.path.controlHandles(forAnchor: anchor).first { _, localPosition in
      let position = localPosition.applying(transform)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }?.ref
  }

  private func editPath(
    of nodeID: NodeID, context: ToolContext, _ newPath: @escaping (PathNode) -> BezierPath
  ) {
    context.store.updateTransient { document in
      document.updateTopLevelNodes(ids: [nodeID]) { node in
        guard case .path(var pathNode) = node else { return node }
        pathNode.path = newPath(pathNode)
        return .path(pathNode)
      }
    }
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → PASS (132개)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 직접 선택 도구 — 앵커·컨트롤 핸들 드래그 편집"
```

---

### Task 4: PenTool + CanvasTool.mouseMoved

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Tools/CanvasTool.swift` (mouseMoved 추가)
- Create: `VectaEngine/Sources/VectaEngine/Tools/PenTool.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PenToolTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

@MainActor
private func makeContext() -> (ToolContext, PenTool, DocumentStore) {
  let store = DocumentStore(document: .empty(size: CGSize(width: 300, height: 300)))
  return (ToolContext(store: store), PenTool(), store)
}

private func at(_ x: CGFloat, _ y: CGFloat) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), hitTolerance: 4)
}

@Test @MainActor func clicksThenEnterCommitsOpenPathOnce() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty(size: CGSize(width: 300, height: 300))) {
    undoManager
  }
  let context = ToolContext(store: store)
  let tool = PenTool()
  for point in [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), CGPoint(x: 100, y: 100)] {
    tool.mouseDown(CanvasEvent(point: point, hitTolerance: 4), context: context)
    tool.mouseUp(CanvasEvent(point: point, hitTolerance: 4), context: context)
  }
  #expect(store.document.layers[0].nodes.isEmpty)  // 아직 커밋 전
  #expect(tool.keyDown(.enter, context: context))
  let nodes = store.document.layers[0].nodes
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.path.subpaths[0].segments.count == 3)
  #expect(!pathNode.path.subpaths[0].isClosed)
  #expect(pathNode.style == .defaultShape)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.isEmpty)
  #expect(!undoManager.canUndo)  // 패스 전체가 undo 1단계
}

@Test @MainActor func clickingStartClosesPath() {
  let (context, tool, store) = makeContext()
  for point in [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), CGPoint(x: 50, y: 80)] {
    tool.mouseDown(CanvasEvent(point: point, hitTolerance: 4), context: context)
    tool.mouseUp(CanvasEvent(point: point, hitTolerance: 4), context: context)
  }
  tool.mouseDown(at(12, 11), context: context)  // 시작점 근처 → 닫기
  tool.mouseUp(at(12, 11), context: context)
  let nodes = store.document.layers[0].nodes
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else { return }
  #expect(pathNode.path.subpaths[0].isClosed)
}

@Test @MainActor func dragCreatesSmoothCurve() {
  let (context, tool, store) = makeContext()
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseDragged(at(40, 10), context: context)  // 시작 핸들
  tool.mouseUp(at(40, 10), context: context)
  tool.mouseDown(at(100, 50), context: context)
  tool.mouseUp(at(100, 50), context: context)
  #expect(tool.keyDown(.escape, context: context))
  guard case .path(let pathNode) = store.document.layers[0].nodes[0] else { return }
  guard case .curve = pathNode.path.subpaths[0].segments[1] else {
    Issue.record("곡선이 아님")
    return
  }
}

@Test @MainActor func escapeWithSingleAnchorDiscards() {
  let (context, tool, store) = makeContext()
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseUp(at(10, 10), context: context)
  #expect(tool.keyDown(.escape, context: context))
  #expect(store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func mouseMovedUpdatesRubberBandWithoutModelChange() {
  let (context, tool, store) = makeContext()
  let before = store.document
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseUp(at(10, 10), context: context)
  tool.mouseMoved(at(200, 200), context: context)
  #expect(store.document == before)  // 모델 불변
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL

- [ ] **Step 3: CanvasTool에 mouseMoved 추가** — `Tools/CanvasTool.swift`의 프로토콜에 메서드 추가 + 기본 구현

프로토콜 본문에 추가:
```swift
  /// 버튼 누르지 않은 이동 (펜 러버밴드 등). 기본 구현은 no-op.
  func mouseMoved(_ event: CanvasEvent, context: ToolContext)
```

extension에 추가:
```swift
  public func mouseMoved(_ event: CanvasEvent, context: ToolContext) {}
```

- [ ] **Step 4: PenTool 구현** — `Sources/VectaEngine/Tools/PenTool.swift`

```swift
import CoreGraphics

/// 펜 도구 (P): 클릭=코너, 드래그=스무스, 시작점 클릭=닫기, Esc/Enter=종료.
/// 패스는 도구 로컬(PenPathBuilder)에서 작성되고 종료 시 apply 1회 = undo 1단계.
@MainActor
public final class PenTool: CanvasTool {
  private var builder = PenPathBuilder()
  private var isDraggingHandle = false
  private var rubberBandPoint: CGPoint?

  public var cursorKind: CursorKind { .crosshair }

  public init() {}

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    if builder.canClose(at: event.point, tolerance: event.hitTolerance * 1.5) {
      let path = builder.close()
      commit(path, context: context)
      return
    }
    builder.addAnchor(at: event.point)
    isDraggingHandle = true
    context.invalidateOverlay()
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    guard isDraggingHandle else { return }
    builder.dragHandle(to: event.point)
    context.invalidateOverlay()
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    isDraggingHandle = false
  }

  public func mouseMoved(_ event: CanvasEvent, context: ToolContext) {
    rubberBandPoint = event.point
    if builder.anchorCount > 0 {
      context.invalidateOverlay()
    }
  }

  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool {
    switch key {
    case .enter, .escape:
      let path = builder.finishOpen()
      commit(path, context: context)
      return true
    case .delete:
      return false
    }
  }

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    guard builder.anchorCount > 0 else { return }
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setLineWidth(1 / scale)
    // 작성 중 세그먼트
    let preview = BezierPath(subpaths: [Subpath(segments: builder.segments, isClosed: false)])
    cgContext.addPath(preview.cgPath)
    cgContext.strokePath()
    // 러버밴드 (마지막 앵커 → 마우스)
    if let last = builder.lastAnchor, let rubber = rubberBandPoint {
      cgContext.setLineDash(phase: 0, lengths: [3 / scale, 3 / scale])
      cgContext.move(to: last)
      cgContext.addLine(to: rubber)
      cgContext.strokePath()
      cgContext.setLineDash(phase: 0, lengths: [])
    }
    // 드래그 중 핸들 라인
    if let last = builder.lastAnchor, let handle = builder.pendingHandle {
      let mirrored = CGPoint(x: 2 * last.x - handle.x, y: 2 * last.y - handle.y)
      cgContext.move(to: mirrored)
      cgContext.addLine(to: handle)
      cgContext.strokePath()
    }
    // 앵커 사각형
    let side = 6 / scale
    cgContext.setFillColor(CGColor.white)
    for segment in builder.segments {
      let position = segment.endPoint
      let rect = CGRect(
        x: position.x - side / 2, y: position.y - side / 2, width: side, height: side)
      cgContext.fill(rect)
      cgContext.stroke(rect)
    }
    cgContext.restoreGState()
  }

  private func commit(_ path: BezierPath?, context: ToolContext) {
    rubberBandPoint = nil
    defer { context.invalidateOverlay() }
    guard let path else { return }
    context.store.apply(actionName: "패스 생성") { document in
      document.layers[0].nodes.append(.path(PathNode(path: path, style: .defaultShape)))
    }
  }
}
```

- [ ] **Step 5: 통과 확인** — `swift test` → PASS (137개)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 펜 도구와 CanvasTool mouseMoved 지원 추가"
```

---

### Task 5: ToolKind 확장 + makeTool 팩토리

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Tools/CanvasEvent.swift` (ToolKind 케이스 추가)
- Create: `VectaEngine/Sources/VectaEngine/Tools/ToolKind+Factory.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ToolKindFactoryTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing
@testable import VectaEngine

@Test @MainActor func everyToolKindMakesMatchingTool() {
  // 망라 switch라 케이스 추가 시 컴파일 에러로 강제되지만,
  // 런타임 타입 매핑도 회귀 방지로 고정한다.
  #expect(ToolKind.select.makeTool() is SelectTool)
  #expect(ToolKind.directSelect.makeTool() is DirectSelectTool)
  #expect(ToolKind.pen.makeTool() is PenTool)
  #expect(ToolKind.rectangle.makeTool() is ShapeTool)
  #expect(ToolKind.ellipse.makeTool() is ShapeTool)
  #expect(ToolKind.allCases.count == 5)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL

- [ ] **Step 3: ToolKind 케이스 추가** — `Tools/CanvasEvent.swift`의 ToolKind를 교체 (순서 = 툴바 순서)

```swift
public enum ToolKind: String, CaseIterable, Equatable, Sendable {
  case select
  case directSelect
  case pen
  case rectangle
  case ellipse
}
```

- [ ] **Step 4: 팩토리 구현** — `Tools/ToolKind+Factory.swift`

```swift
/// ToolKind ↔ 도구 구현의 동기화를 망라 switch로 컴파일 타임에 강제한다
/// (케이스 추가 시 여기서 컴파일 에러 — M2a 리뷰의 강제 언래핑 지적 해소).
extension ToolKind {
  @MainActor
  public func makeTool() -> CanvasTool {
    switch self {
    case .select: return SelectTool()
    case .directSelect: return DirectSelectTool()
    case .pen: return PenTool()
    case .rectangle: return ShapeTool(shape: .rectangle)
    case .ellipse: return ShapeTool(shape: .ellipse)
    }
  }
}
```

- [ ] **Step 5: 통과 확인** — `swift test` → PASS (138개)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: ToolKind 직접선택·펜 추가와 makeTool 팩토리"
```

---

### Task 6: 앱 통합 — 팩토리·트래킹 영역·키 A/P·툴바

UI 셸 — 빌드 + 스모크 검증.

**Files:**
- Modify: `VectaApp/Sources/Canvas/CanvasView.swift`
- Modify: `VectaApp/Sources/Canvas/ToolState.swift`

- [ ] **Step 1: CanvasView 수정**

tools 딕셔너리 선언을 팩토리 기반으로 교체:
```swift
  // ToolKind.allCases × makeTool()로 전 케이스가 보장된다 (팩토리가 망라 switch).
  private let tools: [ToolKind: CanvasTool] = Dictionary(
    uniqueKeysWithValues: ToolKind.allCases.map { ($0, $0.makeTool()) })
```

트래킹 영역 + mouseMoved 포워딩 추가 (클래스 본문에):
```swift
  private var canvasTrackingArea: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let canvasTrackingArea {
      removeTrackingArea(canvasTrackingArea)
    }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
      owner: self, userInfo: nil)
    addTrackingArea(area)
    canvasTrackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    activeTool.mouseMoved(canvasEvent(from: event), context: toolContext)
  }
```

`handleToolShortcut`에 키 추가:
```swift
    case "a": toolState.activeTool = .directSelect
    case "p": toolState.activeTool = .pen
```

- [ ] **Step 2: ToolState 이름·심볼 추가** — `ToolKind` extension의 두 switch에 케이스 추가

```swift
    case .directSelect: return "직접 선택"
    case .pen: return "펜"
```
```swift
    case .directSelect: return "hand.point.up.left"
    case .pen: return "pencil.tip"
```

- [ ] **Step 3: 빌드 + 엔진 회귀**

```bash
cd VectaEngine && swift build && swift test   # 전체 PASS
cd ../VectaApp && xcodegen generate && \
xcodebuild -project Vecta.xcodeproj -scheme Vecta -configuration Debug \
  -derivedDataPath build build                # BUILD SUCCEEDED
```

- [ ] **Step 4: 실행 스모크**

`open VectaApp/build/Build/Products/Debug/Vecta.app` → `pgrep -x Vecta` 생존 확인 (System Events 윈도우 카운트는 신뢰 불가 — 필요 시 lldb). 끝나면 `pkill -x Vecta`. GUI 조작은 사용자 검증.

- [ ] **Step 5: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: 직접 선택·펜 도구 UI 통합 — 팩토리·트래킹·단축키"
```

---

### Task 7: 통합 회귀 + README + PR

- [ ] **Step 1: 전체 회귀** — 엔진 `swift test` 전체 PASS + 앱 xcodebuild BUILD SUCCEEDED

- [ ] **Step 2: 수동 검증 체크리스트** (사용자 수행)

1. P 키 → 펜: 클릭 3회 + Enter → 꺾은선 패스 생성, ⌘Z 1회로 전체 사라짐
2. 펜으로 클릭-드래그 반복 → 곡선 패스, 시작점 클릭으로 닫기
3. 펜 진행 중 마우스 이동 시 러버밴드 표시
4. A 키 → 직접 선택: 패스 클릭 → 앵커 표시, 앵커 드래그 → 모양 변형, ⌘Z 복원
5. 곡선 앵커 클릭 → 컨트롤 핸들 표시, 핸들 드래그 → 곡률 변경
6. V/A/P/M/L 전환과 Esc 동작, 줌 상태에서 앵커 크기 화면 고정
7. ⌘S 저장 → 재열기 → 편집된 패스 100% 복원

- [ ] **Step 3: README 갱신** — `- [x] M2a ...` 줄을 `- [x] M2 편집: 선택/이동/리사이즈/회전/직접선택/펜`으로 교체

- [ ] **Step 4: PR 생성**

```bash
git push -u origin m2b-direct-select-pen
gh pr create --base main --title "feat: M2b 직접 선택·펜 도구" \
  --body "$(cat <<'EOF'
## Summary
- 엔진: 패스 앵커/컨트롤 편집 기하(PathAnchors), 펜 상태 머신(PenPathBuilder), DirectSelectTool·PenTool, ToolKind makeTool 팩토리(망라 switch — 강제 언래핑 해소), CanvasTool.mouseMoved
- 앱: 트래킹 영역 + mouseMoved 포워딩(펜 러버밴드), 단축키 A/P, 툴바 5도구

## Test Plan
- [x] 엔진 swift test 전체 통과
- [x] xcodebuild BUILD SUCCEEDED
- [ ] 수동 체크리스트 7항목 (plan Task 7 Step 2)

Closes #3

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 완료 기준 (M2b Definition of Done)

- 엔진 테스트 전체 그린 (M2a 109개 + 신규 ~29개)
- 수동 체크리스트 7항목 통과
- 펜 패스 생성 = undo 1단계, 앵커/핸들 드래그 = 제스처당 undo 1단계
- PR이 이슈 #3을 닫음

## M3 예고

인스펙터(면/선/그라디언트 렌더+편집), 레이어 패널(활성 레이어 — layers[0] 하드코딩 제거), 그룹/해제, 앞뒤 순서 — 이슈 #4. 직접 선택의 그룹 내부 진입도 이때 함께.
