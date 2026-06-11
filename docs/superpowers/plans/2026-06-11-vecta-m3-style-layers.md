# Vecta M3 — 스타일·구조 (인스펙터, 레이어 패널, 그라디언트) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 그라디언트 렌더링, 우측 인스펙터(면/선/불투명도/변환 수치), 레이어 패널(목록/눈/자물쇠/이름/순서/활성 레이어), 그룹/해제(⌘G/⇧⌘G)·앞뒤 순서(⌘]/⌘[)를 추가하고 M2b 이월 부채(활성 레이어, 펜 이중 이벤트 가드, 직접 선택 그룹 내부 진입)를 해소한다. (GitHub 이슈 #4, PR은 `Closes #4`)

**Architecture:** 모든 신규 로직(그라디언트 렌더·기하, 그룹/해제/순서 모델 연산, 스타일·변환·레이어 명령)은 VectaEngine에 두고 헤드리스 테스트한다. DocumentStore에 명령 표면(extension 파일들)을 추가해 SwiftUI 패널·메뉴가 단일 경로(`apply` = undo 1단계)로 모델을 변경한다. 앱 레이어는 NSHostingView로 우측 패널(인스펙터+레이어)을 도킹하고 Object 메뉴를 응답 체인으로 연결하는 얇은 셸만 추가한다.

**Tech Stack:** Swift 6.3 (언어 모드 v5), Swift Testing, CoreGraphics(CGGradient), SwiftUI/AppKit 셸, XcodeGen. 배포 타깃 macOS 14.0.

**참조:** 스펙 `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` §4(모델)·§7(도구)·§8(패널·메뉴)·§9(undo), 이슈 #4 본문+M2b 이월 부채 코멘트, M2a/M2b 계획(컨벤션·transient 계약).

---

## 커밋 규칙 (전역 규칙 — M1/M2와 동일)

매 커밋 전: ① `cd VectaEngine && swift build`(앱 변경 시 xcodebuild) → ② `swift test` → ③ `swift format --in-place --recursive Sources Tests`(앱은 `VectaApp/Sources`) → ④ commit. 한국어 메시지+접두사, Co-Authored-By 금지. 테스트 실패 시 수정 후 ①부터 재수행.

## 결정 기록 (이 계획에서 확정하는 사항)

| 결정 | 근거 |
|---|---|
| 그라디언트는 `CGGradient`(drawLinear/RadialGradient)로 렌더 | 스펙 §6의 `CGShading` 표기는 axial/radial 셰이딩 의도. CGShading+CGFunction은 스톱 보간을 수동 구현해야 하고 unsafe 포인터 콜백이 필요. CGGradient는 스톱 배열을 네이티브 지원하며 PDF 컨텍스트에 동일하게 shading으로 기록됨. Task 1에서 스펙 표기도 갱신 |
| 활성 레이어는 `DocumentStore.activeLayerID`(NodeID 기반, 인덱스 폴백 0) | 레이어 순서 변경/삭제에도 ID는 안정적. ToolContext는 store를 이미 노출하므로 별도 필드 불필요 (이월 부채의 "ToolContext에 activeLayerIndex" 의도 충족) |
| 잠긴/숨긴 활성 레이어에는 도형/펜 생성 무시 | Illustrator 동작. 조용한 no-op (undo 미등록) |
| 직접 선택 재진입 시 편집 대상 초기화 유지 (M2b 현행) | 이월 부채의 UX 결정 항목. 도구 전환 = 작업 단위 종료로 본다 |
| 그룹 해제 시 `clipPath` 폐기 | Illustrator의 클리핑 마스크 해제와 동일 의미. M3 네이티브 그룹은 클립을 만들지 않으므로 실사용 영향 없음 (M4 임포트 그룹에서 재논의) |
| 회전 수치 입력: 단일 선택은 절대각(atan2 추출) 표시·입력, 다중 선택은 0 표시·입력값=델타 | 다중 선택의 "공통 절대각"은 정의 불가. 적용은 항상 선택 바운드 중심 기준 |
| ColorPicker 변경은 변경당 undo 1단계 (연속 세션 미지원) | SwiftUI ColorPicker는 편집 세션 API가 없음. 불투명도·스톱 위치 Slider는 transient로 드래그=undo 1단계 보장 |
| 레이어 패널에 추가(+)/삭제(−) 버튼 포함 (이슈 목록 외) | 단일 레이어 문서에서는 순서 변경·활성 레이어가 무의미 — 패널이 동작하려면 최소한의 생성 수단 필요. 최소 1개 레이어 불변식 유지 |
| 레이어 패널의 노드 트리(스펙 §8)는 M3 비목표 | 이슈 #4 작업 목록 기준(목록/눈/자물쇠/이름/순서/활성). PR에서 이월 기록 |
| 패스파인더·정렬 버튼은 M5 (스펙 §12) | 인스펙터에는 면/선/그라디언트/불투명도/변환만 |

## 파일 구조 (M3 추가/변경분)

```
VectaEngine/Sources/VectaEngine/
├── Rendering/SceneRenderer.swift     (수정)  # 그라디언트 fill 렌더 (CGGradient)
├── Geometry/
│   ├── GradientGeometry.swift        (생성)  # 각도↔선분 매핑, 기본 그라디언트 팩토리
│   ├── HitTesting.swift              (수정)  # topmostPathNodeID — 그룹 내부 진입
│   └── NodeTransformer.swift         (수정)  # applying 공개, Node.transform/rotationDegrees
├── Model/VectorDocument+Editing.swift (수정) # 그룹/해제/순서, 깊은 패스 조회/변경
├── State/
│   ├── DocumentStore.swift           (수정)  # activeLayerID, appendNodeToActiveLayer
│   ├── DocumentStore+Structure.swift (생성)  # 그룹/해제/앞뒤 순서 명령
│   ├── DocumentStore+Layers.swift    (생성)  # 레이어 추가/삭제/이름/눈/잠금/순서 명령
│   ├── DocumentStore+Styling.swift   (생성)  # selectionPathStyle, 스타일 일괄 변경
│   └── DocumentStore+Transform.swift (생성)  # X/Y/W/H/회전 수치 명령
└── Tools/
    ├── ShapeTool.swift               (수정)  # 활성 레이어 사용
    ├── PenTool.swift                 (수정)  # 활성 레이어 + 이중 mouseDown 가드
    └── DirectSelectTool.swift        (수정)  # 그룹 내부 진입 (월드 변환)

VectaApp/Sources/
├── Document/VectaDocument.swift      (수정)  # Object 메뉴 액션, 우측 패널 도킹
├── MainMenuBuilder.swift             (수정)  # 오브젝트 메뉴 (⌘G/⇧⌘G/⌘]/⌘[)
└── Panels/
    ├── RGBA+Color.swift              (생성)  # RGBA ↔ SwiftUI Color
    ├── LayerPanelView.swift          (생성)
    ├── InspectorView.swift           (생성)  # 본체 + 불투명도 + 변환 섹션
    ├── FillSection.swift             (생성)  # 면 + 그라디언트 에디터
    ├── StrokeSection.swift           (생성)
    └── SidePanelView.swift           (생성)  # 인스펙터/레이어 수직 분할 컨테이너

docs/superpowers/specs/...design.md   (수정)  # §6 CGShading → CGGradient 표기 (Task 1)
README.md                             (수정)  # M3 완료 (Task 13)
```

핵심 계약 (기존 — 신규 코드가 의존):
- 모든 모델 변경은 `DocumentStore.apply(actionName:_:)` 1회 = undo 1단계. 드래그 미리보기는 `beginTransient → updateTransient → commitTransient/cancelTransient`.
- 모델 top-left 좌표. 그라디언트 `start/end`는 **객체 로컬 좌표** (스펙 §4).
- `SceneRenderer`는 캔버스와 PDF 익스포트가 공유 — 그라디언트 렌더 구현만으로 .ai 출력에도 반영된다.
- 테스트 베이스라인: 엔진 142개 그린.

---

### Task 1: SceneRenderer 그라디언트 렌더링 (CGGradient)

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Rendering/SceneRenderer.swift`
- Modify: `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` (§6 표기)
- Test: `VectaEngine/Tests/VectaEngineTests/SceneRendererTests.swift` (추가)

- [ ] **Step 1: 실패하는 테스트 작성** — `SceneRendererTests.swift` 끝에 추가

```swift
// MARK: - 그라디언트 (M3)

private func documentWithGradientRect(_ fill: Paint) -> VectorDocument {
  var document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 80, height: 80)),
    style: Style(fill: fill))
  document.layers[0].nodes = [.path(node)]
  return document
}

private let redToBlue = [
  GradientStop(location: 0, color: RGBA(red: 1, green: 0, blue: 0)),
  GradientStop(location: 1, color: RGBA(red: 0, green: 0, blue: 1)),
]

@Test func linearGradientInterpolatesAndClipsToPath() {
  let gradient = Gradient(
    stops: redToBlue, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  let left = pixelColor(x: 12, y: 50, in: context)
  #expect(left.red > 230)
  #expect(left.blue < 25)
  let right = pixelColor(x: 88, y: 50, in: context)
  #expect(right.blue > 230)
  #expect(right.red < 25)
  let middle = pixelColor(x: 50, y: 50, in: context)
  #expect(middle.red > 100 && middle.red < 160)
  #expect(middle.blue > 100 && middle.blue < 160)
  // 패스 밖(그라디언트 연장선 위)은 클립으로 비어 있어야 한다
  #expect(pixelColor(x: 5, y: 50, in: context).alpha == 0)
}

@Test func linearGradientExtendsBeyondEndpoints() {
  // 선분이 패스보다 짧아도 양 끝 색으로 연장된다 (drawsBefore/AfterStartLocation)
  let gradient = Gradient(
    stops: redToBlue, start: CGPoint(x: 40, y: 50), end: CGPoint(x: 60, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 12, y: 50, in: context).red > 230)
  #expect(pixelColor(x: 88, y: 50, in: context).blue > 230)
}

@Test func radialGradientShadesFromCenter() {
  // start = 중심, end = 원주 위 한 점 (반지름 40)
  let whiteToBlack = [
    GradientStop(location: 0, color: .white),
    GradientStop(location: 1, color: .black),
  ]
  let gradient = Gradient(
    stops: whiteToBlack, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 90, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.radialGradient(gradient)), size: CGSize(width: 100, height: 100))
  let center = pixelColor(x: 50, y: 50, in: context)
  #expect(center.red > 230)
  let nearEdge = pixelColor(x: 88, y: 50, in: context)
  #expect(nearEdge.red < 40)
}

@Test func singleStopGradientRendersSolid() {
  let gradient = Gradient(
    stops: [GradientStop(location: 0, color: RGBA(red: 0, green: 1, blue: 0))],
    start: CGPoint(x: 10, y: 50), end: CGPoint(x: 90, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  let inside = pixelColor(x: 50, y: 50, in: context)
  #expect(inside.green > 230)
  #expect(inside.red < 25)
}

@Test func degenerateGradientLineRendersFirstStopSolid() {
  // start == end (길이 0 선분) → 첫 스톱 단색
  let gradient = Gradient(
    stops: redToBlue, start: CGPoint(x: 50, y: 50), end: CGPoint(x: 50, y: 50))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 50, y: 50, in: context).red > 230)
}

@Test func emptyStopsGradientDrawsNothing() {
  let gradient = Gradient(stops: [], start: .zero, end: CGPoint(x: 100, y: 0))
  let context = renderToBitmap(
    documentWithGradientRect(.linearGradient(gradient)), size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 50, y: 50, in: context).alpha == 0)
}
```

- [ ] **Step 2: 실패 확인** — `cd VectaEngine && swift test` → 신규 6개 FAIL (그라디언트 케이스가 `break`로 아무것도 안 그림)

- [ ] **Step 3: 구현** — `SceneRenderer.swift`의 `renderFill` 그라디언트 케이스 교체 + 헬퍼 추가

`renderFill` 교체:

```swift
  private static func renderFill(_ paint: Paint, path: BezierPath, in context: CGContext) {
    switch paint {
    case .color(let color):
      context.setFillColor(color.cgColor)
      // fillPath()/strokePath()는 current path를 소비하므로 각 함수가 독립적으로 path를 추가해야 한다.
      context.addPath(path.cgPath)
      context.fillPath()
    case .linearGradient(let gradient):
      renderGradientFill(gradient, isRadial: false, path: path, in: context)
    case .radialGradient(let gradient):
      renderGradientFill(gradient, isRadial: true, path: path, in: context)
    }
  }

  /// 패스를 클립한 뒤 그라디언트를 그린다. 스펙 §4 — start/end는 객체 로컬
  /// 좌표, radial은 start=중심·end=원주 위 한 점. 퇴화 케이스(스톱 1개,
  /// 길이 0 선분)는 첫 스톱 단색으로, 스톱 0개는 그리지 않는다.
  private static func renderGradientFill(
    _ gradient: Gradient, isRadial: Bool, path: BezierPath, in context: CGContext
  ) {
    guard let firstStop = gradient.stops.first else { return }
    if gradient.stops.count == 1 || gradient.start == gradient.end {
      context.setFillColor(firstStop.color.cgColor)
      context.addPath(path.cgPath)
      context.fillPath()
      return
    }
    guard let cgGradient = gradient.cgGradient else { return }
    context.saveGState()
    context.addPath(path.cgPath)
    context.clip()
    let options: CGGradientDrawingOptions = [
      .drawsBeforeStartLocation, .drawsAfterEndLocation,
    ]
    if isRadial {
      let radius = hypot(
        gradient.end.x - gradient.start.x, gradient.end.y - gradient.start.y)
      context.drawRadialGradient(
        cgGradient, startCenter: gradient.start, startRadius: 0,
        endCenter: gradient.start, endRadius: radius, options: options)
    } else {
      context.drawLinearGradient(
        cgGradient, start: gradient.start, end: gradient.end, options: options)
    }
    context.restoreGState()
  }
```

같은 파일 하단에 extension 추가:

```swift
extension Gradient {
  /// 위치 순 정렬된 스톱으로 CGGradient를 만든다 (스톱 2개 미만이면 nil).
  fileprivate var cgGradient: CGGradient? {
    guard stops.count >= 2 else { return nil }
    let sorted = stops.sorted { $0.location < $1.location }
    return CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: sorted.map(\.color.cgColor) as CFArray,
      locations: sorted.map { CGFloat($0.location) })
  }
}
```

`hypot` 사용을 위해 파일 상단 import에 `import Foundation` 추가 (CoreGraphics만으로 부족하면).

- [ ] **Step 4: 스펙 표기 갱신** — 스펙 §6의 줄

```
   - 그라디언트: 패스를 클립 → `CGShading`(axial/radial) 드로우
```

을 다음으로 교체:

```
   - 그라디언트: 패스를 클립 → `CGGradient`(axial/radial) 드로우
     (M3 결정: CGShading+CGFunction은 스톱 보간 수동 구현이 필요해
     CGGradient 채택 — PDF에는 동일하게 shading으로 기록됨)
```

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (148개)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 그라디언트 fill 렌더링 — CGGradient 선형·원형"
```

---

### Task 2: GradientGeometry — 각도↔선분 매핑 + 기본 그라디언트

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Geometry/GradientGeometry.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/GradientGeometryTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

private func expectClose(
  _ point: CGPoint, _ expected: CGPoint,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(abs(point.x - expected.x) < 0.0001, sourceLocation: sourceLocation)
  #expect(abs(point.y - expected.y) < 0.0001, sourceLocation: sourceLocation)
}

@Test func angleZeroSpansBoundsLeftToRight() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let line = GradientGeometry.line(angleDegrees: 0, in: bounds)
  expectClose(line.start, CGPoint(x: 0, y: 25))
  expectClose(line.end, CGPoint(x: 100, y: 25))
}

@Test func angleNinetySpansBoundsTopToBottom() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let line = GradientGeometry.line(angleDegrees: 90, in: bounds)
  expectClose(line.start, CGPoint(x: 50, y: 0))
  expectClose(line.end, CGPoint(x: 50, y: 50))
}

@Test func angleRoundTripsThroughLine() {
  let bounds = CGRect(x: 10, y: 20, width: 80, height: 60)
  let line = GradientGeometry.line(angleDegrees: 30, in: bounds)
  let gradient = Gradient(stops: [], start: line.start, end: line.end)
  #expect(abs(GradientGeometry.angleDegrees(of: gradient) - 30) < 0.0001)
}

@Test func zeroLengthGradientAngleIsZero() {
  let gradient = Gradient(stops: [], start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5))
  #expect(GradientGeometry.angleDegrees(of: gradient) == 0)
}

@Test func defaultLinearPreservesBaseColorAndSpansBounds() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let red = RGBA(red: 1, green: 0, blue: 0)
  let gradient = Gradient.defaultLinear(from: red, in: bounds)
  #expect(gradient.stops.count == 2)
  #expect(gradient.stops[0].color == red)
  #expect(gradient.stops[0].location == 0)
  #expect(gradient.stops[1].color == .white)
  #expect(gradient.stops[1].location == 1)
  expectClose(gradient.start, CGPoint(x: 0, y: 25))
  expectClose(gradient.end, CGPoint(x: 100, y: 25))
}

@Test func defaultRadialCentersInBounds() {
  let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
  let gradient = Gradient.defaultRadial(from: .black, in: bounds)
  expectClose(gradient.start, CGPoint(x: 50, y: 25))
  expectClose(gradient.end, CGPoint(x: 100, y: 50))
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`cannot find 'GradientGeometry'`)

- [ ] **Step 3: 구현** — `Geometry/GradientGeometry.swift`

```swift
import CoreGraphics

/// 그라디언트 선분 ↔ 각도 매핑 (인스펙터 각도 편집용). 각도는 도 단위,
/// 모델 y-아래 좌표계 기준 0° = 오른쪽(→), 90° = 아래(↓), 시계 방향 양수.
public enum GradientGeometry {
  /// bounds 중심을 지나고 양 끝이 bounds 경계에 내접하는 angle 방향 선분.
  public static func line(
    angleDegrees: Double, in bounds: CGRect
  ) -> (start: CGPoint, end: CGPoint) {
    let radians = angleDegrees * .pi / 180
    let direction = CGVector(dx: cos(radians), dy: sin(radians))
    // bounds를 방향 벡터에 사영한 반길이 — 끝점이 경계에 닿는다.
    let halfLength =
      (abs(direction.dx) * bounds.width + abs(direction.dy) * bounds.height) / 2
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    return (
      CGPoint(
        x: center.x - direction.dx * halfLength,
        y: center.y - direction.dy * halfLength),
      CGPoint(
        x: center.x + direction.dx * halfLength,
        y: center.y + direction.dy * halfLength)
    )
  }

  /// 그라디언트 선분의 각도 (도). 길이 0이면 0.
  public static func angleDegrees(of gradient: Gradient) -> Double {
    let dx = gradient.end.x - gradient.start.x
    let dy = gradient.end.y - gradient.start.y
    guard dx != 0 || dy != 0 else { return 0 }
    return atan2(dy, dx) * 180 / .pi
  }
}

extension Gradient {
  /// 단색에서 전환할 때의 기본 선형 그라디언트 — 기존 색 → 흰색, 0°.
  /// bounds는 객체 로컬 패스 바운드 (그라디언트 좌표는 객체 로컬 — 스펙 §4).
  public static func defaultLinear(from color: RGBA, in bounds: CGRect) -> Gradient {
    let line = GradientGeometry.line(angleDegrees: 0, in: bounds)
    return Gradient(
      stops: [
        GradientStop(location: 0, color: color),
        GradientStop(location: 1, color: .white),
      ],
      start: line.start, end: line.end)
  }

  /// 기본 원형 그라디언트 — bounds 중심에서 우하단 모서리까지.
  public static func defaultRadial(from color: RGBA, in bounds: CGRect) -> Gradient {
    Gradient(
      stops: [
        GradientStop(location: 0, color: color),
        GradientStop(location: 1, color: .white),
      ],
      start: CGPoint(x: bounds.midX, y: bounds.midY),
      end: CGPoint(x: bounds.maxX, y: bounds.maxY))
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (154개)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 그라디언트 각도·선분 기하와 기본 그라디언트 팩토리"
```

---

### Task 3: 활성 레이어 + 도구 부채 해소 (layers[0] 제거, 펜 이중 다운 가드)

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/State/DocumentStore.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Tools/ShapeTool.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Tools/PenTool.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DocumentStoreActiveLayerTests.swift` (생성)
- Test: `VectaEngine/Tests/VectaEngineTests/ShapeToolTests.swift`, `PenToolTests.swift` (추가)

- [ ] **Step 1: 실패하는 테스트 작성** — `DocumentStoreActiveLayerTests.swift`

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@MainActor
private func makeTwoLayerStore() -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers.append(Layer(name: "레이어 2"))
  return DocumentStore(document: document)
}

private func redRect() -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
      style: Style(fill: .color(.black))))
}

@Test @MainActor func defaultActiveLayerIndexIsZero() {
  let store = makeTwoLayerStore()
  #expect(store.activeLayerIndex == 0)
}

@Test @MainActor func setActiveLayerByID() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  #expect(store.activeLayerIndex == 1)
}

@Test @MainActor func setActiveLayerIgnoresUnknownID() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: NodeID())
  #expect(store.activeLayerIndex == 0)
}

@Test @MainActor func activeLayerFallsBackWhenLayerRemoved() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  store.apply(actionName: "레이어 삭제") { $0.layers.remove(at: 1) }
  #expect(store.activeLayerIndex == 0)
}

@Test @MainActor func appendNodeGoesToActiveLayer() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  store.appendNodeToActiveLayer(redRect(), actionName: "도형 추가")
  #expect(store.document.layers[0].nodes.isEmpty)
  #expect(store.document.layers[1].nodes.count == 1)
}

@Test @MainActor func appendNodeIgnoredOnLockedLayer() {
  let store = makeTwoLayerStore()
  store.apply(actionName: "잠금") { $0.layers[0].isLocked = true }
  store.appendNodeToActiveLayer(redRect(), actionName: "도형 추가")
  #expect(store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func appendNodeIgnoredOnHiddenLayer() {
  let store = makeTwoLayerStore()
  store.apply(actionName: "숨김") { $0.layers[0].isVisible = false }
  store.appendNodeToActiveLayer(redRect(), actionName: "도형 추가")
  #expect(store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func loadResetsActiveLayer() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  store.load(.empty())
  #expect(store.activeLayerIndex == 0)
}
```

`ShapeToolTests.swift` 끝에 추가:

```swift
@Test @MainActor func shapeToolCommitsToActiveLayer() {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers.append(Layer(name: "레이어 2"))
  let store = DocumentStore(document: document)
  store.setActiveLayer(id: store.document.layers[1].id)
  let context = ToolContext(store: store)
  let tool = ShapeTool(shape: .rectangle)
  tool.mouseDown(CanvasEvent(point: CGPoint(x: 10, y: 10)), context: context)
  tool.mouseDragged(CanvasEvent(point: CGPoint(x: 60, y: 60)), context: context)
  tool.mouseUp(CanvasEvent(point: CGPoint(x: 60, y: 60)), context: context)
  #expect(store.document.layers[0].nodes.isEmpty)
  #expect(store.document.layers[1].nodes.count == 1)
}
```

`PenToolTests.swift` 끝에 추가:

```swift
@Test @MainActor func duplicateMouseDownWithoutUpAddsSingleAnchor() {
  let (context, tool, store) = makeContext()
  tool.mouseDown(at(10, 10), context: context)
  tool.mouseDown(at(10, 10), context: context)  // 이중 이벤트 (mouseUp 누락)
  tool.mouseUp(at(10, 10), context: context)
  tool.mouseDown(at(100, 10), context: context)
  tool.mouseUp(at(100, 10), context: context)
  #expect(tool.keyDown(.enter, context: context))
  guard case .path(let pathNode) = store.document.layers[0].nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  // 가드 없으면 (10,10) 앵커가 2개 → 세그먼트 3개
  #expect(pathNode.path.subpaths[0].segments.count == 2)
}

@Test @MainActor func penCommitsToActiveLayer() {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers.append(Layer(name: "레이어 2"))
  let store = DocumentStore(document: document)
  store.setActiveLayer(id: store.document.layers[1].id)
  let context = ToolContext(store: store)
  let tool = PenTool()
  for point in [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10)] {
    tool.mouseDown(CanvasEvent(point: point, hitTolerance: 4), context: context)
    tool.mouseUp(CanvasEvent(point: point, hitTolerance: 4), context: context)
  }
  #expect(tool.keyDown(.enter, context: context))
  #expect(store.document.layers[0].nodes.isEmpty)
  #expect(store.document.layers[1].nodes.count == 1)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`activeLayerIndex` 없음 등)

- [ ] **Step 3: DocumentStore 수정** — `DocumentStore.swift`

`@Published public private(set) var selection` 아래에 추가:

```swift
  /// 새 노드가 추가되는 레이어 (레이어 패널에서 선택). ID 기반이라 순서
  /// 변경·삭제에도 안정적이며, 사라지면 첫 레이어(0)로 폴백한다.
  @Published public private(set) var activeLayerID: NodeID?
```

`load(_:)` 본문에 `selection = []` 다음 줄 추가:

```swift
    activeLayerID = nil
```

`// MARK: - 선택` 섹션 앞에 추가:

```swift
  // MARK: - 활성 레이어

  public var activeLayerIndex: Int {
    guard let activeLayerID,
      let index = document.layers.firstIndex(where: { $0.id == activeLayerID })
    else { return 0 }
    return index
  }

  public func setActiveLayer(id: NodeID) {
    guard document.layers.contains(where: { $0.id == id }) else { return }
    activeLayerID = id
  }

  /// 도구 생성 경로 — 활성 레이어에 노드를 추가한다.
  /// 활성 레이어가 잠겨 있거나 숨겨져 있으면 조용히 무시한다 (Illustrator 동작).
  public func appendNodeToActiveLayer(_ node: Node, actionName: String) {
    let index = activeLayerIndex
    guard document.layers.indices.contains(index) else { return }
    let layer = document.layers[index]
    guard layer.isVisible, !layer.isLocked else { return }
    apply(actionName: actionName) { $0.layers[index].nodes.append(node) }
  }
```

- [ ] **Step 4: ShapeTool 수정** — `mouseUp`의 `context.store.apply(...)` 블록을 교체

```swift
    context.store.appendNodeToActiveLayer(
      .path(PathNode(path: makePath(in: rect), style: .defaultShape)),
      actionName: "도형 추가")
```

(기존 `let path = makePath(in: rect)` 줄은 삭제하고 위처럼 인라인.)

- [ ] **Step 5: PenTool 수정** — ① `mouseDown` 첫 줄에 가드 추가:

```swift
    // 이중 mouseDown 이벤트 방어 (mouseUp 누락 시 앵커 중복 방지 — M2b 이월).
    guard !isDraggingHandle else { return }
```

② `commit`의 `context.store.apply(...)` 블록을 교체:

```swift
    context.store.appendNodeToActiveLayer(
      .path(PathNode(path: path, style: .defaultShape)), actionName: "패스 생성")
```

- [ ] **Step 6: 통과 확인** — `swift test` → 전체 PASS (165개)

- [ ] **Step 7: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 활성 레이어 도입 — 도구 layers[0] 하드코딩 제거·펜 이중 다운 가드"
```

---

### Task 4: 그룹/해제·앞뒤 순서 — 모델 연산

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Model/VectorDocument+Editing.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Geometry/NodeTransformer.swift` (`applying` 공개)
- Test: `VectaEngine/Tests/VectaEngineTests/VectorDocumentStructureTests.swift` (생성)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`groupTopLevelNodes` 없음)

- [ ] **Step 3: NodeTransformer.applying 공개** — `NodeTransformer.swift`의

```swift
  private static func applying(_ operation: CGAffineTransform, to node: Node) -> Node {
```

을 다음으로 교체 (doc 주석 추가):

```swift
  /// 부모 좌표계 연산을 노드 transform 뒤에 합성한다 (그룹 해제 등에서 사용).
  public static func applying(_ operation: CGAffineTransform, to node: Node) -> Node {
```

- [ ] **Step 4: 모델 연산 구현** — `VectorDocument+Editing.swift` 끝에 추가

```swift
import CoreGraphics

extension VectorDocument {
  /// 선택된 최상위 노드들을 하나의 그룹으로 묶는다. 그룹은 최전면(z-순서 맨
  /// 위) 선택 노드 자리에 들어가고, 자식 순서는 문서 z-순서를 따른다.
  /// 여러 레이어에 걸치면 최전면 노드의 레이어로 모인다.
  @discardableResult
  public mutating func groupTopLevelNodes(ids: Set<NodeID>) -> NodeID? {
    var collected: [Node] = []
    var frontmostID: NodeID?
    for layer in layers {
      for node in layer.nodes where ids.contains(node.id) {
        collected.append(node)
        frontmostID = node.id
      }
    }
    guard let frontmostID else { return nil }
    let group = GroupNode(children: collected)
    updateTopLevelNodes(ids: [frontmostID]) { _ in .group(group) }
    removeTopLevelNodes(ids: ids.subtracting([frontmostID]))
    return group.id
  }

  /// 선택된 최상위 그룹을 제자리에서 자식으로 푼다. 그룹 transform은 자식에
  /// 합성되고 clipPath는 폐기된다 (Illustrator 클리핑 마스크 해제 의미).
  /// 그룹이 아닌 노드는 건드리지 않는다. 풀린 자식 ID 집합을 반환.
  @discardableResult
  public mutating func ungroupTopLevelNodes(ids: Set<NodeID>) -> Set<NodeID> {
    var released: Set<NodeID> = []
    for layerIndex in layers.indices {
      layers[layerIndex].nodes = layers[layerIndex].nodes.flatMap { node -> [Node] in
        guard ids.contains(node.id), case .group(let group) = node else { return [node] }
        let children = group.children.map {
          NodeTransformer.applying(group.transform.cgAffineTransform, to: $0)
        }
        released.formUnion(children.map(\.id))
        return children
      }
    }
    return released
  }

  /// 같은 레이어 안에서 한 칸 앞으로(배열 뒤쪽 = 위). 맨 위 또는 바로 위가
  /// 같은 선택이면 그대로 — 인접 선택 묶음은 통째로 막힌다.
  public mutating func bringForwardTopLevelNodes(ids: Set<NodeID>) {
    for layerIndex in layers.indices {
      var nodes = layers[layerIndex].nodes
      guard nodes.count > 1 else { continue }
      for index in stride(from: nodes.count - 2, through: 0, by: -1)
      where ids.contains(nodes[index].id) && !ids.contains(nodes[index + 1].id) {
        nodes.swapAt(index, index + 1)
      }
      layers[layerIndex].nodes = nodes
    }
  }

  /// 같은 레이어 안에서 한 칸 뒤로(배열 앞쪽 = 아래).
  public mutating func sendBackwardTopLevelNodes(ids: Set<NodeID>) {
    for layerIndex in layers.indices {
      var nodes = layers[layerIndex].nodes
      guard nodes.count > 1 else { continue }
      for index in 1..<nodes.count
      where ids.contains(nodes[index].id) && !ids.contains(nodes[index - 1].id) {
        nodes.swapAt(index, index - 1)
      }
      layers[layerIndex].nodes = nodes
    }
  }
}
```

(파일 상단에 이미 `import Foundation`이 있으므로 `import CoreGraphics`는 기존 import 옆에 추가.)

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (177개)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 그룹·해제·앞뒤 순서 모델 연산 추가"
```

---

### Task 5: DocumentStore 구조 명령 (그룹/해제/순서 + 선택 갱신)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore+Structure.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DocumentStoreStructureTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(at origin: CGPoint) -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(origin: origin, size: CGSize(width: 50, height: 50))),
      style: Style(fill: .color(.black))))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func groupSelectionCreatesGroupAndSelectsIt() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let store = makeStore(nodes: [a, b])
  store.select([a.id, b.id])
  store.groupSelection()
  #expect(store.document.layers[0].nodes.count == 1)
  let groupID = store.document.layers[0].nodes[0].id
  #expect(store.selection == [groupID])
}

@Test @MainActor func groupSelectionIsSingleUndoStep() {
  let undoManager = UndoManager()
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let store = makeStore(nodes: [a, b], undoManager: undoManager)
  store.select([a.id, b.id])
  store.groupSelection()
  undoManager.undo()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id, b.id])
  #expect(!undoManager.canUndo)
}

@Test @MainActor func ungroupSelectionSelectsReleasedChildren() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(children: [.path(inner)])
  let store = makeStore(nodes: [.group(group)])
  store.select([group.id])
  store.ungroupSelection()
  #expect(store.selection == [inner.id])
}

@Test @MainActor func bringSelectionForwardReorders() {
  let a = rect(at: .zero)
  let b = rect(at: CGPoint(x: 60, y: 0))
  let store = makeStore(nodes: [a, b])
  store.select([a.id])
  store.bringSelectionForward()
  #expect(store.document.layers[0].nodes.map(\.id) == [b.id, a.id])
  #expect(store.selection == [a.id])  // 선택 유지
}

@Test @MainActor func structureCommandsIgnoreEmptySelection() {
  let a = rect(at: .zero)
  let store = makeStore(nodes: [a])
  store.groupSelection()
  store.ungroupSelection()
  store.bringSelectionForward()
  store.sendSelectionBackward()
  #expect(store.document.layers[0].nodes.map(\.id) == [a.id])
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`groupSelection` 없음)

- [ ] **Step 3: 구현** — `State/DocumentStore+Structure.swift`

```swift
/// 그룹/해제·앞뒤 순서 명령 — 메뉴(⌘G/⇧⌘G/⌘]/⌘[)와 연결된다 (스펙 §8).
extension DocumentStore {
  public func groupSelection() {
    let ids = selection
    guard !ids.isEmpty else { return }
    var groupID: NodeID?
    apply(actionName: "그룹") { groupID = $0.groupTopLevelNodes(ids: ids) }
    if let groupID { select([groupID]) }
  }

  public func ungroupSelection() {
    let ids = selection
    guard !ids.isEmpty else { return }
    var released: Set<NodeID> = []
    apply(actionName: "그룹 해제") { released = $0.ungroupTopLevelNodes(ids: ids) }
    // 그룹이 아니어서 남은 노드 + 풀린 자식을 함께 선택 (select가 존재 검증)
    select(ids.union(released))
  }

  public func bringSelectionForward() {
    let ids = selection
    guard !ids.isEmpty else { return }
    apply(actionName: "앞으로 가져오기") { $0.bringForwardTopLevelNodes(ids: ids) }
  }

  public func sendSelectionBackward() {
    let ids = selection
    guard !ids.isEmpty else { return }
    apply(actionName: "뒤로 보내기") { $0.sendBackwardTopLevelNodes(ids: ids) }
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (182개)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 그룹·해제·순서 DocumentStore 명령 추가"
```

---

### Task 6: DocumentStore 레이어 명령

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore+Layers.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DocumentStoreLayerCommandTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect() -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
      style: Style(fill: .color(.black))))
}

@MainActor
private func makeStore(undoManager: UndoManager? = nil) -> DocumentStore {
  DocumentStore(document: .empty(size: CGSize(width: 300, height: 300))) { undoManager }
}

@Test @MainActor func addLayerAppendsOnTopAndActivates() {
  let store = makeStore()
  store.addLayer()
  #expect(store.document.layers.count == 2)
  #expect(store.document.layers[1].name == "레이어 2")
  #expect(store.activeLayerIndex == 1)
}

@Test @MainActor func addLayerIsSingleUndoStep() {
  let undoManager = UndoManager()
  let store = makeStore(undoManager: undoManager)
  store.addLayer()
  undoManager.undo()
  #expect(store.document.layers.count == 1)
}

@Test @MainActor func removeLastRemainingLayerIsPrevented() {
  let store = makeStore()
  store.removeLayer(id: store.document.layers[0].id)
  #expect(store.document.layers.count == 1)
}

@Test @MainActor func removeLayerDropsItsNodesAndSelection() {
  let store = makeStore()
  store.addLayer()
  let node = rect()
  store.apply(actionName: "노드 추가") { $0.layers[1].nodes.append(node) }
  store.select([node.id])
  store.removeLayer(id: store.document.layers[1].id)
  #expect(store.document.layers.count == 1)
  #expect(store.selection.isEmpty)
}

@Test @MainActor func renameLayerTrimsAndRejectsEmpty() {
  let store = makeStore()
  let id = store.document.layers[0].id
  store.renameLayer(id: id, to: "  배경  ")
  #expect(store.document.layers[0].name == "배경")
  store.renameLayer(id: id, to: "   ")
  #expect(store.document.layers[0].name == "배경")
}

@Test @MainActor func hidingLayerDeselectsItsNodes() {
  let store = makeStore()
  let node = rect()
  store.apply(actionName: "노드 추가") { $0.layers[0].nodes.append(node) }
  store.select([node.id])
  store.setLayerVisibility(id: store.document.layers[0].id, isVisible: false)
  #expect(store.document.layers[0].isVisible == false)
  #expect(store.selection.isEmpty)
}

@Test @MainActor func lockingLayerDeselectsItsNodes() {
  let store = makeStore()
  let node = rect()
  store.apply(actionName: "노드 추가") { $0.layers[0].nodes.append(node) }
  store.select([node.id])
  store.setLayerLocked(id: store.document.layers[0].id, isLocked: true)
  #expect(store.document.layers[0].isLocked == true)
  #expect(store.selection.isEmpty)
}

@Test @MainActor func moveLayerReordersAndClamps() {
  let store = makeStore()
  store.addLayer()
  store.addLayer()
  let bottom = store.document.layers[0].id
  store.moveLayer(id: bottom, toIndex: 99)  // 클램프 → 맨 위
  #expect(store.document.layers[2].id == bottom)
  store.moveLayer(id: bottom, toIndex: 0)
  #expect(store.document.layers[0].id == bottom)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`addLayer` 없음)

- [ ] **Step 3: 구현** — `State/DocumentStore+Layers.swift`

```swift
import Foundation

/// 레이어 패널 명령 (스펙 §8). 각 명령 = apply 1회 = undo 1단계.
extension DocumentStore {
  public func addLayer() {
    let layer = Layer(name: "레이어 \(document.layers.count + 1)")
    apply(actionName: "레이어 추가") { $0.layers.append(layer) }
    setActiveLayer(id: layer.id)
  }

  /// 마지막 남은 레이어는 삭제하지 않는다 (최소 1개 불변식).
  public func removeLayer(id: NodeID) {
    guard document.layers.count > 1 else { return }
    apply(actionName: "레이어 삭제") { document in
      document.layers.removeAll { $0.id == id }
    }
  }

  /// 앞뒤 공백은 잘라내고, 빈 이름은 무시한다.
  public func renameLayer(id: NodeID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    apply(actionName: "레이어 이름 변경") { document in
      guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
      document.layers[index].name = trimmed
    }
  }

  /// 숨긴 레이어의 노드는 선택에서 제외한다 (히트테스트 불가 상태와 일관).
  public func setLayerVisibility(id: NodeID, isVisible: Bool) {
    apply(actionName: isVisible ? "레이어 표시" : "레이어 숨김") { document in
      guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
      document.layers[index].isVisible = isVisible
    }
    if !isVisible {
      deselectNodes(inLayer: id)
    }
  }

  /// 잠근 레이어의 노드는 선택에서 제외한다.
  public func setLayerLocked(id: NodeID, isLocked: Bool) {
    apply(actionName: isLocked ? "레이어 잠금" : "레이어 잠금 해제") { document in
      guard let index = document.layers.firstIndex(where: { $0.id == id }) else { return }
      document.layers[index].isLocked = isLocked
    }
    if isLocked {
      deselectNodes(inLayer: id)
    }
  }

  /// toIndex는 배열 범위로 클램프된다 (레이어 패널 드래그 순서 변경).
  public func moveLayer(id: NodeID, toIndex: Int) {
    apply(actionName: "레이어 순서 변경") { document in
      guard let from = document.layers.firstIndex(where: { $0.id == id }) else { return }
      let clamped = max(0, min(toIndex, document.layers.count - 1))
      guard clamped != from else { return }
      let layer = document.layers.remove(at: from)
      document.layers.insert(layer, at: clamped)
    }
  }

  private func deselectNodes(inLayer layerID: NodeID) {
    guard let layer = document.layers.first(where: { $0.id == layerID }) else { return }
    let layerNodeIDs = Set(layer.nodes.map(\.id))
    select(selection.subtracting(layerNodeIDs))
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (190개)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 레이어 추가·삭제·이름·표시·잠금·순서 명령 추가"
```

---

### Task 7: 스타일 편집 명령 (그룹 자손 포함 일괄 변경)

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Model/VectorDocument+Editing.swift`
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore+Styling.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DocumentStoreStylingTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private let red = RGBA(red: 1, green: 0, blue: 0)

private func rect(at origin: CGPoint = .zero) -> PathNode {
  PathNode(
    path: .rectangle(CGRect(origin: origin, size: CGSize(width: 50, height: 50))),
    style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

@Test @MainActor func updateSelectionStylesChangesFillWithSingleUndo() {
  let undoManager = UndoManager()
  let node = rect()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.select([node.id])
  store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
    style.fill = .color(red)
  }
  #expect(store.selectionPathStyle?.fill == .color(red))
  undoManager.undo()
  #expect(store.selectionPathStyle?.fill == .color(.black))
  #expect(!undoManager.canUndo)
}

@Test @MainActor func styleChangeOnGroupReachesPathDescendants() {
  let inner = rect()
  let nested = rect(at: CGPoint(x: 100, y: 0))
  let innerGroup = GroupNode(children: [.path(nested)])
  let group = GroupNode(children: [.path(inner), .group(innerGroup)])
  let store = makeStore(nodes: [.group(group)])
  store.select([group.id])
  store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
    style.fill = .color(red)
  }
  guard case .group(let updated)? = store.document.topLevelNode(id: group.id),
    case .path(let updatedInner) = updated.children[0],
    case .group(let updatedInnerGroup) = updated.children[1],
    case .path(let updatedNested) = updatedInnerGroup.children[0]
  else {
    Issue.record("구조가 다름")
    return
  }
  #expect(updatedInner.style.fill == .color(red))
  #expect(updatedNested.style.fill == .color(red))
}

@Test @MainActor func selectionPathStyleReturnsFrontmostPath() {
  let back = rect()
  var front = rect(at: CGPoint(x: 100, y: 0))
  front.style = Style(fill: .color(red))
  let store = makeStore(nodes: [.path(back), .path(front)])
  store.select([back.id, front.id])
  #expect(store.selectionPathStyle?.fill == .color(red))
}

@Test @MainActor func emptySelectionStyleUpdateIsNoOp() {
  let node = rect()
  let undoManager = UndoManager()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
    style.fill = .color(red)
  }
  #expect(!undoManager.canUndo)
}

@Test @MainActor func updateSelectionStylesProvidesLocalPathBounds() {
  // 그라디언트 기본 선분 계산용 — 클로저에 노드의 로컬 패스 바운드가 온다
  let node = PathNode(
    path: .rectangle(CGRect(x: 10, y: 20, width: 80, height: 40)),
    style: Style(fill: .color(.black)),
    transform: Transform2D(CGAffineTransform(translationX: 500, y: 0)))
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  var captured: CGRect?
  store.updateSelectionStyles(actionName: "확인") { style, bounds in
    captured = bounds
    style.fill = .color(red)  // 변경 없으면 apply가 무시하므로 더미 변경
  }
  #expect(captured == CGRect(x: 10, y: 20, width: 80, height: 40))
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`updateSelectionStyles` 없음)

- [ ] **Step 3: 모델 — 깊은 패스 일괄 변경** — `VectorDocument+Editing.swift` 끝에 추가

```swift
extension VectorDocument {
  /// ids에 해당하는 패스 노드를 변경한다. 그룹이 매치되면 그 안의 모든 패스
  /// 자손에 적용된다 (Illustrator의 그룹 스타일 편집 의미).
  public mutating func updatePathNodes(ids: Set<NodeID>, _ change: (inout PathNode) -> Void) {
    for layerIndex in layers.indices {
      layers[layerIndex].nodes = layers[layerIndex].nodes.map {
        updatingPathNodes($0, ids: ids, isAncestorMatched: false, change)
      }
    }
  }

  private func updatingPathNodes(
    _ node: Node, ids: Set<NodeID>, isAncestorMatched: Bool,
    _ change: (inout PathNode) -> Void
  ) -> Node {
    let matched = isAncestorMatched || ids.contains(node.id)
    switch node {
    case .path(var pathNode):
      if matched { change(&pathNode) }
      return .path(pathNode)
    case .group(var group):
      group.children = group.children.map {
        updatingPathNodes($0, ids: ids, isAncestorMatched: matched, change)
      }
      return .group(group)
    case .text, .image:
      return node
    }
  }

  /// ids 중 최전면(z-순서 맨 위) 패스 노드 — 그룹이면 그 안의 최전면 패스.
  /// 인스펙터의 대표 스타일 표시용.
  public func frontmostPathNode(in ids: Set<NodeID>) -> PathNode? {
    var result: PathNode?
    for layer in layers {
      for node in layer.nodes {
        collectFrontmostPath(node, ids: ids, isAncestorMatched: false, into: &result)
      }
    }
    return result
  }

  private func collectFrontmostPath(
    _ node: Node, ids: Set<NodeID>, isAncestorMatched: Bool, into result: inout PathNode?
  ) {
    let matched = isAncestorMatched || ids.contains(node.id)
    switch node {
    case .path(let pathNode):
      if matched { result = pathNode }
    case .group(let group):
      for child in group.children {
        collectFrontmostPath(child, ids: ids, isAncestorMatched: matched, into: &result)
      }
    case .text, .image:
      break
    }
  }
}
```

- [ ] **Step 4: 스토어 명령** — `State/DocumentStore+Styling.swift`

```swift
import CoreGraphics

/// 인스펙터 스타일 명령 (스펙 §8). 그룹 선택은 패스 자손 전체에 적용된다.
extension DocumentStore {
  /// 인스펙터 표시용 대표 스타일 — 선택의 최전면 패스 노드 기준.
  public var selectionPathStyle: Style? {
    document.frontmostPathNode(in: selection)?.style
  }

  /// 선택된 패스 노드의 스타일을 일괄 변경한다 (apply 1회 = undo 1단계).
  /// 클로저의 localBounds는 각 노드의 로컬 패스 바운드 — 그라디언트 기본
  /// 선분 계산용 (그라디언트 좌표는 객체 로컬 — 스펙 §4).
  public func updateSelectionStyles(
    actionName: String, _ change: @escaping (inout Style, _ localBounds: CGRect) -> Void
  ) {
    let ids = selection
    guard !ids.isEmpty else { return }
    apply(actionName: actionName) { document in
      document.updatePathNodes(ids: ids) { pathNode in
        change(&pathNode.style, pathNode.path.bounds)
      }
    }
  }

  /// 드래그 제스처용 미리보기 — begin/commitTransient 사이에서 undo 등록
  /// 없이 스타일을 갱신한다 (불투명도·스톱 위치 슬라이더).
  public func updateSelectionStylesTransient(
    _ change: @escaping (inout Style, _ localBounds: CGRect) -> Void
  ) {
    let ids = selection
    guard !ids.isEmpty else { return }
    updateTransient { document in
      document.updatePathNodes(ids: ids) { pathNode in
        change(&pathNode.style, pathNode.path.bounds)
      }
    }
  }
}
```

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (195개)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 선택 스타일 일괄 변경 명령 — 그룹 자손 포함"
```

---

### Task 8: 변환 수치 명령 (X/Y/W/H/회전)

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Geometry/NodeTransformer.swift` (Node.transform/rotationDegrees)
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore+Transform.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DocumentStoreTransformTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func rect(at origin: CGPoint = CGPoint(x: 10, y: 10)) -> PathNode {
  PathNode(
    path: .rectangle(CGRect(origin: origin, size: CGSize(width: 100, height: 50))),
    style: Style(fill: .color(.black)))
}

@MainActor
private func makeStore(
  nodes: [Node], undoManager: UndoManager? = nil
) -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 400, height: 400))
  document.layers[0].nodes = nodes
  return DocumentStore(document: document) { undoManager }
}

private func expectClose(
  _ actual: CGFloat, _ expected: CGFloat,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(abs(actual - expected) < 0.0001, sourceLocation: sourceLocation)
}

@Test @MainActor func moveSelectionSetsBoundsOrigin() {
  let node = rect()
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.moveSelection(x: 50)
  expectClose(store.selectionBounds!.minX, 50)
  expectClose(store.selectionBounds!.minY, 10)  // y 유지
  store.moveSelection(y: 80)
  expectClose(store.selectionBounds!.minY, 80)
  expectClose(store.selectionBounds!.minX, 50)  // x 유지
}

@Test @MainActor func resizeSelectionAnchorsTopLeft() {
  let node = rect()
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.resizeSelection(width: 200)
  let bounds = store.selectionBounds!
  expectClose(bounds.width, 200)
  expectClose(bounds.height, 50)  // 비율 독립
  expectClose(bounds.minX, 10)  // 좌상단 고정
  expectClose(bounds.minY, 10)
}

@Test @MainActor func resizeSelectionRejectsNonPositive() {
  let node = rect()
  let undoManager = UndoManager()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.select([node.id])
  store.resizeSelection(width: 0)
  store.resizeSelection(height: -5)
  expectClose(store.selectionBounds!.width, 100)
  #expect(!undoManager.canUndo)
}

@Test @MainActor func rotateSelectionByNinetyDegreesSwapsBoundsAroundCenter() {
  let node = rect()  // bounds (10,10,100,50), 중심 (60,35)
  let store = makeStore(nodes: [.path(node)])
  store.select([node.id])
  store.rotateSelection(byDegrees: 90)
  let bounds = store.selectionBounds!
  expectClose(bounds.width, 50)
  expectClose(bounds.height, 100)
  expectClose(bounds.midX, 60)  // 중심 유지
  expectClose(bounds.midY, 35)
}

@Test @MainActor func rotationDegreesExtractsAngleFromTransform() {
  var node = rect()
  node.transform = Transform2D(CGAffineTransform(rotationAngle: 30 * .pi / 180))
  #expect(abs(Node.path(node).rotationDegrees - 30) < 0.0001)
  #expect(Node.path(rect()).rotationDegrees == 0)
}

@Test @MainActor func transformCommandIsSingleUndoStep() {
  let undoManager = UndoManager()
  let node = rect()
  let store = makeStore(nodes: [.path(node)], undoManager: undoManager)
  store.select([node.id])
  store.moveSelection(x: 50)
  undoManager.undo()
  expectClose(store.selectionBounds!.minX, 10)
  #expect(!undoManager.canUndo)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`moveSelection` 없음)

- [ ] **Step 3: Node 회전각 추출** — `NodeTransformer.swift` 끝에 추가

```swift
extension Node {
  /// 노드 transform (케이스 공통 접근).
  public var transform: Transform2D {
    switch self {
    case .path(let node): return node.transform
    case .group(let node): return node.transform
    case .text(let node): return node.transform
    case .image(let node): return node.transform
    }
  }

  /// transform의 회전 성분 (도). 모델 y-아래 좌표계 — 양수 = 화면 시계 방향.
  public var rotationDegrees: Double {
    atan2(transform.b, transform.a) * 180 / .pi
  }
}
```

- [ ] **Step 4: 스토어 명령** — `State/DocumentStore+Transform.swift`

```swift
import CoreGraphics

/// 인스펙터 변환 수치 입력 명령 (스펙 §8 — X/Y/W/H/회전).
extension DocumentStore {
  /// 선택 바운드 원점을 (x, y)로 이동한다. nil 축은 유지.
  public func moveSelection(x: CGFloat? = nil, y: CGFloat? = nil) {
    guard let bounds = selectionBounds else { return }
    let delta = CGVector(
      dx: (x ?? bounds.minX) - bounds.minX,
      dy: (y ?? bounds.minY) - bounds.minY)
    guard delta.dx != 0 || delta.dy != 0 else { return }
    let ids = selection
    apply(actionName: "이동") { document in
      document.updateTopLevelNodes(ids: ids) { NodeTransformer.translated($0, by: delta) }
    }
  }

  /// 선택 바운드 크기를 (width, height)로 — 좌상단 고정. 0 이하 입력은 무시.
  public func resizeSelection(width: CGFloat? = nil, height: CGFloat? = nil) {
    guard let bounds = selectionBounds, bounds.width > 0, bounds.height > 0 else { return }
    if let width, width <= 0 { return }
    if let height, height <= 0 { return }
    let scaleX = (width ?? bounds.width) / bounds.width
    let scaleY = (height ?? bounds.height) / bounds.height
    guard scaleX != 1 || scaleY != 1 else { return }
    let ids = selection
    let anchor = CGPoint(x: bounds.minX, y: bounds.minY)
    apply(actionName: "크기 조절") { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.resized($0, anchor: anchor, scaleX: scaleX, scaleY: scaleY)
      }
    }
  }

  /// 선택 바운드 중심 기준 회전 (도 단위 델타).
  public func rotateSelection(byDegrees degrees: CGFloat) {
    guard degrees != 0, let bounds = selectionBounds else { return }
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let ids = selection
    apply(actionName: "회전") { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.rotated($0, around: center, by: degrees * .pi / 180)
      }
    }
  }
}
```

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (201개)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 변환 수치 명령 — X·Y·W·H 절대값과 회전 델타"
```

---

### Task 9: 직접 선택 그룹 내부 진입 (M2b 이월, 스펙 §7)

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Geometry/HitTesting.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Model/VectorDocument+Editing.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Tools/DirectSelectTool.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/HitTestingTests.swift`, `VectorDocumentTests.swift`, `DirectSelectToolTests.swift` (추가)

- [ ] **Step 1: 실패하는 테스트 작성** — `HitTestingTests.swift` 끝에 추가

```swift
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
```

`VectorDocumentTests.swift` 끝에 추가:

```swift
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
```

`DirectSelectToolTests.swift` 끝에 추가:

```swift
@Test @MainActor func clickInsideGroupTargetsInnerPath() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  let context = ToolContext(store: DocumentStore(document: document))
  let tool = DirectSelectTool()
  tool.mouseDown(at(120, 20), context: context)
  tool.mouseUp(at(120, 20), context: context)
  #expect(tool.editNodeID == inner.id)
}

@Test @MainActor func draggingAnchorInsideGroupUsesWorldCoordinates() {
  let inner = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50)),
    style: Style(fill: .color(.black)))
  let group = GroupNode(
    children: [.path(inner)],
    transform: Transform2D(CGAffineTransform(translationX: 100, y: 0)))
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [.group(group)]
  let store = DocumentStore(document: document)
  let context = ToolContext(store: store)
  let tool = DirectSelectTool()
  tool.mouseDown(at(120, 20), context: context)  // 본체 → 편집 대상
  tool.mouseUp(at(120, 20), context: context)
  tool.mouseDown(at(150, 50), context: context)  // 월드 (150,50) = 로컬 (50,50) 앵커
  tool.mouseDragged(at(160, 60), context: context)
  tool.mouseUp(at(160, 60), context: context)
  guard let found = store.document.pathNode(id: inner.id) else {
    Issue.record("패스 없음")
    return
  }
  // 로컬 좌표로 (60,60)
  #expect(
    found.node.path.anchorPosition(AnchorRef(subpathIndex: 0, segmentIndex: 2))
      == CGPoint(x: 60, y: 60))
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`topmostPathNodeID` 없음)

- [ ] **Step 3: HitTesting 확장** — `HitTesting.swift`의 `topLevelNodeIDs` 메서드 다음에 추가

```swift
  /// 점에 닿는 최상단 "패스" 노드 ID — 그룹 내부로 내려가 잎 패스를 찾는다
  /// (직접 선택 도구의 내부 진입 — 스펙 §7).
  public static func topmostPathNodeID(
    at point: CGPoint, in document: VectorDocument, tolerance: CGFloat
  ) -> NodeID? {
    for layer in document.layers.reversed() where layer.isVisible && !layer.isLocked {
      if let found = topmostPathNodeID(at: point, in: layer.nodes, tolerance: tolerance) {
        return found
      }
    }
    return nil
  }

  private static func topmostPathNodeID(
    at point: CGPoint, in nodes: [Node], tolerance: CGFloat
  ) -> NodeID? {
    for node in nodes.reversed() {
      switch node {
      case .path(let pathNode):
        if hits(pathNode, at: point, tolerance: tolerance) { return pathNode.id }
      case .group(let group):
        guard let inverse = safeInverse(of: group.transform) else { continue }
        let local = point.applying(inverse)
        let determinant =
          group.transform.a * group.transform.d - group.transform.b * group.transform.c
        let localTolerance = tolerance / sqrt(abs(determinant))
        if let clip = group.clipPath, !clip.cgPath.contains(local, using: .winding) {
          continue
        }
        if let found = topmostPathNodeID(
          at: local, in: group.children, tolerance: localTolerance)
        {
          return found
        }
      case .text, .image:
        continue
      }
    }
    return nil
  }
```

- [ ] **Step 4: 모델 — 깊은 패스 조회/변경** — `VectorDocument+Editing.swift` 끝에 추가

```swift
extension VectorDocument {
  /// id 패스 노드와 월드 변환(그룹 체인 합성: 노드 × 그룹 × …).
  /// 직접 선택 도구의 좌표 변환용.
  public func pathNode(
    id: NodeID
  ) -> (node: PathNode, worldTransform: CGAffineTransform)? {
    for layer in layers {
      if let found = findPathNode(id: id, in: layer.nodes, parentTransform: .identity) {
        return found
      }
    }
    return nil
  }

  private func findPathNode(
    id: NodeID, in nodes: [Node], parentTransform: CGAffineTransform
  ) -> (node: PathNode, worldTransform: CGAffineTransform)? {
    for node in nodes {
      switch node {
      case .path(let pathNode) where pathNode.id == id:
        return (pathNode, pathNode.transform.cgAffineTransform.concatenating(parentTransform))
      case .group(let group):
        let world = group.transform.cgAffineTransform.concatenating(parentTransform)
        if let found = findPathNode(id: id, in: group.children, parentTransform: world) {
          return found
        }
      default:
        continue
      }
    }
    return nil
  }

  /// 깊이에 상관없이 id 패스 노드 하나를 변경한다 (그룹 내부 포함).
  public mutating func updatePathNode(id: NodeID, _ change: (inout PathNode) -> Void) {
    for layerIndex in layers.indices {
      layers[layerIndex].nodes = layers[layerIndex].nodes.map {
        updatingPathNode($0, id: id, change)
      }
    }
  }

  private func updatingPathNode(
    _ node: Node, id: NodeID, _ change: (inout PathNode) -> Void
  ) -> Node {
    switch node {
    case .path(var pathNode):
      if pathNode.id == id { change(&pathNode) }
      return .path(pathNode)
    case .group(var group):
      group.children = group.children.map { updatingPathNode($0, id: id, change) }
      return .group(group)
    case .text, .image:
      return node
    }
  }
}
```

- [ ] **Step 5: DirectSelectTool 수정** — 월드 변환 기반으로 교체. 변경 지점:

① 파일 상단 doc 주석 교체:

```swift
/// 직접 선택 도구 (A): 패스 노드의 앵커·컨트롤 핸들을 드래그 편집한다.
/// 그룹 내부 패스도 월드 변환(그룹 체인 합성)으로 직접 진입한다 (스펙 §7).
/// 앵커 추가/삭제는 비목표. 도구 재진입 시 편집 대상은 초기화된다 (M3 결정).
```

② `mouseDown`에서 편집 대상 블록과 빈 히트 블록 교체:

```swift
  public func mouseDown(_ event: CanvasEvent, context: ToolContext) {
    if case .idle = dragState {
    } else {
      context.store.cancelTransient()
      dragState = .idle
    }
    let store = context.store
    let handleTolerance = event.hitTolerance * 1.5
    if let nodeID = editNodeID, let found = store.document.pathNode(id: nodeID) {
      // 앵커가 핸들보다 우선 — 핸들이 앵커와 겹치면 앵커가 잡힌다 (Illustrator/Figma 동일).
      if let hitAnchor = hitAnchor(
        in: found.node, worldTransform: found.worldTransform,
        at: event.point, tolerance: handleTolerance)
      {
        selectedAnchor = hitAnchor
        store.beginTransient()
        dragState = .anchor(nodeID, hitAnchor)
        context.invalidateOverlay()
        return
      }
      if let anchor = selectedAnchor,
        let hitControl = hitControl(
          in: found.node, worldTransform: found.worldTransform,
          anchor: anchor, at: event.point, tolerance: handleTolerance)
      {
        store.beginTransient()
        dragState = .control(nodeID, hitControl)
        return
      }
    }
    if let hitID = HitTesting.topmostPathNodeID(
      at: event.point, in: store.document, tolerance: event.hitTolerance)
    {
      editNodeID = hitID
      selectedAnchor = nil
      context.invalidateOverlay()
      return
    }
    editNodeID = nil
    selectedAnchor = nil
    context.invalidateOverlay()
  }
```

③ `mouseDragged` 교체:

```swift
  public func mouseDragged(_ event: CanvasEvent, context: ToolContext) {
    switch dragState {
    case .anchor(let nodeID, let ref):
      editPath(of: nodeID, context: context) { pathNode, worldTransform in
        guard let local = Self.localPoint(event.point, worldTransform: worldTransform)
        else { return pathNode.path }
        return pathNode.path.movingAnchor(ref, to: local)
      }
    case .control(let nodeID, let ref):
      editPath(of: nodeID, context: context) { pathNode, worldTransform in
        guard let local = Self.localPoint(event.point, worldTransform: worldTransform)
        else { return pathNode.path }
        return pathNode.path.movingControl(ref, to: local)
      }
    case .idle:
      break
    }
  }
```

④ `drawOverlay` 첫 guard와 transform 줄 교체:

```swift
    guard let nodeID = editNodeID,
      let found = context.store.document.pathNode(id: nodeID)
    else { return }
    let pathNode = found.node
    let transform = found.worldTransform
```

(이후 본문은 `pathNode`/`transform` 변수를 그대로 사용 — 변경 없음.)

⑤ 헬퍼 교체 — `topLevelPathNode`/`localPoint`/`hitAnchor`/`hitControl`/`editPath`를 다음으로:

```swift
  // MARK: - 헬퍼

  private static func localPoint(
    _ point: CGPoint, worldTransform: CGAffineTransform
  ) -> CGPoint? {
    guard let inverse = Transform2D(worldTransform).invertedOrNil else { return nil }
    return point.applying(inverse)
  }

  private func hitAnchor(
    in pathNode: PathNode, worldTransform: CGAffineTransform,
    at point: CGPoint, tolerance: CGFloat
  ) -> AnchorRef? {
    pathNode.path.anchors().first { _, localPosition in
      let position = localPosition.applying(worldTransform)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }?.ref
  }

  private func hitControl(
    in pathNode: PathNode, worldTransform: CGAffineTransform,
    anchor: AnchorRef, at point: CGPoint, tolerance: CGFloat
  ) -> ControlRef? {
    pathNode.path.controlHandles(forAnchor: anchor).first { _, localPosition in
      let position = localPosition.applying(worldTransform)
      return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
    }?.ref
  }

  private func editPath(
    of nodeID: NodeID, context: ToolContext,
    _ newPath: @escaping (PathNode, CGAffineTransform) -> BezierPath
  ) {
    context.store.updateTransient { document in
      guard let worldTransform = document.pathNode(id: nodeID)?.worldTransform else { return }
      document.updatePathNode(id: nodeID) { pathNode in
        pathNode.path = newPath(pathNode, worldTransform)
      }
    }
  }
```

- [ ] **Step 6: 통과 확인** — `swift test` → 전체 PASS (206개). 기존 DirectSelectTool 테스트(최상위 패스)도 모두 그린이어야 한다.

- [ ] **Step 7: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 직접 선택 그룹 내부 진입 — 월드 변환 기반 패스 편집"
```

---

### Task 10: 앱 — 오브젝트 메뉴 (⌘G/⇧⌘G/⌘]/⌘[)

UI 셸 — 빌드 + 스모크 검증 (엔진 명령은 Task 5에서 테스트 완료).

**Files:**
- Modify: `VectaApp/Sources/MainMenuBuilder.swift`
- Modify: `VectaApp/Sources/Document/VectaDocument.swift`

- [ ] **Step 1: MainMenuBuilder 수정** — `build()`에서 `editMenu` 다음 줄 추가:

```swift
    mainMenu.addItem(wrap(objectMenu()))
```

`editMenu()` 메서드 뒤에 추가:

```swift
  private static func objectMenu() -> NSMenu {
    let menu = NSMenu(title: "오브젝트")
    menu.addItem(
      withTitle: "그룹",
      action: #selector(VectaDocument.groupSelection(_:)), keyEquivalent: "g")
    let ungroup = menu.addItem(
      withTitle: "그룹 해제",
      action: #selector(VectaDocument.ungroupSelection(_:)), keyEquivalent: "G")
    ungroup.keyEquivalentModifierMask = [.command, .shift]
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "앞으로 가져오기",
      action: #selector(VectaDocument.bringForward(_:)), keyEquivalent: "]")
    menu.addItem(
      withTitle: "뒤로 보내기",
      action: #selector(VectaDocument.sendBackward(_:)), keyEquivalent: "[")
    return menu
  }
```

- [ ] **Step 2: VectaDocument 액션 추가** — `read(from:ofType:)` 메서드 뒤에 추가:

```swift
  // MARK: - 오브젝트 메뉴 액션 (응답 체인 — MainMenuBuilder가 연결)

  @objc func groupSelection(_ sender: Any?) {
    store.groupSelection()
  }

  @objc func ungroupSelection(_ sender: Any?) {
    store.ungroupSelection()
  }

  @objc func bringForward(_ sender: Any?) {
    store.bringSelectionForward()
  }

  @objc func sendBackward(_ sender: Any?) {
    store.sendSelectionBackward()
  }

  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    switch item.action {
    case #selector(groupSelection(_:)), #selector(bringForward(_:)),
      #selector(sendBackward(_:)):
      return !store.selection.isEmpty
    case #selector(ungroupSelection(_:)):
      return store.selection.contains { id in
        if case .group? = store.document.topLevelNode(id: id) { return true }
        return false
      }
    default:
      return super.validateUserInterfaceItem(item)
    }
  }
```

- [ ] **Step 3: 빌드 + 엔진 회귀**

```bash
cd VectaEngine && swift build && swift test   # 전체 PASS
cd ../VectaApp && xcodegen generate && \
xcodebuild -project Vecta.xcodeproj -scheme Vecta -configuration Debug \
  -derivedDataPath build build                # BUILD SUCCEEDED
```

- [ ] **Step 4: 실행 스모크** — `open VectaApp/build/Build/Products/Debug/Vecta.app` → `pgrep -x Vecta` 생존 확인 → `pkill -x Vecta`. GUI 조작은 사용자 검증.

- [ ] **Step 5: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: 오브젝트 메뉴 — 그룹·해제·앞뒤 순서 단축키"
```

---

### Task 11: 앱 — 레이어 패널

UI 셸 — 빌드 + 스모크 검증 (레이어 명령은 Task 6에서 테스트 완료).

**Files:**
- Create: `VectaApp/Sources/Panels/LayerPanelView.swift`
- Modify: `VectaApp/Sources/Document/VectaDocument.swift` (우측 도킹)

- [ ] **Step 1: LayerPanelView 작성** — `Panels/LayerPanelView.swift`

```swift
import SwiftUI
import VectaEngine

private enum LayerPanelLayout {
  static let rowHeight: CGFloat = 26
  static let iconSize: CGFloat = 12
  static let headerPadding: CGFloat = 8
  static let activeBackgroundOpacity: CGFloat = 0.18
}

/// 레이어 패널 (스펙 §8) — 목록(위 행 = 최상위 레이어)/눈/자물쇠/이름 더블클릭
/// 편집/드래그 순서 변경/클릭으로 활성 레이어 지정. 노드 트리는 M3 비목표.
struct LayerPanelView: View {
  @ObservedObject var store: DocumentStore
  @State private var editingLayerID: NodeID?
  @State private var draftName = ""
  @FocusState private var nameFieldFocused: Bool

  /// 표시 순서: 맨 위 행 = 최상위 레이어 (모델 배열의 역순).
  private var displayedLayers: [Layer] { store.document.layers.reversed() }

  private var activeLayerID: NodeID {
    store.document.layers[store.activeLayerIndex].id
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      List {
        ForEach(displayedLayers, id: \.id) { layer in
          row(for: layer)
        }
        .onMove(perform: moveDisplayedLayers)
      }
      .listStyle(.plain)
    }
  }

  private var header: some View {
    HStack {
      Text("레이어").font(.headline)
      Spacer()
      Button {
        store.addLayer()
      } label: {
        Image(systemName: "plus")
      }
      .buttonStyle(.borderless)
      .help("레이어 추가")
      Button {
        store.removeLayer(id: activeLayerID)
      } label: {
        Image(systemName: "minus")
      }
      .buttonStyle(.borderless)
      .disabled(store.document.layers.count <= 1)
      .help("활성 레이어 삭제")
    }
    .padding(LayerPanelLayout.headerPadding)
  }

  private func row(for layer: Layer) -> some View {
    HStack(spacing: 6) {
      Button {
        store.setLayerVisibility(id: layer.id, isVisible: !layer.isVisible)
      } label: {
        Image(systemName: layer.isVisible ? "eye" : "eye.slash")
          .font(.system(size: LayerPanelLayout.iconSize))
      }
      .buttonStyle(.borderless)
      .help(layer.isVisible ? "레이어 숨김" : "레이어 표시")
      Button {
        store.setLayerLocked(id: layer.id, isLocked: !layer.isLocked)
      } label: {
        Image(systemName: layer.isLocked ? "lock" : "lock.open")
          .font(.system(size: LayerPanelLayout.iconSize))
          .foregroundStyle(layer.isLocked ? .primary : .tertiary)
      }
      .buttonStyle(.borderless)
      .help(layer.isLocked ? "잠금 해제" : "잠금")
      nameView(for: layer)
      Spacer(minLength: 0)
    }
    .frame(height: LayerPanelLayout.rowHeight)
    .contentShape(Rectangle())
    .onTapGesture { store.setActiveLayer(id: layer.id) }
    .listRowBackground(
      layer.id == activeLayerID
        ? Color.accentColor.opacity(LayerPanelLayout.activeBackgroundOpacity)
        : Color.clear)
  }

  @ViewBuilder
  private func nameView(for layer: Layer) -> some View {
    if editingLayerID == layer.id {
      TextField("이름", text: $draftName)
        .textFieldStyle(.roundedBorder)
        .focused($nameFieldFocused)
        .onSubmit { commitRename(of: layer) }
        .onExitCommand { editingLayerID = nil }
    } else {
      Text(layer.name)
        .lineLimit(1)
        .onTapGesture(count: 2) {
          draftName = layer.name
          editingLayerID = layer.id
          nameFieldFocused = true
        }
    }
  }

  private func commitRename(of layer: Layer) {
    store.renameLayer(id: layer.id, to: draftName)
    editingLayerID = nil
  }

  /// List 표시(역순) 인덱스 → 모델 배열 인덱스로 변환해 이동한다.
  private func moveDisplayedLayers(from source: IndexSet, to destination: Int) {
    guard let displayFrom = source.first else { return }
    let layers = store.document.layers
    let displayTo = destination > displayFrom ? destination - 1 : destination
    let arrayFrom = layers.count - 1 - displayFrom
    let arrayTo = layers.count - 1 - displayTo
    store.moveLayer(id: layers[arrayFrom].id, toIndex: arrayTo)
  }
}
```

- [ ] **Step 2: VectaDocument 도킹** — `makeContentView`의 stack 구성 교체:

```swift
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
    let sidePanel = NSHostingView(rootView: LayerPanelView(store: store))
    let stack = NSStackView(views: [toolbar, scrollView, sidePanel])
    stack.orientation = .horizontal
    stack.distribution = .fill
    stack.spacing = 0
    sidePanel.widthAnchor.constraint(equalToConstant: 260).isActive = true
    return stack
  }
```

(Task 12에서 `LayerPanelView` 자리를 `SidePanelView`로 바꾼다.)

- [ ] **Step 3: 빌드 + 엔진 회귀** — Task 10 Step 3과 동일 명령. 전체 PASS + BUILD SUCCEEDED

- [ ] **Step 4: 실행 스모크** — 앱 실행 → 생존 확인 → 종료

- [ ] **Step 5: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: 레이어 패널 — 목록·눈·자물쇠·이름 편집·순서·활성 레이어"
```

---

### Task 12: 앱 — 인스펙터 + 우측 패널 통합

UI 셸 — 빌드 + 스모크 검증 (스타일·변환 명령은 Task 7·8에서 테스트 완료).

**Files:**
- Create: `VectaApp/Sources/Panels/RGBA+Color.swift`
- Create: `VectaApp/Sources/Panels/InspectorView.swift`
- Create: `VectaApp/Sources/Panels/FillSection.swift`
- Create: `VectaApp/Sources/Panels/StrokeSection.swift`
- Create: `VectaApp/Sources/Panels/SidePanelView.swift`
- Modify: `VectaApp/Sources/Document/VectaDocument.swift` (SidePanelView로 교체)

- [ ] **Step 1: RGBA ↔ SwiftUI Color** — `Panels/RGBA+Color.swift`

```swift
import SwiftUI
import VectaEngine

extension RGBA {
  var swiftUIColor: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }

  /// ColorPicker 출력 → sRGB 성분. 변환 실패 시 검정 (방어적 폴백).
  init(_ color: Color) {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
    self.init(
      red: nsColor.redComponent, green: nsColor.greenComponent,
      blue: nsColor.blueComponent, alpha: nsColor.alphaComponent)
  }
}
```

- [ ] **Step 2: InspectorView 본체** — `Panels/InspectorView.swift`

```swift
import SwiftUI
import VectaEngine

enum InspectorLayout {
  static let sectionSpacing: CGFloat = 14
  static let fieldWidth: CGFloat = 64
  static let padding: CGFloat = 10
}

/// 우측 인스펙터 (스펙 §8) — 면/선/불투명도/변환 수치. 패스파인더·정렬은 M5.
struct InspectorView: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    ScrollView {
      if store.selection.isEmpty {
        Text("선택된 객체 없음")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(.top, 24)
      } else {
        VStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
          if let style = store.selectionPathStyle {
            FillSection(store: store, style: style)
            Divider()
            StrokeSection(store: store, style: style)
            Divider()
            OpacitySection(store: store, style: style)
            Divider()
          }
          TransformSection(store: store)
        }
        .padding(InspectorLayout.padding)
      }
    }
  }
}

/// 불투명도 — 슬라이더 드래그는 transient로 묶어 undo 1단계.
struct OpacitySection: View {
  @ObservedObject var store: DocumentStore
  let style: Style

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("불투명도").font(.headline)
      HStack {
        Slider(
          value: opacityBinding, in: 0...1,
          onEditingChanged: { editing in
            if editing {
              store.beginTransient()
            } else {
              store.commitTransient(actionName: "불투명도")
            }
          })
        Text(style.opacity.formatted(.percent.precision(.fractionLength(0))))
          .monospacedDigit()
          .frame(width: 44, alignment: .trailing)
      }
    }
  }

  private var opacityBinding: Binding<Double> {
    Binding(
      get: { style.opacity },
      set: { newValue in
        store.updateSelectionStylesTransient { style, _ in
          style.opacity = newValue
        }
      })
  }
}

/// X/Y/W/H/회전 수치 입력 — 커밋(Enter/포커스 아웃) 시 1회 적용.
struct TransformSection: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("변환").font(.headline)
      if let bounds = store.selectionBounds {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
          GridRow {
            numericField("X", value: bounds.minX) { store.moveSelection(x: $0) }
            numericField("Y", value: bounds.minY) { store.moveSelection(y: $0) }
          }
          GridRow {
            numericField("W", value: bounds.width) { store.resizeSelection(width: $0) }
            numericField("H", value: bounds.height) { store.resizeSelection(height: $0) }
          }
          GridRow {
            numericField("회전", value: currentRotationDegrees) { newAngle in
              store.rotateSelection(byDegrees: newAngle - currentRotationDegrees)
            }
          }
        }
      }
    }
  }

  /// 단일 선택이면 그 노드의 절대각, 다중이면 0 (입력값 = 추가 회전 델타).
  private var currentRotationDegrees: CGFloat {
    guard store.selection.count == 1, let id = store.selection.first,
      let node = store.document.topLevelNode(id: id)
    else { return 0 }
    return CGFloat(node.rotationDegrees)
  }

  private func numericField(
    _ label: String, value: CGFloat, commit: @escaping (CGFloat) -> Void
  ) -> some View {
    HStack(spacing: 4) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(minWidth: 24, alignment: .trailing)
      CommittingNumberField(value: value, onCommit: commit)
        .frame(width: InspectorLayout.fieldWidth)
    }
  }
}

/// Enter/포커스 아웃에서만 커밋하는 숫자 필드 — 키스트로크마다 apply 방지.
struct CommittingNumberField: View {
  let value: CGFloat
  let onCommit: (CGFloat) -> Void
  @State private var text = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    TextField("", text: $text)
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.trailing)
      .focused($isFocused)
      .onSubmit(commit)
      .onChange(of: isFocused) { _, focused in
        if !focused { commit() }
      }
      .onChange(of: value, initial: true) { _, newValue in
        if !isFocused { text = format(newValue) }
      }
  }

  private func commit() {
    guard let parsed = Double(text) else {
      text = format(value)  // 파싱 실패 → 현재 값 복원
      return
    }
    onCommit(CGFloat(parsed))
  }

  private func format(_ number: CGFloat) -> String {
    number.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
  }
}
```

- [ ] **Step 3: FillSection + 그라디언트 에디터** — `Panels/FillSection.swift`

```swift
import SwiftUI
import VectaEngine

/// 인스펙터 면(fill) 섹션 — 페인트 타입 전환 + 단색/그라디언트 에디터.
struct FillSection: View {
  @ObservedObject var store: DocumentStore
  let style: Style

  private enum PaintKind: String, CaseIterable, Identifiable {
    case none = "없음"
    case color = "단색"
    case linear = "선형"
    case radial = "원형"
    var id: String { rawValue }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("면").font(.headline)
      Picker("페인트", selection: kindBinding) {
        ForEach(PaintKind.allCases) { kind in
          Text(kind.rawValue).tag(kind)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      switch style.fill {
      case .color(let rgba):
        ColorPicker("색", selection: colorBinding(current: rgba))
      case .linearGradient(let gradient):
        GradientEditor(store: store, gradient: gradient, isRadial: false)
      case .radialGradient(let gradient):
        GradientEditor(store: store, gradient: gradient, isRadial: true)
      case nil:
        EmptyView()
      }
    }
  }

  private var currentKind: PaintKind {
    switch style.fill {
    case nil: return .none
    case .color: return .color
    case .linearGradient: return .linear
    case .radialGradient: return .radial
    }
  }

  private var kindBinding: Binding<PaintKind> {
    Binding(
      get: { currentKind },
      set: { newKind in
        guard newKind != currentKind else { return }
        store.updateSelectionStyles(actionName: "면 페인트 변경") { style, bounds in
          style.fill = Self.convertedFill(style.fill, to: newKind, bounds: bounds)
        }
      })
  }

  /// 페인트 타입 전환 — 기존 색(또는 첫 스톱 색)을 보존한다.
  private static func convertedFill(
    _ fill: Paint?, to kind: PaintKind, bounds: CGRect
  ) -> Paint? {
    let baseColor: RGBA
    switch fill {
    case .color(let rgba):
      baseColor = rgba
    case .linearGradient(let gradient), .radialGradient(let gradient):
      baseColor = gradient.stops.first?.color ?? .black
    case nil:
      baseColor = .black
    }
    switch kind {
    case .none: return nil
    case .color: return .color(baseColor)
    case .linear: return .linearGradient(.defaultLinear(from: baseColor, in: bounds))
    case .radial: return .radialGradient(.defaultRadial(from: baseColor, in: bounds))
    }
  }

  private func colorBinding(current: RGBA) -> Binding<Color> {
    Binding(
      get: { current.swiftUIColor },
      set: { newColor in
        let rgba = RGBA(newColor)
        store.updateSelectionStyles(actionName: "면 색 변경") { style, _ in
          style.fill = .color(rgba)
        }
      })
  }
}

/// 그라디언트 스톱·각도 에디터. 스톱은 최소 2개 유지.
struct GradientEditor: View {
  @ObservedObject var store: DocumentStore
  let gradient: VectaEngine.Gradient
  let isRadial: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !isRadial {
        angleRow
      }
      ForEach(Array(gradient.stops.enumerated()), id: \.offset) { index, stop in
        stopRow(index: index, stop: stop)
      }
      Button {
        addStop()
      } label: {
        Label("스톱 추가", systemImage: "plus")
      }
      .buttonStyle(.borderless)
    }
  }

  private var angleRow: some View {
    HStack(spacing: 4) {
      Text("각도").foregroundStyle(.secondary)
      CommittingNumberField(
        value: CGFloat(GradientGeometry.angleDegrees(of: gradient))
      ) { newAngle in
        updateGradient(actionName: "그라디언트 각도") { gradient, bounds in
          let line = GradientGeometry.line(angleDegrees: Double(newAngle), in: bounds)
          gradient.start = line.start
          gradient.end = line.end
        }
      }
      .frame(width: InspectorLayout.fieldWidth)
      Text("°").foregroundStyle(.secondary)
    }
  }

  private func stopRow(index: Int, stop: GradientStop) -> some View {
    HStack(spacing: 6) {
      ColorPicker(
        "",
        selection: Binding(
          get: { stop.color.swiftUIColor },
          set: { newColor in
            let rgba = RGBA(newColor)
            updateGradient(actionName: "스톱 색 변경") { gradient, _ in
              guard gradient.stops.indices.contains(index) else { return }
              gradient.stops[index].color = rgba
            }
          })
      )
      .labelsHidden()
      .frame(width: 36)
      Slider(
        value: Binding(
          get: { stop.location },
          set: { newLocation in
            updateGradientTransient { gradient, _ in
              guard gradient.stops.indices.contains(index) else { return }
              gradient.stops[index].location = min(max(newLocation, 0), 1)
            }
          }),
        in: 0...1,
        onEditingChanged: { editing in
          if editing {
            store.beginTransient()
          } else {
            store.commitTransient(actionName: "스톱 위치 변경")
          }
        })
      Button {
        updateGradient(actionName: "스톱 삭제") { gradient, _ in
          guard gradient.stops.count > 2, gradient.stops.indices.contains(index) else { return }
          gradient.stops.remove(at: index)
        }
      } label: {
        Image(systemName: "minus.circle")
      }
      .buttonStyle(.borderless)
      .disabled(gradient.stops.count <= 2)
    }
  }

  private func addStop() {
    updateGradient(actionName: "스톱 추가") { gradient, _ in
      let color = gradient.stops.last?.color ?? .black
      gradient.stops.append(GradientStop(location: 0.5, color: color))
      gradient.stops.sort { $0.location < $1.location }
    }
  }

  /// 현재 fill의 그라디언트(선형/원형 불문)를 제자리 변경한다.
  private func updateGradient(
    actionName: String,
    _ change: @escaping (inout VectaEngine.Gradient, CGRect) -> Void
  ) {
    store.updateSelectionStyles(actionName: actionName) { style, bounds in
      Self.mutateGradient(in: &style, bounds: bounds, change)
    }
  }

  private func updateGradientTransient(
    _ change: @escaping (inout VectaEngine.Gradient, CGRect) -> Void
  ) {
    store.updateSelectionStylesTransient { style, bounds in
      Self.mutateGradient(in: &style, bounds: bounds, change)
    }
  }

  private static func mutateGradient(
    in style: inout Style, bounds: CGRect,
    _ change: (inout VectaEngine.Gradient, CGRect) -> Void
  ) {
    switch style.fill {
    case .linearGradient(var gradient):
      change(&gradient, bounds)
      style.fill = .linearGradient(gradient)
    case .radialGradient(var gradient):
      change(&gradient, bounds)
      style.fill = .radialGradient(gradient)
    default:
      break
    }
  }
}
```

(주의: `Gradient`는 SwiftUI에도 있어 `VectaEngine.Gradient`로 한정해야 한다.)

- [ ] **Step 4: StrokeSection** — `Panels/StrokeSection.swift`

```swift
import SwiftUI
import VectaEngine

/// 인스펙터 선(stroke) 섹션 — 켜기/끄기, 색, 두께, 캡, 조인.
struct StrokeSection: View {
  @ObservedObject var store: DocumentStore
  let style: Style

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("선").font(.headline)
        Spacer()
        Toggle("선 사용", isOn: enabledBinding)
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.mini)
      }
      if let stroke = style.stroke {
        ColorPicker("색", selection: colorBinding(current: stroke.paint))
        HStack(spacing: 4) {
          Text("두께").foregroundStyle(.secondary)
          CommittingNumberField(value: stroke.width) { newWidth in
            guard newWidth > 0 else { return }
            update(actionName: "선 두께 변경") { $0.width = newWidth }
          }
          .frame(width: InspectorLayout.fieldWidth)
          Text("pt").foregroundStyle(.secondary)
        }
        Picker("캡", selection: capBinding(current: stroke.cap)) {
          Text("버트").tag(LineCap.butt)
          Text("라운드").tag(LineCap.round)
          Text("스퀘어").tag(LineCap.square)
        }
        .pickerStyle(.segmented)
        Picker("조인", selection: joinBinding(current: stroke.join)) {
          Text("마이터").tag(LineJoin.miter)
          Text("라운드").tag(LineJoin.round)
          Text("베벨").tag(LineJoin.bevel)
        }
        .pickerStyle(.segmented)
      }
    }
  }

  private var enabledBinding: Binding<Bool> {
    Binding(
      get: { style.stroke != nil },
      set: { enabled in
        store.updateSelectionStyles(actionName: enabled ? "선 추가" : "선 제거") { style, _ in
          style.stroke = enabled ? Stroke(paint: .black, width: 1) : nil
        }
      })
  }

  private func colorBinding(current: RGBA) -> Binding<Color> {
    Binding(
      get: { current.swiftUIColor },
      set: { newColor in
        let rgba = RGBA(newColor)
        update(actionName: "선 색 변경") { $0.paint = rgba }
      })
  }

  private func capBinding(current: LineCap) -> Binding<LineCap> {
    Binding(
      get: { current },
      set: { newCap in update(actionName: "선 캡 변경") { $0.cap = newCap } })
  }

  private func joinBinding(current: LineJoin) -> Binding<LineJoin> {
    Binding(
      get: { current },
      set: { newJoin in update(actionName: "선 조인 변경") { $0.join = newJoin } })
  }

  private func update(actionName: String, _ change: @escaping (inout Stroke) -> Void) {
    store.updateSelectionStyles(actionName: actionName) { style, _ in
      guard var stroke = style.stroke else { return }
      change(&stroke)
      style.stroke = stroke
    }
  }
}
```

- [ ] **Step 5: SidePanelView + 도킹 교체** — `Panels/SidePanelView.swift`

```swift
import SwiftUI
import VectaEngine

/// 우측 도킹 패널 — 위 인스펙터, 아래 레이어 패널 (스펙 §8).
struct SidePanelView: View {
  @ObservedObject var store: DocumentStore

  var body: some View {
    VSplitView {
      InspectorView(store: store)
        .frame(minHeight: 280)
      LayerPanelView(store: store)
        .frame(minHeight: 140)
    }
  }
}
```

`VectaDocument.makeContentView`의 sidePanel 줄 교체:

```swift
    let sidePanel = NSHostingView(rootView: SidePanelView(store: store))
```

- [ ] **Step 6: 빌드 + 엔진 회귀** — Task 10 Step 3과 동일 명령. 전체 PASS + BUILD SUCCEEDED

- [ ] **Step 7: 실행 스모크** — 앱 실행 → 생존 확인 → 종료

- [ ] **Step 8: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: 인스펙터 — 면·선·그라디언트·불투명도·변환 수치 입력"
```

---

### Task 13: 통합 회귀 + README + PR

- [ ] **Step 1: 전체 회귀** — 엔진 `swift test` 전체 PASS + 앱 xcodebuild BUILD SUCCEEDED

- [ ] **Step 2: 수동 검증 체크리스트** (사용자 수행)

1. 사각형 생성 → 인스펙터 면을 "선형"으로 전환 → 그라디언트 표시, 각도 45 입력·스톱 색 변경 반영
2. "원형" 그라디언트 적용 → ⌘S 저장 → 재열기 → 100% 복원
3. 불투명도 슬라이더 드래그 → ⌘Z 1회로 원복 (undo 1단계)
4. X/Y/W/H/회전 수치 입력 반영, 각각 ⌘Z 1단계
5. 선 두께/캡/조인/색 변경 반영
6. 레이어 추가(+) → 새 도형이 새(활성) 레이어에 생성됨
7. 레이어 이름 더블클릭 편집, 드래그 순서 변경 → 캔버스 겹침 순서 변화
8. 눈 끄기 → 렌더 제외·선택 해제, 자물쇠 → 클릭 선택 불가·해당 레이어에 그리기 무시
9. 도형 2개 선택 ⌘G → 그룹 통째 이동, ⇧⌘G → 제자리 해제, ⌘]/⌘[ 순서 변경
10. A(직접 선택)로 그룹 내부 패스 클릭 → 앵커 편집, ⌘Z 복원
11. 그룹+그라디언트 문서 저장 → 재열기 100% 복원

- [ ] **Step 3: README 갱신** — M2 줄 아래에 추가:

```markdown
- [x] M3 스타일·구조: 그라디언트 렌더/인스펙터/레이어 패널/그룹·순서
```

- [ ] **Step 4: 이슈 #4 이월 기록 + PR 생성**

```bash
gh issue comment 4 --body "M3 구현 노트:
- 레이어 패널의 노드 트리(스펙 §8)는 M5 이후로 이월 (이슈 #4 작업 목록 기준 구현)
- 그라디언트 렌더는 CGGradient 채택 (스펙 §6 표기 갱신 — CGShading 수동 보간 회피)
- 직접 선택 재진입 시 편집 대상 초기화 유지로 결정
- ColorPicker 연속 변경은 변경당 undo 1단계 (편집 세션 API 부재 — 추후 개선 후보)"

git push -u origin m3-style-layers
gh pr create --base main --title "feat: M3 스타일·구조 — 인스펙터·레이어 패널·그라디언트" \
  --body "$(cat <<'EOF'
## Summary
- 엔진: 그라디언트 렌더(CGGradient)·각도 기하, 그룹/해제/앞뒤 순서, 활성 레이어(layers[0] 하드코딩 제거), 스타일·변환·레이어 명령(모두 apply = undo 1단계), 직접 선택 그룹 내부 진입(월드 변환), 펜 이중 다운 가드
- 앱: 우측 패널(인스펙터 + 레이어), 오브젝트 메뉴(⌘G/⇧⌘G/⌘]/⌘[)
- 스펙 §6 그라디언트 표기 CGShading → CGGradient 갱신 (근거 포함)

## Test Plan
- [x] 엔진 swift test 전체 통과 (기존 142 + 신규 ~64)
- [x] xcodebuild BUILD SUCCEEDED
- [ ] 수동 체크리스트 11항목 (plan Task 13 Step 2)

Closes #4

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 완료 기준 (M3 Definition of Done)

- 엔진 테스트 전체 그린 (기존 142개 + 신규 ~64개)
- 수동 체크리스트 11항목 통과
- 모든 패널·메뉴 변경 = apply 1회 = undo 1단계 (슬라이더 드래그는 transient로 1단계)
- 그라디언트·그룹 문서의 저장→재열기 100% 라운드트립 (JSON 임베드 경유)
- PR이 이슈 #4를 닫음

## M4 예고

외부 .ai 임포트 (이슈 #5): 패스/스타일 → 클립·폼 → 그라디언트 → 이미지 → 텍스트 순 파서 확장 + ImportReport UI. 레이어 패널 노드 트리·그룹 클립 해제 정책 재논의도 그때.
