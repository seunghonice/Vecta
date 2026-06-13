# M5a 선택 조작 (패스파인더·정렬·복사/붙여넣기) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 선택된 객체를 대상으로 패스파인더 4종(합치기·빼기·교차·제외), 정렬 6종, 복사/잘라내기/붙여넣기/복제를 제공한다.

**Architecture:** 엔진(VectaEngine, AppKit 비의존)에 순수 모델 연산과 DocumentStore 명령을 TDD로 추가하고, 앱(VectaApp)은 인스펙터 버튼·메뉴·NSPasteboard I/O로 그 명령을 노출한다. 패스파인더는 각 패스를 모델 좌표 CGPath로 베이크 → `normalized(using:)` 정규화 → CGPath 불린 연산 → 결과 PathNode 1개로 치환(스타일·자리 = 최하단). 클립보드는 엔진이 `[Node]` ↔ `Data`(Codable JSON) 직렬화를 책임지고, 앱은 NSPasteboard 커스텀 타입으로 읽고 쓴다.

**Tech Stack:** Swift 6, Swift Testing, CoreGraphics(CGPath boolean ops — macOS 13+, 엔진 이미 사용 중), AppKit(NSPasteboard·NSMenu), SwiftUI(인스펙터).

---

## File Structure

**엔진 — 신규**
- `VectaEngine/Sources/VectaEngine/Model/Pathfinder.swift` — `PathfinderOperation` enum + `VectorDocument.combineSelectedPaths(ids:operation:)`
- `VectaEngine/Sources/VectaEngine/Model/NodeAlignment.swift` — `AlignEdge` enum + `VectorDocument.alignTopLevelNodes(ids:edge:within:)`
- `VectaEngine/Sources/VectaEngine/Model/NodeClipboard.swift` — `NodeClipboard`(encode/decode/pasteboardType) + `Node.withFreshIDs()`
- `VectaEngine/Sources/VectaEngine/State/DocumentStore+Pathfinder.swift` — `applyPathfinder(_:)` + `combinablePathCount`
- `VectaEngine/Sources/VectaEngine/State/DocumentStore+Align.swift` — `alignSelection(edge:)`
- `VectaEngine/Sources/VectaEngine/State/DocumentStore+Clipboard.swift` — `copyableSelection()` / `pasteNodes(_:offset:)` / `duplicateSelection()`

**엔진 테스트 — 신규**
- `VectaEngine/Tests/VectaEngineTests/PathfinderTests.swift`
- `VectaEngine/Tests/VectaEngineTests/NodeAlignmentTests.swift`
- `VectaEngine/Tests/VectaEngineTests/NodeClipboardTests.swift`

**앱 — 수정**
- `VectaApp/Sources/Panels/InspectorView.swift` — `PathfinderSection`·`AlignSection` 추가 + body에 배치
- `VectaApp/Sources/MainMenuBuilder.swift` — 편집 메뉴(잘라내기/복사/붙여넣기/복제), 오브젝트 메뉴(패스파인더 4종)
- `VectaApp/Sources/Document/VectaDocument.swift` — `@objc` 액션 8종 + `validateUserInterfaceItem` 분기

**문서 — 수정**
- `README.md` — 현재 상태 체크박스

각 태스크는 자체 완결 변경이다. 엔진 태스크(1·3·5)는 TDD(실패 테스트 → 구현 → 통과). 앱 태스크(2·4·6)는 앱 타깃에 테스트 하니스가 없으므로 빌드 성공 + 수동 GUI 체크리스트(사용자 수행)로 마감한다.

---

### Task 1: 패스파인더 엔진

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/Pathfinder.swift`
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore+Pathfinder.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PathfinderTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

`VectaEngine/Tests/VectaEngineTests/PathfinderTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private let red = RGBA(red: 1, green: 0, blue: 0)
private let blue = RGBA(red: 0, green: 0, blue: 1)

private func rect(_ frame: CGRect, fill: RGBA = .black) -> PathNode {
  PathNode(path: .rectangle(frame), style: Style(fill: .color(fill)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func pathfinderUniteReplacesSelectionWithSinglePath() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let b = rect(CGRect(x: 50, y: 50, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  store.applyPathfinder(.unite)
  #expect(store.document.layers[0].nodes.count == 1)
  guard case .path(let result) = store.document.layers[0].nodes[0] else {
    Issue.record("결과가 패스 노드가 아님")
    return
  }
  // 합집합 바운드 = 두 사각형 바운드의 union (0,0)-(150,150).
  let bounds = Node.path(result).bounds
  #expect(abs(bounds.minX - 0) < 0.5)
  #expect(abs(bounds.minY - 0) < 0.5)
  #expect(abs(bounds.maxX - 150) < 0.5)
  #expect(abs(bounds.maxY - 150) < 0.5)
  #expect(store.selection == [result.id])
}

@Test @MainActor func pathfinderIntersectBoundsIsOverlap() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let b = rect(CGRect(x: 50, y: 50, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  store.applyPathfinder(.intersect)
  let bounds = store.document.layers[0].nodes[0].bounds
  // 교집합 = (50,50)-(100,100).
  #expect(abs(bounds.minX - 50) < 0.5)
  #expect(abs(bounds.minY - 50) < 0.5)
  #expect(abs(bounds.maxX - 100) < 0.5)
  #expect(abs(bounds.maxY - 100) < 0.5)
}

@Test @MainActor func pathfinderSubtractRemovesTopFromBottom() {
  // 아래(최하단) 큰 사각형에서 오른쪽 절반을 덮는 위 사각형을 뺀다 → 왼쪽 절반.
  let bottom = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let top = rect(CGRect(x: 50, y: 0, width: 100, height: 100))
  let store = makeStore(nodes: [.path(bottom), .path(top)])
  store.select([bottom.id, top.id])
  store.applyPathfinder(.subtract)
  let bounds = store.document.layers[0].nodes[0].bounds
  #expect(abs(bounds.minX - 0) < 0.5)
  #expect(abs(bounds.maxX - 50) < 0.5)  // 오른쪽 절반이 잘려나감
}

@Test @MainActor func pathfinderUsesBottomMostStyle() {
  let bottom = rect(CGRect(x: 0, y: 0, width: 100, height: 100), fill: red)
  let top = rect(CGRect(x: 50, y: 50, width: 100, height: 100), fill: blue)
  let store = makeStore(nodes: [.path(bottom), .path(top)])
  store.select([bottom.id, top.id])
  store.applyPathfinder(.unite)
  guard case .path(let result) = store.document.layers[0].nodes[0],
    case .color(let color) = result.style.fill
  else {
    Issue.record("결과 스타일을 읽을 수 없음")
    return
  }
  #expect(color == red)  // 최하단 스타일
}

@Test @MainActor func pathfinderRequiresTwoPaths() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a)])
  store.select([a.id])
  store.applyPathfinder(.unite)
  #expect(store.document.layers[0].nodes.count == 1)
  #expect(store.document.layers[0].nodes[0].id == a.id)  // 변화 없음
}

@Test @MainActor func pathfinderIgnoresNonPathNodes() {
  // 패스 1 + 텍스트 1 선택 → 패스가 1개뿐이라 no-op.
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let text = TextNode(
    string: "안녕", fontName: "Helvetica", fontSize: 12,
    fill: .color(.black), position: CGPoint(x: 10, y: 10))
  let store = makeStore(nodes: [.path(a), .text(text)])
  store.select([a.id, text.id])
  store.applyPathfinder(.unite)
  #expect(store.document.layers[0].nodes.count == 2)  // 변화 없음
}

@Test @MainActor func pathfinderIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let b = rect(CGRect(x: 50, y: 50, width: 100, height: 100))
  let store = makeStore(nodes: [.path(a), .path(b)], undoManager: undoManager)
  store.select([a.id, b.id])
  store.applyPathfinder(.unite)
  undoManager.undo()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id, b.id])
  #expect(!undoManager.canUndo)
}

@Test @MainActor func combinablePathCountCountsOnlyPaths() {
  let a = rect(CGRect(x: 0, y: 0, width: 100, height: 100))
  let text = TextNode(
    string: "x", fontName: "Helvetica", fontSize: 12,
    fill: .color(.black), position: .zero)
  let store = makeStore(nodes: [.path(a), .text(text)])
  store.select([a.id, text.id])
  #expect(store.combinablePathCount == 1)
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd VectaEngine && swift test --filter PathfinderTests`
Expected: 컴파일 실패 — `applyPathfinder`, `combinablePathCount`, `PathfinderOperation` 미정의.

- [ ] **Step 3: 패스파인더 모델 연산 구현**

`VectaEngine/Sources/VectaEngine/Model/Pathfinder.swift`:

```swift
import CoreGraphics

/// 패스파인더 불린 연산 (스펙 §8). Illustrator 합치기/빼기/교차/제외에 대응.
public enum PathfinderOperation: Sendable {
  case unite
  case subtract
  case intersect
  case exclude
}

extension VectorDocument {
  /// 선택된 최상위 패스 노드들을 불린 연산으로 합쳐 하나의 패스 노드로 치환한다.
  /// 패스가 2개 미만이면 아무것도 하지 않고 nil을 반환한다.
  /// 비-패스 노드(그룹·텍스트·이미지)는 무시한다.
  ///
  /// 좌표 처리: 각 패스를 자기 transform으로 모델 좌표에 베이크한 뒤, 자기
  /// fillRule로 `normalized` 정규화한다(자가교차 패스를 단일 winding 영역으로).
  /// 결과는 모델 좌표이므로 새 노드의 transform은 identity, fillRule은 winding.
  /// 스타일과 z-자리는 최하단(문서 z-순서 맨 아래) 패스를 따른다.
  @discardableResult
  public mutating func combineSelectedPaths(
    ids: Set<NodeID>, operation: PathfinderOperation
  ) -> NodeID? {
    // 문서 z-순서로 선택된 최상위 패스 노드 수집 (맨 앞 = 최하단).
    var ordered: [PathNode] = []
    for layer in layers {
      for node in layer.nodes where ids.contains(node.id) {
        if case .path(let pathNode) = node { ordered.append(pathNode) }
      }
    }
    guard ordered.count >= 2 else { return nil }

    let normalized = ordered.map { node -> CGPath in
      let model = node.path.applying(node.transform.cgAffineTransform).cgPath
      let rule: CGPathFillRule = node.fillRule == .evenOdd ? .evenOdd : .winding
      return model.normalized(using: rule)
    }
    let combined = Self.applyBoolean(normalized, operation: operation)

    let bottom = ordered[0]
    let result = PathNode(
      path: BezierPath(cgPath: combined),
      style: bottom.style,
      transform: .identity,
      fillRule: .winding)

    updateTopLevelNodes(ids: [bottom.id]) { _ in .path(result) }
    removeTopLevelNodes(ids: ids.subtracting([bottom.id]))
    return result.id
  }

  /// 정규화된 패스 배열에 불린 연산 적용. 입력은 모두 winding 영역으로 정규화됨.
  private static func applyBoolean(
    _ paths: [CGPath], operation: PathfinderOperation
  ) -> CGPath {
    let first = paths[0]
    let rest = Array(paths.dropFirst())  // count >= 1 보장 (호출부 guard)
    switch operation {
    case .unite:
      return rest.reduce(first) { $0.union($1, using: .winding) }
    case .intersect:
      return rest.reduce(first) { $0.intersection($1, using: .winding) }
    case .exclude:
      return rest.reduce(first) { $0.symmetricDifference($1, using: .winding) }
    case .subtract:
      // 최하단에서 그 위 모든 패스의 합집합을 뺀다 (Illustrator Minus Front).
      let top = rest.dropFirst().reduce(rest[0]) { $0.union($1, using: .winding) }
      return first.subtracting(top, using: .winding)
    }
  }
}
```

`VectaEngine/Sources/VectaEngine/State/DocumentStore+Pathfinder.swift`:

```swift
/// 패스파인더 명령 — 인스펙터 4버튼·오브젝트 메뉴와 연결된다 (스펙 §8).
extension DocumentStore {
  /// 선택된 최상위 패스(2개 이상)를 불린 연산으로 합쳐 결과를 선택한다.
  public func applyPathfinder(_ operation: PathfinderOperation) {
    let ids = selection
    var resultID: NodeID?
    apply(actionName: "패스파인더") {
      resultID = $0.combineSelectedPaths(ids: ids, operation: operation)
    }
    if let resultID { select([resultID]) }
  }

  /// 선택 중 패스파인더 대상이 되는 최상위 패스 노드 수 (UI 활성화 판단용).
  public var combinablePathCount: Int {
    selection.reduce(into: 0) { count, id in
      if case .path? = document.topLevelNode(id: id) { count += 1 }
    }
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd VectaEngine && swift test --filter PathfinderTests`
Expected: PASS (8 테스트).

- [ ] **Step 5: 커밋**

분석 → 테스트 → 포맷 → 커밋 순서 준수:

```bash
cd VectaEngine && swift build && swift test
swift format --in-place --recursive Sources Tests
cd .. && git add VectaEngine/Sources/VectaEngine/Model/Pathfinder.swift \
  VectaEngine/Sources/VectaEngine/State/DocumentStore+Pathfinder.swift \
  VectaEngine/Tests/VectaEngineTests/PathfinderTests.swift
git commit -m "feat: 패스파인더 4종 엔진 연산 (합치기·빼기·교차·제외)"
```

---

### Task 2: 패스파인더 UI (인스펙터 + 오브젝트 메뉴)

**Files:**
- Modify: `VectaApp/Sources/Panels/InspectorView.swift`
- Modify: `VectaApp/Sources/MainMenuBuilder.swift:54-71` (objectMenu)
- Modify: `VectaApp/Sources/Document/VectaDocument.swift`

- [ ] **Step 1: 인스펙터 PathfinderSection 추가**

`VectaApp/Sources/Panels/InspectorView.swift`의 `InspectorView.body` 안 `TransformSection(store: store)` 다음 줄에 추가:

```swift
          TransformSection(store: store)
          Divider()
          PathfinderSection(store: store)
```

같은 파일 맨 아래(파일 끝)에 섹션 뷰 추가:

```swift
/// 패스파인더 4종 — 선택된 패스 2개 이상에서 활성화 (스펙 §8).
struct PathfinderSection: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("패스파인더").font(.headline)
      HStack(spacing: 6) {
        button("합치기", systemName: "plus.square.on.square") {
          store.applyPathfinder(.unite)
        }
        button("빼기", systemName: "minus.square") {
          store.applyPathfinder(.subtract)
        }
        button("교차", systemName: "square.on.square.intersection.dashed") {
          store.applyPathfinder(.intersect)
        }
        button("제외", systemName: "square.on.square.squareshape.controlhandles") {
          store.applyPathfinder(.exclude)
        }
      }
      .disabled(store.combinablePathCount < 2)
    }
  }

  private func button(
    _ label: String, systemName: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.bordered)
    .help(label)
    .accessibilityLabel(label)
  }
}
```

- [ ] **Step 2: VectaDocument 패스파인더 액션 추가**

`VectaApp/Sources/Document/VectaDocument.swift`의 `sendBackward(_:)` 다음(L124 부근)에 추가:

```swift
  @objc func pathfinderUnite(_ sender: Any?) {
    store.applyPathfinder(.unite)
  }

  @objc func pathfinderSubtract(_ sender: Any?) {
    store.applyPathfinder(.subtract)
  }

  @objc func pathfinderIntersect(_ sender: Any?) {
    store.applyPathfinder(.intersect)
  }

  @objc func pathfinderExclude(_ sender: Any?) {
    store.applyPathfinder(.exclude)
  }
```

같은 파일 `validateUserInterfaceItem`의 `switch` 안 `default:` 위에 분기 추가:

```swift
    case #selector(pathfinderUnite(_:)), #selector(pathfinderSubtract(_:)),
      #selector(pathfinderIntersect(_:)), #selector(pathfinderExclude(_:)):
      return store.combinablePathCount >= 2
```

- [ ] **Step 3: 오브젝트 메뉴에 패스파인더 추가**

`VectaApp/Sources/MainMenuBuilder.swift`의 `objectMenu()`에서 `뒤로 보내기` 항목 다음(L69)·`return menu` 앞에 추가:

```swift
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "합치기",
      action: #selector(VectaDocument.pathfinderUnite(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: "빼기",
      action: #selector(VectaDocument.pathfinderSubtract(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: "교차",
      action: #selector(VectaDocument.pathfinderIntersect(_:)), keyEquivalent: "")
    menu.addItem(
      withTitle: "제외",
      action: #selector(VectaDocument.pathfinderExclude(_:)), keyEquivalent: "")
```

- [ ] **Step 4: 빌드 확인**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 수동 GUI 체크리스트 (사용자 수행)**

`make run` 후 확인:
- 사각형 2개 그리고 둘 다 선택 → 인스펙터 "패스파인더" 4버튼 활성화
- 합치기 → 1개 패스로 병합, 빼기/교차/제외 각 동작
- 패스 1개만 선택 시 버튼 비활성화
- 오브젝트 메뉴에서도 동일 동작, ⌘Z로 1단계 되돌리기

- [ ] **Step 6: 커밋**

```bash
make build
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
swift format --in-place --recursive VectaApp/Sources
git add VectaApp/Sources/Panels/InspectorView.swift \
  VectaApp/Sources/MainMenuBuilder.swift \
  VectaApp/Sources/Document/VectaDocument.swift
git commit -m "feat: 패스파인더 인스펙터 버튼·오브젝트 메뉴 연결"
```

---

### Task 3: 정렬 엔진

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/NodeAlignment.swift`
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore+Align.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/NodeAlignmentTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

`VectaEngine/Tests/VectaEngineTests/NodeAlignmentTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(_ frame: CGRect) -> PathNode {
  PathNode(path: .rectangle(frame), style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func alignLeftMovesNodesToSelectionLeft() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let left = store.selectionBounds!.minX  // 10
  store.alignSelection(edge: .left)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.minX - left) < 0.5)
  }
}

@Test @MainActor func alignRightMovesNodesToSelectionRight() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let right = store.selectionBounds!.maxX  // 180
  store.alignSelection(edge: .right)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.maxX - right) < 0.5)
  }
}

@Test @MainActor func alignCenterVerticalCentersNodes() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let midY = store.selectionBounds!.midY
  store.alignSelection(edge: .centerVertical)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.midY - midY) < 0.5)
  }
}

@Test @MainActor func alignTopMovesNodesToSelectionTop() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  let top = store.selectionBounds!.minY  // 10 (모델 y-아래: 위 = 작은 y)
  store.alignSelection(edge: .top)
  for node in store.document.layers[0].nodes {
    #expect(abs(node.bounds.minY - top) < 0.5)
  }
}

@Test @MainActor func alignRequiresTwoNodes() {
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let store = makeStore(nodes: [.path(a)])
  store.select([a.id])
  store.alignSelection(edge: .left)
  #expect(store.document.layers[0].nodes[0].bounds.minX == 10)  // 변화 없음
}

@Test @MainActor func alignIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(CGRect(x: 10, y: 10, width: 50, height: 50))
  let b = rect(CGRect(x: 100, y: 100, width: 80, height: 30))
  let store = makeStore(nodes: [.path(a), .path(b)], undoManager: undoManager)
  store.select([a.id, b.id])
  store.alignSelection(edge: .left)
  undoManager.undo()
  #expect(store.document.layers[0].nodes[0].bounds.minX == 10)
  #expect(store.document.layers[0].nodes[1].bounds.minX == 100)
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd VectaEngine && swift test --filter NodeAlignmentTests`
Expected: 컴파일 실패 — `alignSelection`, `AlignEdge` 미정의.

- [ ] **Step 3: 정렬 모델 + 명령 구현**

`VectaEngine/Sources/VectaEngine/Model/NodeAlignment.swift`:

```swift
import CoreGraphics

/// 정렬 기준 (스펙 §8). 모델은 y-아래 좌표계이므로 top = 최소 y, bottom = 최대 y.
public enum AlignEdge: Sendable {
  case left
  case centerHorizontal
  case right
  case top
  case centerVertical
  case bottom
}

extension VectorDocument {
  /// 선택된 최상위 노드들을 기준 바운드에 맞춰 정렬한다.
  /// 가로 기준(left/centerHorizontal/right)은 x축만, 세로 기준은 y축만 이동한다.
  public mutating func alignTopLevelNodes(
    ids: Set<NodeID>, edge: AlignEdge, within bounds: CGRect
  ) {
    updateTopLevelNodes(ids: ids) { node in
      let frame = node.bounds
      let delta: CGVector
      switch edge {
      case .left:
        delta = CGVector(dx: bounds.minX - frame.minX, dy: 0)
      case .centerHorizontal:
        delta = CGVector(dx: bounds.midX - frame.midX, dy: 0)
      case .right:
        delta = CGVector(dx: bounds.maxX - frame.maxX, dy: 0)
      case .top:
        delta = CGVector(dx: 0, dy: bounds.minY - frame.minY)
      case .centerVertical:
        delta = CGVector(dx: 0, dy: bounds.midY - frame.midY)
      case .bottom:
        delta = CGVector(dx: 0, dy: bounds.maxY - frame.maxY)
      }
      return NodeTransformer.translated(node, by: delta)
    }
  }
}
```

`VectaEngine/Sources/VectaEngine/State/DocumentStore+Align.swift`:

```swift
/// 정렬 명령 — 인스펙터 6버튼과 연결된다 (스펙 §8). 선택 바운드를 기준으로 한다.
extension DocumentStore {
  public func alignSelection(edge: AlignEdge) {
    let ids = selection
    guard ids.count >= 2, let bounds = selectionBounds else { return }
    apply(actionName: "정렬") {
      $0.alignTopLevelNodes(ids: ids, edge: edge, within: bounds)
    }
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd VectaEngine && swift test --filter NodeAlignmentTests`
Expected: PASS (6 테스트).

- [ ] **Step 5: 커밋**

```bash
cd VectaEngine && swift build && swift test
swift format --in-place --recursive Sources Tests
cd .. && git add VectaEngine/Sources/VectaEngine/Model/NodeAlignment.swift \
  VectaEngine/Sources/VectaEngine/State/DocumentStore+Align.swift \
  VectaEngine/Tests/VectaEngineTests/NodeAlignmentTests.swift
git commit -m "feat: 정렬 6종 엔진 연산 (좌/중앙x/우/상/중간y/하)"
```

---

### Task 4: 정렬 UI (인스펙터)

**Files:**
- Modify: `VectaApp/Sources/Panels/InspectorView.swift`

- [ ] **Step 1: 인스펙터 AlignSection 추가**

`InspectorView.body`의 `PathfinderSection(store: store)` 다음 줄에 추가:

```swift
          PathfinderSection(store: store)
          Divider()
          AlignSection(store: store)
```

같은 파일 맨 아래에 섹션 뷰 추가:

```swift
/// 정렬 6종 — 선택된 노드 2개 이상에서 활성화 (스펙 §8).
struct AlignSection: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("정렬").font(.headline)
      HStack(spacing: 6) {
        button("왼쪽 정렬", systemName: "align.horizontal.left") {
          store.alignSelection(edge: .left)
        }
        button("가로 가운데 정렬", systemName: "align.horizontal.center") {
          store.alignSelection(edge: .centerHorizontal)
        }
        button("오른쪽 정렬", systemName: "align.horizontal.right") {
          store.alignSelection(edge: .right)
        }
      }
      HStack(spacing: 6) {
        button("위 정렬", systemName: "align.vertical.top") {
          store.alignSelection(edge: .top)
        }
        button("세로 가운데 정렬", systemName: "align.vertical.center") {
          store.alignSelection(edge: .centerVertical)
        }
        button("아래 정렬", systemName: "align.vertical.bottom") {
          store.alignSelection(edge: .bottom)
        }
      }
    }
    .disabled(store.selection.count < 2)
  }

  private func button(
    _ label: String, systemName: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.bordered)
    .help(label)
    .accessibilityLabel(label)
  }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 수동 GUI 체크리스트 (사용자 수행)**

`make run` 후:
- 도형 3개 흩뿌리고 모두 선택 → "정렬" 6버튼 활성화
- 왼쪽/오른쪽/위/아래/가로가운데/세로가운데 각 정렬 동작 확인
- 1개만 선택 시 비활성화, ⌘Z 1단계 되돌리기

- [ ] **Step 4: 커밋**

```bash
make build
swift format --in-place --recursive VectaApp/Sources
git add VectaApp/Sources/Panels/InspectorView.swift
git commit -m "feat: 정렬 6종 인스펙터 버튼 연결"
```

---

### Task 5: 클립보드 엔진 (직렬화 + 명령)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/NodeClipboard.swift`
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore+Clipboard.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/NodeClipboardTests.swift`

- [ ] **Step 1: 실패 테스트 작성**

`VectaEngine/Tests/VectaEngineTests/NodeClipboardTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(_ frame: CGRect) -> PathNode {
  PathNode(path: .rectangle(frame), style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(nodes: [Node]) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document)
}

@Test func withFreshIDsChangesAllIDs() {
  let inner = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let group = GroupNode(children: [.path(inner)])
  let original = Node.group(group)
  let copy = original.withFreshIDs()
  #expect(copy.id != original.id)
  guard case .group(let copiedGroup) = copy else {
    Issue.record("그룹이 아님")
    return
  }
  #expect(copiedGroup.children[0].id != inner.id)
}

@Test func nodeClipboardRoundTripsThroughData() {
  let a = Node.path(rect(CGRect(x: 5, y: 5, width: 20, height: 20)))
  let data = NodeClipboard.encode([a])
  #expect(data != nil)
  let decoded = NodeClipboard.decode(data!)
  #expect(decoded == [a])
}

@Test func decodeReturnsNilForGarbage() {
  let garbage = Data("not json".utf8)
  #expect(NodeClipboard.decode(garbage) == nil)
}

@Test @MainActor func copyableSelectionReturnsSelectedNodesInZOrder() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let b = rect(CGRect(x: 20, y: 0, width: 10, height: 10))
  let c = rect(CGRect(x: 40, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a), .path(b), .path(c)])
  store.select([c.id, a.id])  // 선택 순서와 무관하게 z-순서로
  let nodes = store.copyableSelection()
  #expect(nodes.map(\.id) == [a.id, c.id])
}

@Test @MainActor func pasteNodesAddsFreshIDsWithOffsetAndSelects() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a)])
  let pasted = Node.path(rect(CGRect(x: 0, y: 0, width: 10, height: 10)))
  store.pasteNodes([pasted])
  #expect(store.document.layers[0].nodes.count == 2)
  let added = store.document.layers[0].nodes[1]
  #expect(added.id != pasted.id)  // 새 ID
  #expect(abs(added.bounds.minX - 10) < 0.5)  // +10 오프셋
  #expect(abs(added.bounds.minY - 10) < 0.5)
  #expect(store.selection == [added.id])
}

@Test @MainActor func pasteNodesIgnoresEmpty() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a)])
  store.pasteNodes([])
  #expect(store.document.layers[0].nodes.count == 1)
}

@Test @MainActor func duplicateSelectionAddsOffsetCopyOfSelection() {
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  let b = rect(CGRect(x: 50, y: 0, width: 10, height: 10))
  let store = makeStore(nodes: [.path(a), .path(b)])
  store.select([a.id, b.id])
  store.duplicateSelection()
  #expect(store.document.layers[0].nodes.count == 4)
  // 새로 추가된 2개가 선택됨, 원본 ID와 겹치지 않음.
  #expect(store.selection.count == 2)
  #expect(store.selection.isDisjoint(with: [a.id, b.id]))
}

@Test @MainActor func duplicateIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(CGRect(x: 0, y: 0, width: 10, height: 10))
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [.path(a)]
  let store = DocumentStore(document: document) { undoManager }
  store.select([a.id])
  store.duplicateSelection()
  undoManager.undo()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id])
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd VectaEngine && swift test --filter NodeClipboardTests`
Expected: 컴파일 실패 — `withFreshIDs`, `NodeClipboard`, `copyableSelection`, `pasteNodes`, `duplicateSelection` 미정의.

- [ ] **Step 3: 클립보드 직렬화 + Node.withFreshIDs 구현**

`VectaEngine/Sources/VectaEngine/Model/NodeClipboard.swift`:

```swift
import Foundation

/// 노드 클립보드 직렬화 (스펙 §8). 엔진은 AppKit 비의존이므로 NSPasteboard
/// I/O는 앱이 담당하고, 여기서는 `[Node]` ↔ `Data`(JSON)만 다룬다.
public enum NodeClipboard {
  /// 앱이 NSPasteboard 커스텀 타입을 만들 때 쓰는 식별자.
  public static let pasteboardType = "dev.vecta.nodes"

  public static func encode(_ nodes: [Node]) -> Data? {
    try? JSONEncoder().encode(nodes)
  }

  public static func decode(_ data: Data) -> [Node]? {
    try? JSONDecoder().decode([Node].self, from: data)
  }
}

extension Node {
  /// 모든 NodeID를 새로 발급한 복제본 (그룹 자식까지 재귀). 붙여넣기·복제에서
  /// 원본과의 ID 충돌을 막는다. 지오메트리·스타일·transform은 그대로 유지.
  public func withFreshIDs() -> Node {
    switch self {
    case .path(let node):
      return .path(
        PathNode(
          path: node.path, style: node.style,
          transform: node.transform, fillRule: node.fillRule))
    case .group(let node):
      return .group(
        GroupNode(
          children: node.children.map { $0.withFreshIDs() },
          clipPath: node.clipPath, transform: node.transform))
    case .text(let node):
      return .text(
        TextNode(
          string: node.string, fontName: node.fontName, fontSize: node.fontSize,
          fill: node.fill, position: node.position, transform: node.transform))
    case .image(let node):
      return .image(
        ImageNode(
          imageData: node.imageData, frame: node.frame, transform: node.transform))
    }
  }
}
```

`VectaEngine/Sources/VectaEngine/State/DocumentStore+Clipboard.swift`:

```swift
import CoreGraphics

/// 복사/붙여넣기/복제 명령 (스펙 §8). 직렬화는 NodeClipboard, NSPasteboard
/// I/O는 앱이 담당하고, 스토어는 선택 수집·노드 추가만 한다.
extension DocumentStore {
  /// 선택된 최상위 노드를 문서 z-순서로 반환 (복사·잘라내기·복제용).
  public func copyableSelection() -> [Node] {
    let ids = selection
    var result: [Node] = []
    for layer in document.layers {
      for node in layer.nodes where ids.contains(node.id) {
        result.append(node)
      }
    }
    return result
  }

  /// 노드들을 새 ID·오프셋으로 활성 레이어에 추가하고 선택한다 (붙여넣기).
  /// 활성 레이어가 숨김/잠금이면 조용히 무시한다 (생성 경로와 동일 규칙).
  public func pasteNodes(_ nodes: [Node], offset: CGVector = CGVector(dx: 10, dy: 10)) {
    guard !nodes.isEmpty else { return }
    let index = activeLayerIndex
    guard document.layers.indices.contains(index) else { return }
    let layer = document.layers[index]
    guard layer.isVisible, !layer.isLocked else { return }
    let fresh = nodes.map { NodeTransformer.translated($0.withFreshIDs(), by: offset) }
    apply(actionName: "붙여넣기") { $0.layers[index].nodes.append(contentsOf: fresh) }
    select(Set(fresh.map(\.id)))
  }

  /// 선택을 그 자리에서 오프셋 복제한다 — 클립보드를 거치지 않는다.
  public func duplicateSelection() {
    apply(actionName: "복제") { document in
      let index = activeLayerIndex
      guard document.layers.indices.contains(index) else { return }
      let layer = document.layers[index]
      guard layer.isVisible, !layer.isLocked else { return }
      let copies = copyableSelection().map {
        NodeTransformer.translated($0.withFreshIDs(), by: CGVector(dx: 10, dy: 10))
      }
      guard !copies.isEmpty else { return }
      document.layers[index].nodes.append(contentsOf: copies)
      pendingSelection = Set(copies.map(\.id))
    }
    if let pending = pendingSelection {
      select(pending)
      pendingSelection = nil
    }
  }
}
```

> **참고:** `duplicateSelection`은 단일 undo 단계여야 하므로 `apply` 1회 안에서
> 추가하고, 새 선택 ID는 `pendingSelection`으로 전달한다. `DocumentStore`에
> 다음 저장 프로퍼티를 추가한다 (`DocumentStore.swift`의 `transientBase`
> 선언 다음 줄):
>
> ```swift
>   private var pendingSelection: Set<NodeID>?
> ```
>
> `pasteNodes`는 `apply` 밖에서 `fresh`를 알 수 있어 직접 `select`하지만,
> `duplicateSelection`은 `copyableSelection()`이 `apply` 클로저 안의 최신
> 문서가 아니라 현재 `self`를 읽으므로(복사 대상은 변경 전 선택) 동일 패턴이
> 가능하다. 단 새 ID를 클로저 밖으로 빼기 위해 `pendingSelection`을 쓴다.

- [ ] **Step 4: DocumentStore에 pendingSelection 프로퍼티 추가**

`VectaEngine/Sources/VectaEngine/State/DocumentStore.swift:18`의 `private var transientBase: VectorDocument?` 다음에 추가:

```swift
  private var transientBase: VectorDocument?
  /// 복제 등 apply 클로저 내부에서 만든 새 노드의 선택 ID를 클로저 밖으로
  /// 전달하는 임시 버퍼.
  private var pendingSelection: Set<NodeID>?
```

`pendingSelection`은 `DocumentStore+Clipboard.swift`에서 접근하므로 `private`
대신 같은 모듈 확장에서 보이도록 `internal`로 둔다 (접근 제어자 생략 = internal):

```swift
  var pendingSelection: Set<NodeID>?
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `cd VectaEngine && swift test --filter NodeClipboardTests`
Expected: PASS (9 테스트).

- [ ] **Step 6: 커밋**

```bash
cd VectaEngine && swift build && swift test
swift format --in-place --recursive Sources Tests
cd .. && git add VectaEngine/Sources/VectaEngine/Model/NodeClipboard.swift \
  VectaEngine/Sources/VectaEngine/State/DocumentStore+Clipboard.swift \
  VectaEngine/Sources/VectaEngine/State/DocumentStore.swift \
  VectaEngine/Tests/VectaEngineTests/NodeClipboardTests.swift
git commit -m "feat: 복사/붙여넣기/복제 엔진 직렬화·명령"
```

---

### Task 6: 클립보드 UI (NSPasteboard + 편집 메뉴)

**Files:**
- Modify: `VectaApp/Sources/Document/VectaDocument.swift`
- Modify: `VectaApp/Sources/MainMenuBuilder.swift:73-87` (editMenu)

- [ ] **Step 1: VectaDocument 클립보드 액션 추가**

`VectaApp/Sources/Document/VectaDocument.swift`의 패스파인더 액션(Task 2에서 추가) 다음에 추가:

```swift
  // MARK: - 편집 메뉴 클립보드 액션

  @objc func copy(_ sender: Any?) {
    writeSelectionToPasteboard()
  }

  @objc func cut(_ sender: Any?) {
    guard writeSelectionToPasteboard() else { return }
    store.deleteSelection()
  }

  @objc func paste(_ sender: Any?) {
    let type = NSPasteboard.PasteboardType(NodeClipboard.pasteboardType)
    guard let data = NSPasteboard.general.data(forType: type),
      let nodes = NodeClipboard.decode(data)
    else { return }
    store.pasteNodes(nodes)
  }

  @objc func duplicate(_ sender: Any?) {
    store.duplicateSelection()
  }

  /// 선택 노드를 NSPasteboard 커스텀 타입으로 쓴다. 빈 선택이면 false.
  @discardableResult
  private func writeSelectionToPasteboard() -> Bool {
    let nodes = store.copyableSelection()
    guard !nodes.isEmpty, let data = NodeClipboard.encode(nodes) else { return false }
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(NodeClipboard.pasteboardType))
    return true
  }
```

`validateUserInterfaceItem`의 `switch`에 분기 추가 (`default:` 위):

```swift
    case #selector(copy(_:)), #selector(cut(_:)), #selector(duplicate(_:)):
      return !store.selection.isEmpty
    case #selector(paste(_:)):
      let type = NSPasteboard.PasteboardType(NodeClipboard.pasteboardType)
      return NSPasteboard.general.data(forType: type) != nil
```

- [ ] **Step 2: 편집 메뉴에 클립보드 항목 추가**

`VectaApp/Sources/MainMenuBuilder.swift`의 `editMenu()`에서 `모두 선택` 항목 다음·`return menu` 앞에 추가:

```swift
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "잘라내기",
      action: #selector(VectaDocument.cut(_:)), keyEquivalent: "x")
    menu.addItem(
      withTitle: "복사",
      action: #selector(VectaDocument.copy(_:)), keyEquivalent: "c")
    menu.addItem(
      withTitle: "붙여넣기",
      action: #selector(VectaDocument.paste(_:)), keyEquivalent: "v")
    menu.addItem(
      withTitle: "복제",
      action: #selector(VectaDocument.duplicate(_:)), keyEquivalent: "d")
```

- [ ] **Step 3: 빌드 확인**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 수동 GUI 체크리스트 (사용자 수행)**

`make run` 후:
- 도형 선택 → ⌘C → ⌘V: +10,+10 오프셋 복제본이 추가되고 선택됨
- ⌘X: 잘라내기 후 ⌘V로 복원
- ⌘D: 제자리 복제, ⌘Z 1단계 되돌리기
- 빈 선택 시 복사/잘라내기/복제 메뉴 비활성화, 클립보드 비어 있으면 붙여넣기 비활성화
- 그룹 복제 시 자식까지 독립 복제(원본 편집이 복제본에 영향 없음)

- [ ] **Step 5: 커밋**

```bash
make build
swift format --in-place --recursive VectaApp/Sources
git add VectaApp/Sources/Document/VectaDocument.swift \
  VectaApp/Sources/MainMenuBuilder.swift
git commit -m "feat: 복사/잘라내기/붙여넣기/복제 메뉴·NSPasteboard 연결"
```

---

### Task 7: 회귀 검증 + README + PR

**Files:**
- Modify: `README.md:35`

- [ ] **Step 1: 전체 엔진 회귀**

Run: `cd VectaEngine && swift build && swift test`
Expected: 전체 PASS (기존 362 + 신규 23 = 385 테스트). 실패 시 원인 수정 후 analyze부터 재수행.

- [ ] **Step 2: 앱 빌드 회귀**

Run: `make build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: README 갱신**

`README.md:35`의 라인을 교체:

```markdown
- [ ] M5 텍스트·이미지·패스파인더·정렬
```

→

```markdown
- [x] M5a 선택 조작: 패스파인더 4종·정렬 6종·복사/붙여넣기/복제
- [ ] M5b 텍스트 도구 (인라인 입력)
- [ ] M5c 이미지 배치 (Place Image…)
```

- [ ] **Step 4: 포맷 + 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
swift format --in-place --recursive VectaApp/Sources
git add README.md
git commit -m "docs: M5a 완료 — 선택 조작 (패스파인더·정렬·클립보드)"
```

- [ ] **Step 5: PR 생성**

```bash
git push -u origin <branch>
gh pr create --title "M5a: 선택 조작 — 패스파인더·정렬·복사/붙여넣기" \
  --body "Closes #6

## 변경
- 패스파인더 4종 (합치기·빼기·교차·제외): CGPath 불린 + normalized 전처리, 결과 PathNode 1개 치환(스타일 최하단)
- 정렬 6종 (좌/중앙x/우/상/중간y/하): 선택 바운드 기준
- 복사/잘라내기/붙여넣기/복제 (⌘C/⌘X/⌘V/⌘D): 엔진 Codable 직렬화 + 앱 NSPasteboard
- 인스펙터 패스파인더·정렬 버튼, 오브젝트/편집 메뉴 연결

## 테스트
- 엔진 385 테스트 통과 (신규 23)
- 앱 빌드 성공, 수동 GUI 체크리스트 완료"
```

---

## Self-Review

**1. 스펙 커버리지:**
- 패스파인더 4종 (CGPath union/subtract/intersect/symmetricDifference + normalized 전처리) → Task 1 ✓
- 결과 PathNode 1개 치환(스타일 최하단) → Task 1 `combineSelectedPaths` ✓
- 인스펙터 4버튼 + Object 메뉴 → Task 2 ✓
- 정렬 6종, 인스펙터 6버튼 → Task 3·4 ✓
- 복사/잘라내기/붙여넣기/복제 ⌘C/⌘X/⌘V/⌘D → Task 5·6 ✓
- 텍스트 도구·이미지 배치 → M5b(#21)·M5c(#22)로 분리, 본 계획 범위 밖 ✓

**2. 플레이스홀더 스캔:** 모든 코드 스텝에 실제 구현 포함, "TODO/적절한 처리" 없음 ✓

**3. 타입 일관성:**
- `PathfinderOperation`(.unite/.subtract/.intersect/.exclude) — Task 1 정의, Task 2 사용 일치 ✓
- `AlignEdge`(.left/.centerHorizontal/.right/.top/.centerVertical/.bottom) — Task 3 정의, Task 4 사용 일치 ✓
- `combinablePathCount` — Task 1 정의, Task 2 validate 사용 ✓
- `NodeClipboard.pasteboardType`/`encode`/`decode`, `Node.withFreshIDs()`, `copyableSelection`/`pasteNodes`/`duplicateSelection` — Task 5 정의, Task 6 사용 일치 ✓
- `pendingSelection` — Task 5 Step 4에서 internal 선언, `DocumentStore+Clipboard.swift`에서 접근 ✓
- 색 타입은 `RGBA`(`RGBA(red:green:blue:alpha:)`), 정적 상수는 `.black`/`.white`만 존재 — 테스트는 `red`/`blue`를 `RGBA(red:1,green:0,blue:0)` 등으로 직접 정의(Task 1 헬퍼)했고, `Style(fill: .color(...))`·`Paint.color(RGBA)`는 `Style.swift`/`RGBA.swift` 확인 완료 ✓
