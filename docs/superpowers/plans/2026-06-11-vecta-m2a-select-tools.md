# Vecta M2a — Tool 아키텍처 + 선택 편집 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 선택 도구(클릭/Shift/마퀴 선택, 이동, 8핸들 리사이즈, 회전, 삭제)와 Tool 프로토콜 아키텍처를 도입하고 M1의 인라인 마우스 핸들러를 대체한다. (GitHub 이슈 #2, PR은 `Closes #2`)

**Architecture:** 도구 상태 머신·히트테스트·변환·선택 상태를 전부 VectaEngine에 두어 `swift test`로 검증한다 (커서만 앱에서 NSCursor로 매핑). 드래그 미리보기는 DocumentStore의 transient 변경 API(begin/update/commit/cancel)로 구현해 "제스처당 undo 1회" 계약을 유지한다. CanvasView는 NSEvent→CanvasEvent 변환과 도구 디스패치만 하는 얇은 셸이 된다.

**Tech Stack:** Swift 6.3 (언어 모드 v5), Swift Testing, CoreGraphics(CGPath 히트테스트), AppKit/SwiftUI 셸, XcodeGen.

**참조:** 스펙 `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` §4(선택 상태)·§7(캔버스/도구/히트테스트), M1 계획(컨벤션).

---

## 커밋 규칙 (사용자 전역 규칙 — M1과 동일)

매 커밋 전 순서 고정: ① analyze(`swift build` / 앱은 xcodebuild) → ② `swift test` → ③ `swift format --in-place --recursive Sources Tests` (VectaEngine에서; 앱은 `VectaApp/Sources`) → ④ commit. 한국어 메시지+접두사, Co-Authored-By 금지. 테스트 실패 시 ①부터 재수행.

## 파일 구조 (M2a 추가/변경분)

```
VectaEngine/Sources/VectaEngine/
├── Model/
│   └── VectorDocument+Editing.swift   # 최상위 노드 조회/일괄 변경/삭제
├── Geometry/
│   ├── BezierPath+Bounds.swift        # 패스·노드 바운드 (변환 반영)
│   ├── NodeTransformer.swift          # 이동/리사이즈/회전 순수 함수
│   └── HitTesting.swift               # 점→노드, 마퀴→노드 집합
├── State/
│   └── DocumentStore.swift  (수정)    # selection, transient API, deleteSelection
└── Tools/
    ├── CanvasEvent.swift              # CanvasEvent/CanvasKey/CursorKind/ToolKind
    ├── CanvasTool.swift               # 프로토콜 + ToolContext
    ├── SelectionHandles.swift         # 8핸들 좌표·히트·회전 존 (순수 함수)
    ├── SelectTool.swift               # 선택 도구 상태 머신
    └── ShapeTool.swift                # 사각형/타원 도구 (M1 로직 이관 + Shift)

VectaApp/Sources/
├── Canvas/CanvasView.swift  (재작성)  # 이벤트 변환 + 도구 디스패치 + 오버레이
├── Canvas/ToolState.swift   (재작성)  # ToolKind 기반
├── Panels/ToolbarView.swift (수정)    # 도구 3개 (선택/사각형/타원)
├── Document/VectaDocument.swift (수정)# 캔버스 initialFirstResponder
└── MainMenuBuilder.swift    (수정)    # 편집 메뉴: 모두 선택 ⌘A
```

좌표 계약(불변): 모델 = top-left, CanvasEvent.point는 모델 좌표. `hitTolerance`는 뷰 4pt를 줌 배율로 나눈 모델 좌표 허용 오차. 오버레이는 모델 좌표 컨텍스트에 그리되 핸들 크기는 `상수/scale`로 화면 크기를 유지한다.

---

### Task 1: 바운드 기하 (BezierPath·Node)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Geometry/BezierPath+Bounds.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/BoundsTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `value of type 'BezierPath' has no member 'bounds'`

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Geometry/BezierPath+Bounds.swift`

```swift
import CoreGraphics

extension BezierPath {
  /// 곡선을 포함한 타이트 바운딩 박스 (컨트롤 포인트 박스가 아님).
  public var bounds: CGRect {
    let box = cgPath.boundingBoxOfPath
    return box.isNull ? .zero : box
  }
}

extension Node {
  /// 부모 좌표계 기준 바운드 (자기 transform 적용 후). 선택 UI·마퀴 판정용.
  public var bounds: CGRect {
    switch self {
    case .path(let pathNode):
      var transform = pathNode.transform.cgAffineTransform
      let transformed = pathNode.path.cgPath.copy(using: &transform) ?? pathNode.path.cgPath
      let box = transformed.boundingBoxOfPath
      return box.isNull ? .zero : box
    case .group(let group):
      let union = group.children.reduce(CGRect.null) { $0.union($1.bounds) }
      let inner = group.clipPath.map { union.intersection($0.bounds) } ?? union
      guard !inner.isNull else { return .zero }
      return inner.applying(group.transform.cgAffineTransform)
    case .text(let text):
      // 정밀 텍스트 바운드는 M5에서. 현재는 위치 점.
      return CGRect(origin: text.position, size: .zero)
        .applying(text.transform.cgAffineTransform)
    case .image(let image):
      return image.frame.applying(image.transform.cgAffineTransform)
    }
  }
}
```

- [ ] **Step 4: 통과 확인** — `cd VectaEngine && swift test` → PASS (52개)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: BezierPath·Node 바운드 기하 추가"
```

---

### Task 2: NodeTransformer (이동/리사이즈/회전 순수 함수)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Geometry/NodeTransformer.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/NodeTransformerTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`cannot find 'NodeTransformer'`)

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Geometry/NodeTransformer.swift`

```swift
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
```

- [ ] **Step 4: 통과 확인** — `swift test` → PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 노드 이동·리사이즈·회전 변환 NodeTransformer 추가"
```

---

### Task 3: 히트테스트 + 문서 편집 헬퍼

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Geometry/HitTesting.swift`
- Create: `VectaEngine/Sources/VectaEngine/Model/VectorDocument+Editing.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/HitTestingTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`cannot find 'HitTesting'`)

- [ ] **Step 3: 히트테스트 구현** — `Sources/VectaEngine/Geometry/HitTesting.swift`

```swift
import CoreGraphics

/// 점·마퀴 → 노드 판정. 모든 좌표는 모델 좌표.
public enum HitTesting {
  /// 점에 닿는 최상단 노드 ID. 위 레이어·나중에 그려진 노드 우선,
  /// 숨김/잠금 레이어 제외. 그룹은 자식이 닿으면 그룹 ID를 반환한다.
  public static func topmostNodeID(
    at point: CGPoint, in document: VectorDocument, tolerance: CGFloat
  ) -> NodeID? {
    for layer in document.layers.reversed() where layer.isVisible && !layer.isLocked {
      for node in layer.nodes.reversed() where hits(node, at: point, tolerance: tolerance) {
        return node.id
      }
    }
    return nil
  }

  /// 마퀴 사각형과 바운드가 교차하는 최상위 노드 집합.
  public static func topLevelNodeIDs(
    intersecting rect: CGRect, in document: VectorDocument
  ) -> Set<NodeID> {
    var result: Set<NodeID> = []
    for layer in document.layers where layer.isVisible && !layer.isLocked {
      for node in layer.nodes where node.bounds.intersects(rect) {
        result.insert(node.id)
      }
    }
    return result
  }

  static func hits(_ node: Node, at point: CGPoint, tolerance: CGFloat) -> Bool {
    switch node {
    case .path(let pathNode):
      return hits(pathNode, at: point, tolerance: tolerance)
    case .group(let group):
      let local = point.applying(group.transform.cgAffineTransform.inverted())
      if let clip = group.clipPath, !clip.cgPath.contains(local, using: .winding) {
        return false
      }
      return group.children.contains { hits($0, at: local, tolerance: tolerance) }
    case .text:
      return false  // M5에서 텍스트 바운드와 함께
    case .image(let image):
      let local = point.applying(image.transform.cgAffineTransform.inverted())
      return image.frame.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
    }
  }

  static func hits(_ pathNode: PathNode, at point: CGPoint, tolerance: CGFloat) -> Bool {
    let local = point.applying(pathNode.transform.cgAffineTransform.inverted())
    let cgPath = pathNode.path.cgPath
    if pathNode.style.fill != nil, cgPath.contains(local, using: .winding) {
      return true
    }
    if let stroke = pathNode.style.stroke {
      let hitWidth = max(stroke.width, 1) + tolerance * 2
      let stroked = cgPath.copy(
        strokingWithWidth: hitWidth, lineCap: stroke.cap.cgLineCap,
        lineJoin: stroke.join.cgLineJoin, miterLimit: 10)
      if stroked.contains(local, using: .winding) {
        return true
      }
    }
    return false
  }
}
```

주의: `LineCap.cgLineCap`/`LineJoin.cgLineJoin`은 `SceneRenderer.swift`에 internal로 이미 존재한다 — 같은 모듈이므로 그대로 사용 가능.

- [ ] **Step 4: 편집 헬퍼 구현** — `Sources/VectaEngine/Model/VectorDocument+Editing.swift`

```swift
import Foundation

extension VectorDocument {
  /// 모든 레이어의 최상위 노드 ID (그룹 내부 제외 — M2a 선택 단위).
  public var topLevelNodeIDs: Set<NodeID> {
    Set(layers.flatMap { $0.nodes.map(\.id) })
  }

  public func topLevelNode(id: NodeID) -> Node? {
    for layer in layers {
      if let node = layer.nodes.first(where: { $0.id == id }) {
        return node
      }
    }
    return nil
  }

  public mutating func updateTopLevelNodes(ids: Set<NodeID>, _ change: (Node) -> Node) {
    for layerIndex in layers.indices {
      for nodeIndex in layers[layerIndex].nodes.indices
      where ids.contains(layers[layerIndex].nodes[nodeIndex].id) {
        layers[layerIndex].nodes[nodeIndex] = change(layers[layerIndex].nodes[nodeIndex])
      }
    }
  }

  public mutating func removeTopLevelNodes(ids: Set<NodeID>) {
    for layerIndex in layers.indices {
      layers[layerIndex].nodes.removeAll { ids.contains($0.id) }
    }
  }
}
```

- [ ] **Step 5: 통과 확인** — `swift test` → PASS

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 노드 히트테스트와 문서 편집 헬퍼 추가"
```

---

### Task 4: DocumentStore — 선택 상태·transient 변경·삭제

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/State/DocumentStore.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DocumentStoreSelectionTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

private func storeWithOneRect() -> (DocumentStore, NodeID) {
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaultShape)
  var document = VectorDocument.empty()
  document.layers[0].nodes = [.path(node)]
  return (DocumentStore(document: document), node.id)
}

@Test @MainActor func selectAndToggleAndClear() {
  let (store, id) = storeWithOneRect()
  store.select([id])
  #expect(store.selection == [id])
  store.toggleSelection(id)
  #expect(store.selection.isEmpty)
  store.toggleSelection(id)
  #expect(store.selection == [id])
  store.clearSelection()
  #expect(store.selection.isEmpty)
}

@Test @MainActor func selectIgnoresUnknownIDs() {
  let (store, id) = storeWithOneRect()
  store.select([id, NodeID()])
  #expect(store.selection == [id])
}

@Test @MainActor func selectionPrunedWhenNodeRemovedByApply() {
  let (store, id) = storeWithOneRect()
  store.select([id])
  store.apply(actionName: "삭제") { $0.removeTopLevelNodes(ids: [id]) }
  #expect(store.selection.isEmpty)
}

@Test @MainActor func loadClearsSelection() {
  let (store, id) = storeWithOneRect()
  store.select([id])
  store.load(.empty())
  #expect(store.selection.isEmpty)
}

@Test @MainActor func deleteSelectionRemovesNodesWithSingleUndoStep() {
  let undoManager = UndoManager()
  let node = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaultShape)
  var document = VectorDocument.empty()
  document.layers[0].nodes = [.path(node)]
  let store = DocumentStore(document: document) { undoManager }
  store.select([node.id])
  store.deleteSelection()
  #expect(store.document.layers[0].nodes.isEmpty)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.count == 1)
}

@Test @MainActor func selectionBoundsUnionsSelectedNodes() {
  let nodeA = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)), style: .defaultShape)
  let nodeB = PathNode(
    path: .rectangle(CGRect(x: 20, y: 20, width: 10, height: 10)), style: .defaultShape)
  var document = VectorDocument.empty()
  document.layers[0].nodes = [.path(nodeA), .path(nodeB)]
  let store = DocumentStore(document: document)
  #expect(store.selectionBounds == nil)
  store.select([nodeA.id, nodeB.id])
  #expect(store.selectionBounds == CGRect(x: 0, y: 0, width: 30, height: 30))
}

// --- transient ---

@Test @MainActor func transientUpdatesPublishWithoutUndo() {
  let undoManager = UndoManager()
  let (storeBase, id) = storeWithOneRect()
  let store = DocumentStore(document: storeBase.document) { undoManager }
  store.beginTransient()
  store.updateTransient { document in
    document.updateTopLevelNodes(ids: [id]) {
      NodeTransformer.translated($0, by: CGVector(dx: 5, dy: 0))
    }
  }
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 5)
  #expect(!undoManager.canUndo)
  store.commitTransient(actionName: "이동")
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 0)
}

@Test @MainActor func transientUpdateIsAbsoluteFromBase() {
  // update를 여러 번 호출해도 베이스 기준 절대 변경 — 누적되지 않는다
  let (store, id) = storeWithOneRect()
  store.beginTransient()
  for _ in 0..<3 {
    store.updateTransient { document in
      document.updateTopLevelNodes(ids: [id]) {
        NodeTransformer.translated($0, by: CGVector(dx: 7, dy: 0))
      }
    }
  }
  store.commitTransient(actionName: "이동")
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 7)
}

@Test @MainActor func cancelTransientRestoresBase() {
  let (store, id) = storeWithOneRect()
  store.beginTransient()
  store.updateTransient { document in
    document.updateTopLevelNodes(ids: [id]) {
      NodeTransformer.translated($0, by: CGVector(dx: 5, dy: 0))
    }
  }
  store.cancelTransient()
  #expect(store.document.topLevelNode(id: id)?.bounds.minX == 0)
}

@Test @MainActor func noOpTransientCommitRegistersNoUndo() {
  let undoManager = UndoManager()
  let (storeBase, _) = storeWithOneRect()
  let store = DocumentStore(document: storeBase.document) { undoManager }
  store.beginTransient()
  store.commitTransient(actionName: "이동")
  #expect(!undoManager.canUndo)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`has no member 'select'` 등)

- [ ] **Step 3: DocumentStore 확장 구현** — 기존 `State/DocumentStore.swift`에 추가 (기존 apply/load/registerUndo는 유지하되 아래 표시된 곳 수정)

```swift
  // 프로퍼티 추가
  @Published public private(set) var selection: Set<NodeID> = []
  private var transientBase: VectorDocument?

  // MARK: - 선택

  public func select(_ ids: Set<NodeID>) {
    selection = ids.intersection(document.topLevelNodeIDs)
  }

  public func toggleSelection(_ id: NodeID) {
    guard document.topLevelNodeIDs.contains(id) else { return }
    if selection.contains(id) {
      selection.remove(id)
    } else {
      selection.insert(id)
    }
  }

  public func clearSelection() {
    selection = []
  }

  /// 선택된 최상위 노드 바운드의 합집합 (선택 없으면 nil).
  public var selectionBounds: CGRect? {
    let rects = selection.compactMap { document.topLevelNode(id: $0)?.bounds }
    guard let first = rects.first else { return nil }
    return rects.dropFirst().reduce(first) { $0.union($1) }
  }

  public func deleteSelection() {
    guard !selection.isEmpty else { return }
    let ids = selection
    apply(actionName: "삭제") { $0.removeTopLevelNodes(ids: ids) }
  }

  // MARK: - Transient 변경 (드래그 제스처 미리보기)

  /// 드래그 시작. 이후 updateTransient는 이 시점 문서를 베이스로 한 절대
  /// 변경을 적용한다 (호출마다 누적되지 않음).
  public func beginTransient() {
    assert(transientBase == nil, "이미 transient 변경이 진행 중")
    transientBase = document
  }

  /// undo 등록 없이 문서를 갱신·발행한다. begin 없이 호출하면 무시.
  public func updateTransient(_ change: (inout VectorDocument) -> Void) {
    guard var base = transientBase else {
      assertionFailure("beginTransient 없이 updateTransient 호출")
      return
    }
    change(&base)
    document = base
  }

  /// 제스처 종료 — 베이스 대비 변경이 있으면 undo 1단계 등록.
  public func commitTransient(actionName: String) {
    guard let base = transientBase else { return }
    transientBase = nil
    guard document != base else { return }
    registerUndo(restoring: base, actionName: actionName)
  }

  /// 제스처 취소 — 베이스로 복원.
  public func cancelTransient() {
    guard let base = transientBase else { return }
    transientBase = nil
    document = base
  }
```

기존 메서드 2곳 수정:

```swift
  public func apply(actionName: String, _ change: (inout VectorDocument) -> Void) {
    var updated = document
    change(&updated)
    guard updated != document else { return }
    registerUndo(restoring: document, actionName: actionName)
    document = updated
    selection = selection.intersection(updated.topLevelNodeIDs)  // ← 추가: 삭제된 노드 정리
  }

  public func load(_ newDocument: VectorDocument) {
    document = newDocument
    selection = []  // ← 추가
    undoManagerProvider()?.removeAllActions()
  }
```

- [ ] **Step 4: 통과 확인** — `swift test` → PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: DocumentStore에 선택 상태·transient 변경·삭제 추가"
```

---

### Task 5: 도구 기반 타입 (CanvasEvent/CanvasTool/ToolContext) + SelectionHandles

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Tools/CanvasEvent.swift`
- Create: `VectaEngine/Sources/VectaEngine/Tools/CanvasTool.swift`
- Create: `VectaEngine/Sources/VectaEngine/Tools/SelectionHandles.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/SelectionHandlesTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL

- [ ] **Step 3: 이벤트·프로토콜 타입 구현**

`Sources/VectaEngine/Tools/CanvasEvent.swift`:

```swift
import CoreGraphics

/// 캔버스 마우스 이벤트의 플랫폼 독립 표현. point는 모델 좌표.
public struct CanvasEvent: Equatable, Sendable {
  public var point: CGPoint
  public var isShiftPressed: Bool
  public var clickCount: Int
  /// 줌 반영 히트 허용 오차 (뷰 ~4pt ÷ magnification, 모델 좌표 단위).
  public var hitTolerance: CGFloat

  public init(
    point: CGPoint, isShiftPressed: Bool = false,
    clickCount: Int = 1, hitTolerance: CGFloat = 4
  ) {
    self.point = point
    self.isShiftPressed = isShiftPressed
    self.clickCount = clickCount
    self.hitTolerance = hitTolerance
  }
}

public enum CanvasKey: Equatable, Sendable {
  case delete
  case escape
  case enter
}

/// 앱 레이어가 NSCursor로 매핑한다 (엔진은 AppKit 비의존 — 스펙 §7).
public enum CursorKind: Equatable, Sendable {
  case arrow
  case crosshair
}

public enum ToolKind: String, CaseIterable, Equatable, Sendable {
  case select
  case rectangle
  case ellipse
}
```

`Sources/VectaEngine/Tools/CanvasTool.swift`:

```swift
import CoreGraphics

/// 캔버스 도구 상태 머신. 모든 좌표는 모델 좌표 (스펙 §7).
@MainActor
public protocol CanvasTool: AnyObject {
  var cursorKind: CursorKind { get }
  func mouseDown(_ event: CanvasEvent, context: ToolContext)
  func mouseDragged(_ event: CanvasEvent, context: ToolContext)
  func mouseUp(_ event: CanvasEvent, context: ToolContext)
  /// 처리했으면 true (미처리 키는 캔버스가 다음 응답자로 넘긴다).
  func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool
  /// 모델 좌표 컨텍스트에 오버레이를 그린다. scale은 화면 확대 배율 —
  /// 핸들 등 화면 고정 크기 요소는 (상수 ÷ scale)로 그린다.
  func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext)
}

extension CanvasTool {
  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool { false }
  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {}
}

/// 도구가 문서·선택에 접근하고 오버레이 리드로우를 요청하는 통로.
@MainActor
public final class ToolContext {
  public let store: DocumentStore
  /// 모델 변경 없이 오버레이만 바뀌었을 때 호출 (모델 변경은 store가 발행).
  public var invalidateOverlay: () -> Void

  public init(store: DocumentStore, invalidateOverlay: @escaping () -> Void = {}) {
    self.store = store
    self.invalidateOverlay = invalidateOverlay
  }
}
```

- [ ] **Step 4: SelectionHandles 구현** — `Sources/VectaEngine/Tools/SelectionHandles.swift`

```swift
import CoreGraphics

/// 선택 바운드의 8개 리사이즈 핸들 (순수 함수 — 도구·오버레이가 공유).
public enum SelectionHandle: CaseIterable, Equatable, Sendable {
  case topLeft, topCenter, topRight
  case middleLeft, middleRight
  case bottomLeft, bottomCenter, bottomRight

  public func position(in bounds: CGRect) -> CGPoint {
    switch self {
    case .topLeft: return CGPoint(x: bounds.minX, y: bounds.minY)
    case .topCenter: return CGPoint(x: bounds.midX, y: bounds.minY)
    case .topRight: return CGPoint(x: bounds.maxX, y: bounds.minY)
    case .middleLeft: return CGPoint(x: bounds.minX, y: bounds.midY)
    case .middleRight: return CGPoint(x: bounds.maxX, y: bounds.midY)
    case .bottomLeft: return CGPoint(x: bounds.minX, y: bounds.maxY)
    case .bottomCenter: return CGPoint(x: bounds.midX, y: bounds.maxY)
    case .bottomRight: return CGPoint(x: bounds.maxX, y: bounds.maxY)
    }
  }

  public var opposite: SelectionHandle {
    switch self {
    case .topLeft: return .bottomRight
    case .topCenter: return .bottomCenter
    case .topRight: return .bottomLeft
    case .middleLeft: return .middleRight
    case .middleRight: return .middleLeft
    case .bottomLeft: return .topRight
    case .bottomCenter: return .topCenter
    case .bottomRight: return .topLeft
    }
  }

  /// 리사이즈 고정점 = 반대편 핸들 위치.
  public func anchor(in bounds: CGRect) -> CGPoint {
    opposite.position(in: bounds)
  }

  public var scalesX: Bool {
    switch self {
    case .topCenter, .bottomCenter: return false
    default: return true
    }
  }

  public var scalesY: Bool {
    switch self {
    case .middleLeft, .middleRight: return false
    default: return true
    }
  }

  /// 점이 닿는 핸들 (체비쇼프 거리 ≤ tolerance).
  public static func hitHandle(
    at point: CGPoint, bounds: CGRect, tolerance: CGFloat
  ) -> SelectionHandle? {
    allCases.first { handle in
      let position = handle.position(in: bounds)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }
  }

  /// 모서리 바깥 회전 존 (스펙 §7): 코너에서 (tolerance, 3×tolerance] 거리,
  /// 바운드 외부, 핸들 미적중일 때.
  public static func isInRotationZone(
    _ point: CGPoint, bounds: CGRect, tolerance: CGFloat
  ) -> Bool {
    guard !bounds.contains(point) else { return false }
    guard hitHandle(at: point, bounds: bounds, tolerance: tolerance) == nil else { return false }
    let corners: [SelectionHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    return corners.contains { corner in
      let position = corner.position(in: bounds)
      let distance = hypot(point.x - position.x, point.y - position.y)
      return distance <= tolerance * 3
    }
  }
}
```

- [ ] **Step 5: 통과 확인** — `swift test` → PASS

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: CanvasTool 프로토콜·CanvasEvent·SelectionHandles 추가"
```

---

### Task 6: SelectTool — 클릭/Shift/마퀴 선택 + 이동

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Tools/SelectTool.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/SelectToolTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing
@testable import VectaEngine

@MainActor
private func makeContext() -> (ToolContext, SelectTool, NodeID, NodeID) {
  let nodeA = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let nodeB = PathNode(
    path: .rectangle(CGRect(x: 100, y: 100, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.path(nodeA), .path(nodeB)]
  let context = ToolContext(store: DocumentStore(document: document))
  return (context, SelectTool(), nodeA.id, nodeB.id)
}

private func click(_ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), isShiftPressed: shift, hitTolerance: 4)
}

@Test @MainActor func clickSelectsTopmostNode() {
  let (context, tool, nodeA, _) = makeContext()
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseUp(click(25, 25), context: context)
  #expect(context.store.selection == [nodeA])
}

@Test @MainActor func clickEmptySpaceClearsSelection() {
  let (context, tool, nodeA, _) = makeContext()
  context.store.select([nodeA])
  tool.mouseDown(click(300, 300), context: context)
  tool.mouseUp(click(300, 300), context: context)
  #expect(context.store.selection.isEmpty)
}

@Test @MainActor func shiftClickTogglesMembership() {
  let (context, tool, nodeA, nodeB) = makeContext()
  context.store.select([nodeA])
  tool.mouseDown(click(125, 125, shift: true), context: context)
  tool.mouseUp(click(125, 125, shift: true), context: context)
  #expect(context.store.selection == [nodeA, nodeB])
  tool.mouseDown(click(125, 125, shift: true), context: context)
  tool.mouseUp(click(125, 125, shift: true), context: context)
  #expect(context.store.selection == [nodeA])
}

@Test @MainActor func dragSelectedNodeMovesItWithSingleUndo() {
  let undoManager = UndoManager()
  let (base, tool, nodeA, _) = makeContext()
  let store = DocumentStore(document: base.store.document) { undoManager }
  let context = ToolContext(store: store)
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseDragged(click(35, 30), context: context)
  tool.mouseDragged(click(45, 35), context: context)
  tool.mouseUp(click(45, 35), context: context)
  // 총 델타 (20, 10)
  #expect(store.document.topLevelNode(id: nodeA)?.bounds.origin == CGPoint(x: 20, y: 10))
  #expect(undoManager.canUndo)
  undoManager.undo()
  #expect(store.document.topLevelNode(id: nodeA)?.bounds.origin == .zero)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func marqueeSelectsIntersectingNodes() {
  let (context, tool, nodeA, nodeB) = makeContext()
  tool.mouseDown(click(200, 200), context: context)
  tool.mouseDragged(click(120, 120), context: context)
  tool.mouseUp(click(120, 120), context: context)
  #expect(context.store.selection == [nodeB])
  // 전체를 덮는 마퀴
  tool.mouseDown(click(220, 220), context: context)
  tool.mouseDragged(click(-10, -10), context: context)
  tool.mouseUp(click(-10, -10), context: context)
  #expect(context.store.selection == [nodeA, nodeB])
}

@Test @MainActor func deleteKeyRemovesSelection() {
  let (context, tool, nodeA, _) = makeContext()
  context.store.select([nodeA])
  #expect(tool.keyDown(.delete, context: context))
  #expect(context.store.document.topLevelNode(id: nodeA) == nil)
}

@Test @MainActor func escapeClearsSelectionWhenIdle() {
  let (context, tool, nodeA, _) = makeContext()
  context.store.select([nodeA])
  #expect(tool.keyDown(.escape, context: context))
  #expect(context.store.selection.isEmpty)
}

@Test @MainActor func escapeDuringMoveCancelsGesture() {
  let (context, tool, nodeA, _) = makeContext()
  tool.mouseDown(click(25, 25), context: context)
  tool.mouseDragged(click(45, 25), context: context)
  #expect(tool.keyDown(.escape, context: context))
  #expect(context.store.document.topLevelNode(id: nodeA)?.bounds.origin == .zero)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`cannot find 'SelectTool'`)

- [ ] **Step 3: SelectTool 구현 (이동·마퀴까지)** — `Sources/VectaEngine/Tools/SelectTool.swift`

```swift
import CoreGraphics

/// 선택 도구 (V): 클릭/Shift 토글/마퀴 선택, 드래그 이동,
/// 핸들 리사이즈·코너 바깥 회전 (Task 7에서 확장).
@MainActor
public final class SelectTool: CanvasTool {
  enum DragState {
    case idle
    case movingSelection(start: CGPoint)
    case marquee(start: CGPoint, current: CGPoint)
    case resizing(handle: SelectionHandle, baseBounds: CGRect)
    case rotating(center: CGPoint, startAngle: CGFloat)
  }

  var dragState: DragState = .idle
  public var cursorKind: CursorKind { .arrow }

  public init() {}

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    let store = context.store
    if let bounds = store.selectionBounds {
      let handleTolerance = event.hitTolerance * 1.5
      if let handle = SelectionHandle.hitHandle(
        at: event.point, bounds: bounds, tolerance: handleTolerance) {
        store.beginTransient()
        dragState = .resizing(handle: handle, baseBounds: bounds)
        return
      }
      if SelectionHandle.isInRotationZone(event.point, bounds: bounds, tolerance: handleTolerance) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        store.beginTransient()
        dragState = .rotating(center: center, startAngle: angle(from: center, to: event.point))
        return
      }
    }
    if let hitID = HitTesting.topmostNodeID(
      at: event.point, in: store.document, tolerance: event.hitTolerance) {
      if event.isShiftPressed {
        store.toggleSelection(hitID)
      } else if !store.selection.contains(hitID) {
        store.select([hitID])
      }
      if store.selection.contains(hitID) {
        store.beginTransient()
        dragState = .movingSelection(start: event.point)
      }
      return
    }
    if !event.isShiftPressed {
      store.clearSelection()
    }
    dragState = .marquee(start: event.point, current: event.point)
    context.invalidateOverlay()
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .movingSelection(let start):
      let delta = CGVector(dx: event.point.x - start.x, dy: event.point.y - start.y)
      let ids = context.store.selection
      context.store.updateTransient { document in
        document.updateTopLevelNodes(ids: ids) {
          NodeTransformer.translated($0, by: delta)
        }
      }
    case .marquee(let start, _):
      dragState = .marquee(start: start, current: event.point)
      context.invalidateOverlay()
    case .resizing(let handle, let baseBounds):
      resize(to: event, handle: handle, baseBounds: baseBounds, context: context)
    case .rotating(let center, let startAngle):
      rotate(to: event, center: center, startAngle: startAngle, context: context)
    case .idle:
      break
    }
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .movingSelection:
      context.store.commitTransient(actionName: "이동")
    case .resizing:
      context.store.commitTransient(actionName: "크기 조절")
    case .rotating:
      context.store.commitTransient(actionName: "회전")
    case .marquee(let start, _):
      let rect = CGRect(corner: start, oppositeCorner: event.point)
      let hits = HitTesting.topLevelNodeIDs(intersecting: rect, in: context.store.document)
      if event.isShiftPressed {
        context.store.select(context.store.selection.union(hits))
      } else {
        context.store.select(hits)
      }
      context.invalidateOverlay()
    case .idle:
      break
    }
    dragState = .idle
  }

  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool {
    switch key {
    case .delete:
      context.store.deleteSelection()
      return true
    case .escape:
      if case .idle = dragState {
        context.store.clearSelection()
      } else {
        context.store.cancelTransient()
        dragState = .idle
        context.invalidateOverlay()
      }
      return true
    case .enter:
      return false
    }
  }

  // resize/rotate/drawOverlay는 Task 7에서 구현 — 이 Task에서는 컴파일을 위한
  // 최소 본체만 둔다.
  func resize(
    to event: CanvasEvent, handle: SelectionHandle, baseBounds: CGRect, context: ToolContext
  ) {}

  func rotate(
    to event: CanvasEvent, center: CGPoint, startAngle: CGFloat, context: ToolContext
  ) {}

  func angle(from center: CGPoint, to point: CGPoint) -> CGFloat {
    atan2(point.y - center.y, point.x - center.x)
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: SelectTool 클릭·Shift·마퀴 선택과 이동 구현"
```

---

### Task 7: SelectTool — 리사이즈·회전 + 오버레이

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Tools/SelectTool.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/SelectToolResizeTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing
@testable import VectaEngine

@MainActor
private func makeSelected() -> (ToolContext, SelectTool, NodeID) {
  let node = PathNode(
    path: .rectangle(CGRect(x: 100, y: 100, width: 100, height: 100)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.path(node)]
  let context = ToolContext(store: DocumentStore(document: document))
  context.store.select([node.id])
  return (context, SelectTool(), node.id)
}

private func event(_ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), isShiftPressed: shift, hitTolerance: 4)
}

@Test @MainActor func cornerHandleResizesAroundOppositeAnchor() {
  let (context, tool, node) = makeSelected()
  // bottomRight 핸들 (200,200) 잡고 (300,250)으로 → anchor (100,100),
  // scaleX 2, scaleY 1.5
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(300, 250), context: context)
  tool.mouseUp(event(300, 250), context: context)
  #expect(
    context.store.document.topLevelNode(id: node)?.bounds
      == CGRect(x: 100, y: 100, width: 200, height: 150))
}

@Test @MainActor func edgeHandleResizesSingleAxis() {
  let (context, tool, node) = makeSelected()
  // middleRight (200,150) → (250,300): scaleX 1.5, y는 불변
  tool.mouseDown(event(200, 150), context: context)
  tool.mouseDragged(event(250, 300), context: context)
  tool.mouseUp(event(250, 300), context: context)
  #expect(
    context.store.document.topLevelNode(id: node)?.bounds
      == CGRect(x: 100, y: 100, width: 150, height: 100))
}

@Test @MainActor func shiftCornerResizeIsUniform() {
  let (context, tool, node) = makeSelected()
  // bottomRight를 (300,250)으로 + Shift → 지배 축 비율 2.0 균등
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(300, 250, shift: true), context: context)
  tool.mouseUp(event(300, 250, shift: true), context: context)
  #expect(
    context.store.document.topLevelNode(id: node)?.bounds
      == CGRect(x: 100, y: 100, width: 200, height: 200))
}

@Test @MainActor func resizeIsSingleUndoStep() {
  let undoManager = UndoManager()
  let nodeSource = PathNode(
    path: .rectangle(CGRect(x: 100, y: 100, width: 100, height: 100)),
    style: Style(fill: .color(.black)))
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = [.path(nodeSource)]
  let store = DocumentStore(document: document) { undoManager }
  let context = ToolContext(store: store)
  store.select([nodeSource.id])
  let tool = SelectTool()
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(220, 220), context: context)
  tool.mouseDragged(event(300, 300), context: context)
  tool.mouseUp(event(300, 300), context: context)
  undoManager.undo()
  #expect(
    store.document.topLevelNode(id: nodeSource.id)?.bounds
      == CGRect(x: 100, y: 100, width: 100, height: 100))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func rotationZoneDragRotatesSelection() {
  let (context, tool, node) = makeSelected()
  // 코너 (200,100) 바깥 회전 존에서 시작
  let start = CGPoint(x: 208, y: 92)
  tool.mouseDown(event(start.x, start.y), context: context)
  // 중심 (150,150) 기준 90° 회전한 위치로 드래그:
  // start-중심 벡터 (58,-58) → 90°(y-아래 좌표계 시계) 회전 → (58,58) → (208,208)
  tool.mouseDragged(event(208, 208), context: context)
  tool.mouseUp(event(208, 208), context: context)
  let bounds = context.store.document.topLevelNode(id: node)!.bounds
  // 정사각형 90° 회전 → 바운드 동일 (중심 유지)
  #expect(abs(bounds.midX - 150) < 0.01)
  #expect(abs(bounds.midY - 150) < 0.01)
  #expect(abs(bounds.width - 100) < 0.01)
}

@Test @MainActor func degenerateResizeIsClampedToNoOp() {
  let (context, tool, node) = makeSelected()
  // 핸들을 anchor 위로 정확히 끌어도 0 스케일이 되지 않는다
  tool.mouseDown(event(200, 200), context: context)
  tool.mouseDragged(event(100, 100), context: context)
  tool.mouseUp(event(100, 100), context: context)
  let bounds = context.store.document.topLevelNode(id: node)!.bounds
  #expect(bounds.width > 0.5)
  #expect(bounds.height > 0.5)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (resize/rotate가 빈 본체라 assertion 실패)

- [ ] **Step 3: resize/rotate/오버레이 구현** — `SelectTool.swift`의 빈 메서드를 교체하고 오버레이 추가

```swift
  private static let minimumScaleDenominator: CGFloat = 0.001
  private static let minimumScale: CGFloat = 0.01

  func resize(
    to event: CanvasEvent, handle: SelectionHandle, baseBounds: CGRect, context: ToolContext
  ) {
    let anchor = handle.anchor(in: baseBounds)
    let handleStart = handle.position(in: baseBounds)
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    if handle.scalesX {
      scaleX = safeRatio(event.point.x - anchor.x, handleStart.x - anchor.x)
    }
    if handle.scalesY {
      scaleY = safeRatio(event.point.y - anchor.y, handleStart.y - anchor.y)
    }
    if event.isShiftPressed && handle.scalesX && handle.scalesY {
      let uniform = max(abs(scaleX), abs(scaleY))
      scaleX = scaleX < 0 ? -uniform : uniform
      scaleY = scaleY < 0 ? -uniform : uniform
    }
    let ids = context.store.selection
    context.store.updateTransient { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.resized($0, anchor: anchor, scaleX: scaleX, scaleY: scaleY)
      }
    }
  }

  func rotate(
    to event: CanvasEvent, center: CGPoint, startAngle: CGFloat, context: ToolContext
  ) {
    let delta = angle(from: center, to: event.point) - startAngle
    let ids = context.store.selection
    context.store.updateTransient { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.rotated($0, around: center, by: delta)
      }
    }
  }

  /// 분모가 0에 가까우면 1, 결과가 0에 가까우면 최소 스케일로 클램프
  /// (특이 행렬 방지 — 0 스케일은 역변환 불가).
  private func safeRatio(_ numerator: CGFloat, _ denominator: CGFloat) -> CGFloat {
    guard abs(denominator) > Self.minimumScaleDenominator else { return 1 }
    let ratio = numerator / denominator
    if abs(ratio) < Self.minimumScale {
      return ratio < 0 ? -Self.minimumScale : Self.minimumScale
    }
    return ratio
  }

  // MARK: - 오버레이

  private static let handleScreenSize: CGFloat = 8
  private static let selectionLineScreenWidth: CGFloat = 1

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    if let bounds = context.store.selectionBounds {
      drawSelectionChrome(bounds: bounds, in: cgContext, scale: scale)
    }
    if case .marquee(let start, let current) = dragState {
      drawMarquee(
        rect: CGRect(corner: start, oppositeCorner: current), in: cgContext, scale: scale)
    }
  }

  private func drawSelectionChrome(bounds: CGRect, in cgContext: CGContext, scale: CGFloat) {
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setLineWidth(Self.selectionLineScreenWidth / scale)
    cgContext.stroke(bounds)
    let side = Self.handleScreenSize / scale
    cgContext.setFillColor(CGColor.white)
    for handle in SelectionHandle.allCases {
      let position = handle.position(in: bounds)
      let rect = CGRect(
        x: position.x - side / 2, y: position.y - side / 2, width: side, height: side)
      cgContext.fill(rect)
      cgContext.stroke(rect)
    }
    cgContext.restoreGState()
  }

  private func drawMarquee(rect: CGRect, in cgContext: CGContext, scale: CGFloat) {
    let accent = CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 1)
    cgContext.saveGState()
    cgContext.setStrokeColor(accent)
    cgContext.setFillColor(CGColor(srgbRed: 0.0, green: 0.47, blue: 1.0, alpha: 0.1))
    cgContext.setLineWidth(Self.selectionLineScreenWidth / scale)
    cgContext.setLineDash(phase: 0, lengths: [4 / scale, 4 / scale])
    cgContext.fill(rect)
    cgContext.stroke(rect)
    cgContext.restoreGState()
  }
```

- [ ] **Step 4: 통과 확인** — `swift test` → PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: SelectTool 리사이즈·회전과 선택 오버레이 구현"
```

---

### Task 8: ShapeTool (사각형/타원 이관 + Shift 정비율)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Tools/ShapeTool.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ShapeToolTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing
@testable import VectaEngine

private func drag(_ x: CGFloat, _ y: CGFloat, shift: Bool = false) -> CanvasEvent {
  CanvasEvent(point: CGPoint(x: x, y: y), isShiftPressed: shift, hitTolerance: 4)
}

@Test func dragRectNormalizesAndConstrains() {
  #expect(
    ShapeTool.dragRect(
      from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 30), constrainSquare: false)
      == CGRect(x: 10, y: 10, width: 30, height: 20))
  // Shift: 큰 변 기준 정사각형, 드래그 방향 유지
  #expect(
    ShapeTool.dragRect(
      from: CGPoint(x: 10, y: 10), to: CGPoint(x: 40, y: 30), constrainSquare: true)
      == CGRect(x: 10, y: 10, width: 30, height: 30))
  // 음의 방향 드래그 + Shift
  #expect(
    ShapeTool.dragRect(
      from: CGPoint(x: 40, y: 40), to: CGPoint(x: 10, y: 30), constrainSquare: true)
      == CGRect(x: 10, y: 10, width: 30, height: 30))
}

@Test @MainActor func dragCreatesRectangleNodeWithDefaultStyle() {
  let context = ToolContext(store: DocumentStore(document: .empty()))
  let tool = ShapeTool(shape: .rectangle)
  tool.mouseDown(drag(10, 10), context: context)
  tool.mouseDragged(drag(60, 40), context: context)
  tool.mouseUp(drag(60, 40), context: context)
  let nodes = context.store.document.layers[0].nodes
  #expect(nodes.count == 1)
  #expect(nodes[0].bounds == CGRect(x: 10, y: 10, width: 50, height: 30))
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("path 노드가 아님")
    return
  }
  #expect(pathNode.style == .defaultShape)
}

@Test @MainActor func ellipseToolCreatesEllipse() {
  let context = ToolContext(store: DocumentStore(document: .empty()))
  let tool = ShapeTool(shape: .ellipse)
  tool.mouseDown(drag(0, 0), context: context)
  tool.mouseUp(drag(40, 20), context: context)
  guard case .path(let pathNode) = context.store.document.layers[0].nodes[0] else {
    Issue.record("path 노드가 아님")
    return
  }
  let curveCount = pathNode.path.subpaths[0].segments.filter {
    if case .curve = $0 { return true } else { return false }
  }.count
  #expect(curveCount == 4)
}

@Test @MainActor func tinyDragCreatesNothing() {
  let context = ToolContext(store: DocumentStore(document: .empty()))
  let tool = ShapeTool(shape: .rectangle)
  tool.mouseDown(drag(10, 10), context: context)
  tool.mouseUp(drag(10.5, 10.5), context: context)
  #expect(context.store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func shapeCreationIsOneUndoStep() {
  let undoManager = UndoManager()
  let store = DocumentStore(document: .empty()) { undoManager }
  let context = ToolContext(store: store)
  let tool = ShapeTool(shape: .rectangle)
  tool.mouseDown(drag(10, 10), context: context)
  tool.mouseUp(drag(60, 60), context: context)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.isEmpty)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`cannot find 'ShapeTool'`)

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Tools/ShapeTool.swift`

```swift
import CoreGraphics

/// 사각형/타원 생성 도구 (M/L). 드래그 미리보기는 오버레이로 그리고
/// mouseUp에 apply 1회 (= undo 1단계).
@MainActor
public final class ShapeTool: CanvasTool {
  public enum Shape {
    case rectangle
    case ellipse
  }

  private let shape: Shape
  private var dragStart: CGPoint?
  private var dragCurrent: CGPoint?
  private var shiftPressed = false

  public var cursorKind: CursorKind { .crosshair }

  public init(shape: Shape) {
    self.shape = shape
  }

  /// 드래그 두 점 → 정규화 rect. Shift면 큰 변 기준 정사각형 (방향 유지).
  static func dragRect(from start: CGPoint, to end: CGPoint, constrainSquare: Bool) -> CGRect {
    guard constrainSquare else {
      return CGRect(corner: start, oppositeCorner: end)
    }
    let side = max(abs(end.x - start.x), abs(end.y - start.y))
    let constrainedEnd = CGPoint(
      x: start.x + (end.x < start.x ? -side : side),
      y: start.y + (end.y < start.y ? -side : side))
    return CGRect(corner: start, oppositeCorner: constrainedEnd)
  }

  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    dragStart = event.point
    dragCurrent = event.point
    shiftPressed = event.isShiftPressed
  }

  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    guard dragStart != nil else { return }
    dragCurrent = event.point
    shiftPressed = event.isShiftPressed
    context.invalidateOverlay()
  }

  public func mouseUp(_ event: CanvasEvent, context: ToolContext) {
    defer {
      dragStart = nil
      dragCurrent = nil
      context.invalidateOverlay()
    }
    guard let start = dragStart else { return }
    let rect = Self.dragRect(from: start, to: event.point, constrainSquare: event.isShiftPressed)
    guard rect.width >= 1, rect.height >= 1 else { return }
    let path = makePath(in: rect)
    context.store.apply(actionName: "도형 추가") { document in
      document.layers[0].nodes.append(.path(PathNode(path: path, style: .defaultShape)))
    }
  }

  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {
    guard let start = dragStart, let current = dragCurrent else { return }
    let rect = Self.dragRect(from: start, to: current, constrainSquare: shiftPressed)
    guard case .color(let fill) = Style.defaultShape.fill else { return }
    cgContext.saveGState()
    cgContext.setAlpha(0.5)
    cgContext.addPath(makePath(in: rect).cgPath)
    cgContext.setFillColor(fill.cgColor)
    cgContext.fillPath()
    cgContext.restoreGState()
  }

  private func makePath(in rect: CGRect) -> BezierPath {
    switch shape {
    case .rectangle: return .rectangle(rect)
    case .ellipse: return .ellipse(in: rect)
    }
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: ShapeTool로 도형 생성 이관·Shift 정비율 지원"
```

---

### Task 9: 앱 통합 — CanvasView 도구 디스패치·키보드·툴바·메뉴

UI 셸이므로 빌드 + 스모크로 검증한다.

**Files:**
- Modify: `VectaApp/Sources/Canvas/ToolState.swift` (전면 교체)
- Modify: `VectaApp/Sources/Canvas/CanvasView.swift` (전면 교체)
- Modify: `VectaApp/Sources/Panels/ToolbarView.swift` (ShapeKind→ToolKind)
- Modify: `VectaApp/Sources/Document/VectaDocument.swift` (initialFirstResponder)
- Modify: `VectaApp/Sources/MainMenuBuilder.swift` (모두 선택 ⌘A)
- Modify: `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` (§7 cursor 표기)

- [ ] **Step 1: ToolState 교체**

```swift
import Foundation
import VectaEngine

// M1의 ShapeKind 기반에서 ToolKind 기반으로 교체 (M2a).
final class ToolState: ObservableObject {
  @Published var activeTool: ToolKind = .select
}

extension ToolKind {
  var koreanName: String {
    switch self {
    case .select: return "선택"
    case .rectangle: return "사각형"
    case .ellipse: return "타원"
    }
  }

  var symbolName: String {
    switch self {
    case .select: return "cursorarrow"
    case .rectangle: return "rectangle"
    case .ellipse: return "circle"
    }
  }
}
```

- [ ] **Step 2: CanvasView 교체**

```swift
import AppKit
import Combine
import VectaEngine

/// 아트보드 크기 frame의 문서 뷰. 모델 좌표 = 뷰 좌표(flipped).
/// NSEvent → CanvasEvent 변환과 활성 도구 디스패치만 담당하는 얇은 셸.
final class CanvasView: NSView {
  private static let viewHitTolerance: CGFloat = 4

  private let store: DocumentStore
  private let toolState: ToolState
  private let tools: [ToolKind: CanvasTool] = [
    .select: SelectTool(),
    .rectangle: ShapeTool(shape: .rectangle),
    .ellipse: ShapeTool(shape: .ellipse),
  ]
  private lazy var toolContext = ToolContext(store: store) { [weak self] in
    self?.needsDisplay = true
  }
  private var subscriptions: Set<AnyCancellable> = []

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  private var activeTool: CanvasTool { tools[toolState.activeTool]! }

  private var magnification: CGFloat {
    enclosingScrollView?.magnification ?? 1
  }

  init(store: DocumentStore, toolState: ToolState) {
    self.store = store
    self.toolState = toolState
    super.init(frame: NSRect(origin: .zero, size: store.document.artboard.size))
    // objectWillChange는 변경 직전 발행되지만 DispatchQueue 스케줄러는 항상
    // async 디스패치하므로 sink는 변경 완료 후 실행된다.
    store.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.documentDidChange() }
      .store(in: &subscriptions)
    toolState.$activeTool
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.activeToolDidChange() }
      .store(in: &subscriptions)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("Interface Builder를 사용하지 않는다")
  }

  private func documentDidChange() {
    setFrameSize(store.document.artboard.size)
    needsDisplay = true
  }

  private func activeToolDidChange() {
    window?.invalidateCursorRects(for: self)
    needsDisplay = true
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: activeTool.cursorKind.nsCursor)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
    cgContext.setFillColor(CGColor.white)
    cgContext.fill(CGRect(origin: .zero, size: store.document.artboard.size))
    SceneRenderer.render(store.document, in: cgContext)
    activeTool.drawOverlay(in: cgContext, scale: magnification, context: toolContext)
  }

  // MARK: - 이벤트 → CanvasEvent

  private func canvasEvent(from event: NSEvent) -> CanvasEvent {
    CanvasEvent(
      point: convert(event.locationInWindow, from: nil),
      isShiftPressed: event.modifierFlags.contains(.shift),
      clickCount: event.clickCount,
      hitTolerance: Self.viewHitTolerance / magnification)
  }

  override func mouseDown(with event: NSEvent) {
    activeTool.mouseDown(canvasEvent(from: event), context: toolContext)
  }

  override func mouseDragged(with event: NSEvent) {
    activeTool.mouseDragged(canvasEvent(from: event), context: toolContext)
  }

  override func mouseUp(with event: NSEvent) {
    activeTool.mouseUp(canvasEvent(from: event), context: toolContext)
  }

  // MARK: - 키보드

  override func keyDown(with event: NSEvent) {
    if handleToolShortcut(event) || handleToolKey(event) {
      return
    }
    super.keyDown(with: event)
  }

  private func handleToolShortcut(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
      let characters = event.charactersIgnoringModifiers?.lowercased()
    else { return false }
    switch characters {
    case "v": toolState.activeTool = .select
    case "m": toolState.activeTool = .rectangle
    case "l": toolState.activeTool = .ellipse
    default: return false
    }
    return true
  }

  private func handleToolKey(_ event: NSEvent) -> Bool {
    guard let key = canvasKey(from: event) else { return false }
    return activeTool.keyDown(key, context: toolContext)
  }

  private func canvasKey(from event: NSEvent) -> CanvasKey? {
    switch event.keyCode {
    case 51, 117: return .delete  // backspace, forward delete
    case 53: return .escape
    case 36, 76: return .enter  // return, keypad enter
    default: return nil
    }
  }

  override func selectAll(_ sender: Any?) {
    store.select(store.document.topLevelNodeIDs)
  }
}

extension CursorKind {
  var nsCursor: NSCursor {
    switch self {
    case .arrow: return .arrow
    case .crosshair: return .crosshair
    }
  }
}
```

- [ ] **Step 3: ToolbarView 수정** — `ShapeKind` → `ToolKind`

```swift
import SwiftUI
import VectaEngine

private enum ToolbarLayout {
  static let buttonSide: CGFloat = 36
  static let stripWidth: CGFloat = 56
  static let buttonSpacing: CGFloat = 8
  static let topPadding: CGFloat = 12
  static let iconSize: CGFloat = 18
  static let cornerRadius: CGFloat = 6
}

struct ToolbarView: View {
  @ObservedObject var toolState: ToolState

  var body: some View {
    VStack(spacing: ToolbarLayout.buttonSpacing) {
      ForEach(ToolKind.allCases, id: \.self) { kind in
        Button {
          toolState.activeTool = kind
        } label: {
          Image(systemName: kind.symbolName)
            .font(.system(size: ToolbarLayout.iconSize))
            .frame(width: ToolbarLayout.buttonSide, height: ToolbarLayout.buttonSide)
        }
        .buttonStyle(.borderless)
        .background(
          toolState.activeTool == kind ? Color.accentColor.opacity(0.25) : .clear,
          in: RoundedRectangle(cornerRadius: ToolbarLayout.cornerRadius)
        )
        .help(kind.koreanName)
        .accessibilityLabel(kind.koreanName)
      }
      Spacer()
    }
    .padding(.top, ToolbarLayout.topPadding)
    .frame(width: ToolbarLayout.stripWidth)
  }
}
```

- [ ] **Step 4: VectaDocument 수정** — 캔버스를 첫 응답자로

`makeContentView()`에서 canvasView를 지역 변수로 분리해 보관하고, `makeWindowControllers()`에서 윈도우의 initialFirstResponder로 지정:

```swift
  override func makeWindowControllers() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    let canvasView = CanvasView(store: store, toolState: toolState)
    window.contentView = makeContentView(canvasView: canvasView)
    window.initialFirstResponder = canvasView
    window.center()
    addWindowController(NSWindowController(window: window))
  }

  private func makeContentView(canvasView: CanvasView) -> NSView {
    let scrollView = NSScrollView()
    scrollView.documentView = canvasView
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = true
    scrollView.allowsMagnification = true
    scrollView.minMagnification = 0.1
    scrollView.maxMagnification = 64
    scrollView.backgroundColor = .windowBackgroundColor

    let toolbar = NSHostingView(rootView: ToolbarView(toolState: toolState))
    let stack = NSStackView(views: [toolbar, scrollView])
    stack.orientation = .horizontal
    stack.distribution = .fill
    stack.spacing = 0
    return stack
  }
```

- [ ] **Step 5: 편집 메뉴에 모두 선택 추가** — `MainMenuBuilder.editMenu()`에 추가

```swift
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "모두 선택",
      action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
```

- [ ] **Step 6: 스펙 §7 표기 갱신** — `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md`의 Tool 프로토콜 의사 코드에서 `var cursor: NSCursor { get }`를 `var cursorKind: CursorKind { get }  // NSCursor 매핑은 앱 레이어`로 교체하고, 도구 로직이 엔진(Tools/)에 있어 헤드리스 테스트됨을 한 줄 추가.

- [ ] **Step 7: 빌드 + 엔진 회귀**

```bash
cd VectaEngine && swift build && swift test   # 전체 PASS
cd ../VectaApp && xcodegen generate && \
xcodebuild -project Vecta.xcodeproj -scheme Vecta -configuration Debug \
  -derivedDataPath build build                # BUILD SUCCEEDED
```

- [ ] **Step 8: 실행 스모크**

`open VectaApp/build/Build/Products/Debug/Vecta.app` → `pgrep -x Vecta` 생존 확인. lldb로 contentView 구조 확인 가능하면 확인 (System Events 윈도우 카운트는 신뢰 불가). 끝나면 `pkill -x Vecta`. GUI 조작 검증은 사용자가 수행.

- [ ] **Step 9: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: 캔버스 도구 디스패치 전환·선택 도구 UI 통합"
```

---

### Task 10: 통합 회귀 + 수동 검증 + PR

- [ ] **Step 1: 전체 회귀** — 엔진 `swift test` 전체 PASS + 앱 xcodebuild BUILD SUCCEEDED

- [ ] **Step 2: 수동 검증 체크리스트** (사용자 수행)

1. V(선택)/M(사각형)/L(타원) 키로 도구 전환, 툴바 하이라이트 동기화
2. 사각형 2개 + 타원 1개 생성 (Shift 드래그 → 정사각형/정원)
3. 클릭 선택 → 파란 바운드+8핸들, Shift 클릭 다중 선택, 빈 곳 클릭 해제
4. 마퀴 드래그로 여러 개 선택
5. 선택 드래그 이동 → ⌘Z 1회로 복귀
6. 코너 핸들 리사이즈(+Shift 비율 유지), 에지 핸들 단축 리사이즈
7. 코너 바깥 드래그로 회전
8. Delete로 삭제 → ⌘Z 복원, ⌘A 모두 선택, Esc 해제
9. 줌(핀치) 상태에서 1~8 일부 재확인 (핸들 화면 크기 유지)
10. ⌘S 저장 → 재열기 → 편집 결과 보존

- [ ] **Step 3: README 현재 상태 갱신** — M2 항목을 `- [x] M2a 선택 편집 (M2b 직접선택/펜 남음)`으로 수정

- [ ] **Step 4: PR 생성**

```bash
git push -u origin m2a-select-tools
gh pr create --base main --title "feat: M2a 선택 도구 — Tool 아키텍처, 선택/이동/리사이즈/회전" \
  --body "$(cat <<'EOF'
## Summary
- 엔진: 바운드/히트테스트/NodeTransformer 기하, DocumentStore 선택 상태·transient 변경(제스처당 undo 1회)·삭제, CanvasTool 프로토콜 + SelectTool/ShapeTool
- 앱: CanvasView를 도구 디스패치 셸로 재작성, 단축키 V/M/L/Delete/Esc/⌘A, 선택 오버레이

## Test Plan
- [x] 엔진 swift test 전체 통과
- [x] xcodebuild BUILD SUCCEEDED
- [ ] 수동 체크리스트 10항목 (plan Task 10 Step 2)

Closes #2
EOF
)"
```

---

## 완료 기준 (M2a Definition of Done)

- 엔진 테스트 전체 그린 (M1 47개 + 신규 ~40개)
- 수동 체크리스트 10항목 통과
- 제스처(이동/리사이즈/회전/생성)당 undo 정확히 1단계
- PR이 이슈 #2를 닫음

## M2b 예고 (다음 계획)

직접 선택 도구(앵커/컨트롤 핸들 편집), 펜 도구(베지어 작성), CursorKind 확장(pen 등), 단축키 A/P — 이슈 #3.
