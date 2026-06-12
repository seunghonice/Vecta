# Vecta M4a — 외부 .ai 임포트 파서 코어 (패스·스타일·클립·폼) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 외부 도구가 만든 .ai/PDF 파일을 CGPDFScanner 기반 콘텐츠 스트림 파서로 가져온다 — 패스/스타일/클립/폼 XObject까지. 미지원 요소(그라디언트·이미지·텍스트)는 ImportReport로 수집해 비모달 배너로 표시한다. .pdf 열기, 다중 페이지 경고, 페이로드 크기 상한, 손상 JSON 폴백 포함. (GitHub 이슈 #5, PR은 `Closes #5`. 그라디언트·이미지·텍스트 파싱은 M4b — 이슈 #11)

**Architecture:** 파서는 VectaEngine/ImportAI에 두고 수제 미니멀 PDF 픽스처로 헤드리스 테스트한다(스펙 §11). `ContentStreamParser`(class — CGPDFScanner C 콜백의 info 포인터 대상)가 그래픽 상태 스택을 유지하며 페인팅 연산자마다 PathNode를 만들고, CTM·페이지 플립은 노드 좌표에 베이크한다. 클립은 CGPath 교차로 누적해 같은 클립의 연속 노드를 GroupNode로 묶는다. `AIFileReader`는 임베드 JSON 우선, 부재·손상·과대 시 파서 폴백.

**Tech Stack:** Swift 6 (언어 모드 v5), Swift Testing, CoreGraphics(CGPDFDocument/CGPDFScanner/CGPath 불리언 — macOS 13+, 엔진 플랫폼 .v14), SwiftUI 배너, XcodeGen.

**참조:** 스펙 `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` §5(ImportAI)·§10(에러)·§11(테스트)·§12-M4, 이슈 #5(M4a 재범위), M3 계획(컨벤션).

---

## 커밋 규칙 (전역 규칙 — 기존과 동일)

매 커밋 전: ① `cd VectaEngine && swift build`(앱 변경 시 xcodebuild 추가) → ② `swift test` → ③ `swift format --in-place --recursive Sources Tests`(앱은 `VectaApp/Sources`) → ④ commit. 한국어 메시지+접두사, Co-Authored-By 금지. 테스트 실패 시 수정 후 ①부터 재수행.

## 결정 기록 (이 계획에서 확정)

| 결정 | 근거 |
|---|---|
| CTM·페이지 플립을 노드 좌표에 베이크 (transform = identity) | 임포트 목표는 시각 충실도. 베지어는 아핀 변환에 닫혀 있어 제어점 변환으로 정확. 폼 XObject는 구조 보존을 위해 GroupNode(identity)로만 묶음 |
| 선폭·대시 길이는 CTM의 √\|det\| 근사 스케일 | 비균등 스케일 오차 허용 — 기존 히트테스트 허용 오차 관례와 동일 |
| `PathNode.fillRule` 모델 추가 (winding/evenOdd, 디코드 기본 winding) | 스펙 §5의 짝홀(f*) 매핑 요구. §4 모델에 없던 필드 — 스펙도 갱신. 구버전 JSON은 decodeIfPresent로 호환 |
| 클립 누적 = CGPath `normalized(using:)` + `intersection` (macOS 13+) | 정확 교차. W*의 짝홀 해석은 normalized로 winding 등가 변환 후 교차. 같은 클립의 연속 노드는 단일 GroupNode로 그룹화 |
| 폼 XObject의 /BBox는 클립으로 적용, /Matrix는 CTM에 합성 | PDF 의미론 그대로 — 폼 밖 드로잉 누출 방지 |
| `gs`는 ca(fill alpha) → opacity만 반영, CA·기타 키 무시 | 모델 opacity는 노드 단위 하나 (스펙 §4) |
| 미지원 색공간(ICC 등)은 리포트 + 직전 색 유지; 패턴 채움(scn)은 unsupportedShading 리포트 | M4b에서 shading 패턴 지원 예정 |
| `d`의 dash phase 무시 | 모델 Stroke에 phase 없음 (스펙 §4) |
| 텍스트(BT)·이미지(Do image/BI)·셰이딩(sh)은 건너뛰고 리포트 | M4b 범위 (이슈 #11). 조용한 데이터 손실 금지 (스펙 §5) |
| 페이로드 상한 64MB (base64 기준) — 초과·손상 시 파서 폴백 + 리포트 | M1 리뷰 보류 항목. 악의적 파일의 메모리 폭주 방어 |
| .pdf 문서 타입은 Viewer 역할 (읽기 전용 — 저장은 .ai로 다른 이름 저장) | ExportAI는 .ai만 쓴다 (스펙 §6) |
| 미등록 연산자는 무보고 스킵 | CGPDFScanner는 등록된 콜백만 호출 — 알려진 미지원(sh/BT/BI/이미지 Do)만 등록해 리포트 |

## 파일 구조 (M4a 추가/변경분)

```
VectaEngine/Sources/VectaEngine/
├── Model/Node.swift                  (수정)  # FillRule + PathNode.fillRule (호환 디코드)
├── Geometry/BezierPath+CGPath.swift  (수정)  # init(cgPath:) 역변환, applying(_:)
├── Rendering/SceneRenderer.swift     (수정)  # fillRule 반영 (fillPath(using:)/clip(using:))
├── Geometry/HitTesting.swift         (수정)  # fillRule 반영 (contains(using:))
├── ExportAI/NativeScenePayload.swift (수정)  # 페이로드 상한
└── ImportAI/
    ├── ImportError.swift             (수정)  # payloadTooLarge·encryptedPDF·unreadablePDF
    ├── ImportReport.swift            (생성)  # ImportIssue/ImportReport/ImportResult
    ├── PDFColor.swift                (생성)  # 색공간 + 성분→RGBA (internal)
    ├── PDFPathBuilder.swift          (생성)  # m l c v y h re → BezierPath (internal)
    ├── ContentStreamParser.swift     (생성)  # 스캐너 콜백 + 상태 머신 (internal class)
    ├── PDFDocumentImporter.swift     (생성)  # CGPDFDocument → ImportResult (internal)
    └── AIFileReader.swift            (수정)  # read(from:) → ImportResult, 폴백 연결

VectaEngine/Tests/VectaEngineTests/
├── PDFFixture.swift                  (생성)  # 수제 미니멀 PDF 빌더 (xref 오프셋 계산)
├── FillRuleTests.swift               (생성)
├── BezierPathCGPathTests.swift       (생성)
├── ImportReportTests.swift           (생성)
├── PDFColorTests.swift               (생성)
├── PDFPathBuilderTests.swift         (생성)
├── ContentStreamParserTests.swift    (생성)  # 코어/클립/폼/리포트
└── AIFileReaderImportTests.swift     (생성)  # 통합·폴백·다중페이지·암호화

VectaApp/
├── project.yml                       (수정)  # .pdf 문서 타입 (Viewer)
└── Sources/
    ├── Document/VectaDocument.swift  (수정)  # read → ImportResult, 배너 통합
    └── Panels/ImportReportBanner.swift (생성)
```

핵심 계약:
- 모델 top-left 좌표, PDF는 bottom-left — 파서가 `pageFlip`으로 변환 (스펙 §4).
- 파서 산출 노드는 `transform = identity` (좌표 베이크).
- 테스트 베이스라인: 엔진 215개 그린. 브랜치 `m4a-import-core` (base: `m3-style-layers` — PR #10 미머지 시 스택).
- 엔진 태스크는 엔진만 빌드한다. Task 11에서 `AIFileReader.document(from:)`가 `read(from:)`로 바뀌면 앱은 Task 12까지 일시적으로 빌드가 깨진다 (브랜치 중간 상태 허용).

---

### Task 1: FillRule — 모델·렌더러·히트테스트 (PDF f* 대비)

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Model/Node.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Rendering/SceneRenderer.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Geometry/HitTesting.swift`
- Modify: `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` (§4 PathNode)
- Test: `VectaEngine/Tests/VectaEngineTests/FillRuleTests.swift` (생성)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 동일 방향 사각형 2개 (도넛) — winding은 전체 채움, evenOdd는 구멍.
private func donutNode(fillRule: FillRule) -> PathNode {
  let outer = BezierPath.rectangle(CGRect(x: 20, y: 20, width: 160, height: 160))
  let inner = BezierPath.rectangle(CGRect(x: 70, y: 70, width: 60, height: 60))
  let donut = BezierPath(subpaths: outer.subpaths + inner.subpaths)
  return PathNode(
    path: donut, style: Style(fill: .color(RGBA(red: 1, green: 0, blue: 0))),
    fillRule: fillRule)
}

@Test func evenOddFillRendersHole() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [.path(donutNode(fillRule: .evenOdd))]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  #expect(pixelColor(x: 40, y: 100, in: context).red > 230)  // 링
  #expect(pixelColor(x: 100, y: 100, in: context).alpha == 0)  // 구멍
}

@Test func windingFillHasNoHole() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [.path(donutNode(fillRule: .winding))]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
  #expect(pixelColor(x: 100, y: 100, in: context).red > 230)  // 동일 방향 → 채워짐
}

@Test func evenOddHitTestMissesHole() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  let node = donutNode(fillRule: .evenOdd)
  document.layers[0].nodes = [.path(node)]
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 40, y: 100), in: document, tolerance: 0)
      == node.id)
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 100, y: 100), in: document, tolerance: 0)
      == nil)
}

@Test func pathNodeDecodesLegacyJSONWithWindingDefault() throws {
  // fillRule 키가 없는 구버전 JSON — winding으로 디코드 (저장 파일 호환)
  let legacy = PathNode(
    path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
    style: Style(fill: .color(.black)))
  var json = try JSONSerialization.jsonObject(
    with: JSONEncoder().encode(legacy)) as! [String: Any]
  json.removeValue(forKey: "fillRule")
  let stripped = try JSONSerialization.data(withJSONObject: json)
  let decoded = try JSONDecoder().decode(PathNode.self, from: stripped)
  #expect(decoded.fillRule == .winding)
  #expect(decoded.id == legacy.id)
}

@Test func fillRuleRoundTripsThroughCodable() throws {
  let node = donutNode(fillRule: .evenOdd)
  let decoded = try JSONDecoder().decode(
    PathNode.self, from: JSONEncoder().encode(node))
  #expect(decoded.fillRule == .evenOdd)
  #expect(decoded == node)
}
```

- [ ] **Step 2: 실패 확인** — `cd VectaEngine && swift test` → FAIL (`FillRule` 없음)

- [ ] **Step 3: 모델 수정** — `Model/Node.swift`의 `PathNode`를 다음으로 교체:

```swift
/// 면 채움 규칙. PDF의 f(winding)/f*(even-odd) 매핑 (스펙 §5).
public enum FillRule: String, Codable, Sendable {
  case winding
  case evenOdd
}

public struct PathNode: Equatable, Codable, Sendable {
  public let id: NodeID
  public var path: BezierPath
  public var style: Style
  public var transform: Transform2D
  /// M4a에 추가 — 기존 파일(키 없음)은 winding으로 디코드된다.
  public var fillRule: FillRule

  public init(
    id: NodeID = NodeID(), path: BezierPath, style: Style,
    transform: Transform2D = .identity, fillRule: FillRule = .winding
  ) {
    self.id = id
    self.path = path
    self.style = style
    self.transform = transform
    self.fillRule = fillRule
  }

  private enum CodingKeys: String, CodingKey {
    case id, path, style, transform, fillRule
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(NodeID.self, forKey: .id)
    path = try container.decode(BezierPath.self, forKey: .path)
    style = try container.decode(Style.self, forKey: .style)
    transform = try container.decode(Transform2D.self, forKey: .transform)
    fillRule = try container.decodeIfPresent(FillRule.self, forKey: .fillRule) ?? .winding
  }
}
```

- [ ] **Step 4: 렌더러 반영** — `SceneRenderer.swift`:

`render(_ pathNode:)`의 fill 분기를 fillRule 전달로 교체:

```swift
    if let fill = pathNode.style.fill {
      renderFill(fill, path: pathNode.path, fillRule: pathNode.fillRule, in: context)
    }
```

`renderFill`/`renderGradientFill` 시그니처에 fillRule 추가 — `fillPath()`는 `fillPath(using: fillRule.cgFillRule)`로, 그라디언트 클립은 `clip(using: fillRule.cgFillRule)`로:

```swift
  private static func renderFill(
    _ paint: Paint, path: BezierPath, fillRule: FillRule, in context: CGContext
  ) {
    switch paint {
    case .color(let color):
      context.setFillColor(color.cgColor)
      // fillPath()/strokePath()는 current path를 소비하므로 각 함수가 독립적으로 path를 추가해야 한다.
      context.addPath(path.cgPath)
      context.fillPath(using: fillRule.cgFillRule)
    case .linearGradient(let gradient):
      renderGradientFill(gradient, isRadial: false, path: path, fillRule: fillRule, in: context)
    case .radialGradient(let gradient):
      renderGradientFill(gradient, isRadial: true, path: path, fillRule: fillRule, in: context)
    }
  }
```

`renderGradientFill`도 `fillRule: FillRule` 파라미터를 받아 퇴화 단색 분기는 `fillPath(using: fillRule.cgFillRule)`, 클립 분기는 `context.clip(using: fillRule.cgFillRule)` 사용. 파일 하단에 extension 추가:

```swift
extension FillRule {
  var cgFillRule: CGPathFillRule {
    switch self {
    case .winding: return .winding
    case .evenOdd: return .evenOdd
    }
  }
}
```

- [ ] **Step 5: 히트테스트 반영** — `HitTesting.swift`의 `hits(_ pathNode:)`에서 fill 판정을:

```swift
    if pathNode.style.fill != nil,
      cgPath.contains(local, using: pathNode.fillRule.cgFillRule)
    {
      return true
    }
```

- [ ] **Step 6: 스펙 §4 갱신** — PathNode 줄을 다음으로 교체:

```
struct PathNode  { let id: NodeID; var path: BezierPath
                   var style: Style; var transform: CGAffineTransform
                   var fillRule: FillRule }   // winding|evenOdd (M4a — PDF f* 매핑)
```

- [ ] **Step 7: 통과 확인** — `swift test` → 전체 PASS (220개 = 215 + 5)

- [ ] **Step 8: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PathNode fillRule 추가 — 짝홀 채움 렌더·히트테스트·호환 디코드"
```

---

### Task 2: BezierPath ← CGPath 역변환 + applying

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Geometry/BezierPath+CGPath.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/BezierPathCGPathTests.swift` (생성)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

@Test func rectangleRoundTripsThroughCGPath() {
  let original = BezierPath.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50))
  let roundTripped = BezierPath(cgPath: original.cgPath)
  #expect(roundTripped == original)
}

@Test func ellipseRoundTripsThroughCGPath() {
  let original = BezierPath.ellipse(in: CGRect(x: 0, y: 0, width: 80, height: 60))
  let roundTripped = BezierPath(cgPath: original.cgPath)
  #expect(roundTripped == original)
}

@Test func quadCurveIsPromotedToCubic() {
  let cgPath = CGMutablePath()
  cgPath.move(to: .zero)
  cgPath.addQuadCurve(to: CGPoint(x: 90, y: 0), control: CGPoint(x: 45, y: 60))
  let path = BezierPath(cgPath: cgPath)
  guard case .curve(let to, let control1, let control2) = path.subpaths[0].segments[1] else {
    Issue.record("3차 곡선이 아님")
    return
  }
  #expect(to == CGPoint(x: 90, y: 0))
  // c1 = p0 + 2/3(q − p0) = (30, 40), c2 = p + 2/3(q − p) = (60, 40)
  #expect(abs(control1.x - 30) < 0.0001 && abs(control1.y - 40) < 0.0001)
  #expect(abs(control2.x - 60) < 0.0001 && abs(control2.y - 40) < 0.0001)
}

@Test func multipleSubpathsArePreserved() {
  let cgPath = CGMutablePath()
  cgPath.addRect(CGRect(x: 0, y: 0, width: 10, height: 10))
  cgPath.move(to: CGPoint(x: 50, y: 50))
  cgPath.addLine(to: CGPoint(x: 80, y: 50))
  let path = BezierPath(cgPath: cgPath)
  #expect(path.subpaths.count == 2)
  #expect(path.subpaths[0].isClosed)
  #expect(!path.subpaths[1].isClosed)
}

@Test func segmentAfterCloseStartsNewSubpathAtStartPoint() {
  let cgPath = CGMutablePath()
  cgPath.move(to: .zero)
  cgPath.addLine(to: CGPoint(x: 10, y: 0))
  cgPath.closeSubpath()
  cgPath.addLine(to: CGPoint(x: 0, y: 20))  // 닫힘 뒤 — 시작점에서 새 subpath
  let path = BezierPath(cgPath: cgPath)
  #expect(path.subpaths.count == 2)
  #expect(path.subpaths[1].segments[0] == .move(to: .zero))
  #expect(path.subpaths[1].segments[1] == .line(to: CGPoint(x: 0, y: 20)))
}

@Test func applyingTransformsEveryPoint() {
  let path = BezierPath.ellipse(in: CGRect(x: 0, y: 0, width: 40, height: 40))
  let moved = path.applying(CGAffineTransform(translationX: 100, y: 50))
  #expect(moved.bounds == CGRect(x: 100, y: 50, width: 40, height: 40))
  #expect(moved.subpaths[0].segments.count == path.subpaths[0].segments.count)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`init(cgPath:)` 없음)

- [ ] **Step 3: 구현** — `BezierPath+CGPath.swift` 끝에 추가:

```swift
extension BezierPath {
  /// CGPath → BezierPath 역변환 (클립 교차 결과 수용 등 — M4a).
  /// 2차(quad) 곡선은 3차로 승격: c1 = p0 + ⅔(q − p0), c2 = p + ⅔(q − p).
  public init(cgPath: CGPath) {
    var subpaths: [Subpath] = []
    var segments: [PathSegment] = []
    var isClosed = false
    var currentPoint = CGPoint.zero
    var subpathStart = CGPoint.zero

    func flush() {
      if !segments.isEmpty {
        subpaths.append(Subpath(segments: segments, isClosed: isClosed))
      }
      segments = []
      isClosed = false
    }
    // 닫힘 직후처럼 세그먼트가 비어 있으면 현재 점에서 새 subpath를 연다.
    func ensureOpenSubpath() {
      if segments.isEmpty {
        segments = [.move(to: currentPoint)]
        subpathStart = currentPoint
      }
    }

    cgPath.applyWithBlock { elementPointer in
      let element = elementPointer.pointee
      switch element.type {
      case .moveToPoint:
        flush()
        currentPoint = element.points[0]
        subpathStart = currentPoint
        segments = [.move(to: currentPoint)]
      case .addLineToPoint:
        ensureOpenSubpath()
        currentPoint = element.points[0]
        segments.append(.line(to: currentPoint))
      case .addQuadCurveToPoint:
        ensureOpenSubpath()
        let control = element.points[0]
        let end = element.points[1]
        let control1 = CGPoint(
          x: currentPoint.x + 2 * (control.x - currentPoint.x) / 3,
          y: currentPoint.y + 2 * (control.y - currentPoint.y) / 3)
        let control2 = CGPoint(
          x: end.x + 2 * (control.x - end.x) / 3,
          y: end.y + 2 * (control.y - end.y) / 3)
        segments.append(.curve(to: end, control1: control1, control2: control2))
        currentPoint = end
      case .addCurveToPoint:
        ensureOpenSubpath()
        let end = element.points[2]
        segments.append(
          .curve(to: end, control1: element.points[0], control2: element.points[1]))
        currentPoint = end
      case .closeSubpath:
        isClosed = true
        flush()
        currentPoint = subpathStart
      @unknown default:
        break
      }
    }
    flush()
    self.init(subpaths: subpaths)
  }

  /// 모든 점에 아핀 변환 적용 — 베지어는 제어점 변환으로 정확 (CTM 베이크용).
  public func applying(_ transform: CGAffineTransform) -> BezierPath {
    BezierPath(
      subpaths: subpaths.map { subpath in
        Subpath(
          segments: subpath.segments.map { segment in
            switch segment {
            case .move(let to):
              return .move(to: to.applying(transform))
            case .line(let to):
              return .line(to: to.applying(transform))
            case .curve(let to, let control1, let control2):
              return .curve(
                to: to.applying(transform),
                control1: control1.applying(transform),
                control2: control2.applying(transform))
            }
          }, isClosed: subpath.isClosed)
      })
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (226개 = 220 + 6)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: CGPath→BezierPath 역변환과 아핀 적용 헬퍼"
```

---

### Task 3: ImportReport·ImportError 확장 + 페이로드 상한

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/ImportReport.swift`
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ImportError.swift`
- Modify: `VectaEngine/Sources/VectaEngine/ExportAI/NativeScenePayload.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ImportReportTests.swift` (생성)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Foundation
import Testing

@testable import VectaEngine

@Test func importReportCollectsIssues() {
  var report = ImportReport()
  #expect(report.isEmpty)
  report.add(.unsupportedShading, detail: "sh 연산자")
  report.add(.multiplePages, detail: "3페이지 중 1페이지만")
  #expect(report.issues.count == 2)
  #expect(report.issues[0].kind == .unsupportedShading)
  #expect(!report.isEmpty)
}

@Test func oversizedPayloadThrows() throws {
  // 정상 PDF 꼬리 구조를 흉내 낸 데이터에 상한 초과 base64 블록 삽입
  let huge = Data(
    repeating: UInt8(ascii: "A"), count: NativeScenePayload.maxPayloadBytes + 1)
  var data = Data("%PDF-1.4\n".utf8)
  data.append(Data("\(NativeScenePayload.beginMarker)\n%".utf8))
  data.append(huge)
  data.append(Data("\n\(NativeScenePayload.endMarker)\nstartxref\n0\n%%EOF".utf8))
  #expect(throws: ImportError.payloadTooLarge) {
    try NativeScenePayload.extract(from: data)
  }
}

@Test func payloadUnderCapStillExtracts() throws {
  // 기존 정상 경로 회귀 — 작은 문서는 그대로 추출
  let document = VectorDocument.empty()
  let pdf = try AIFileWriter.data(for: document)
  let extracted = try NativeScenePayload.extract(from: pdf)
  #expect(extracted == document)
}

@Test func importErrorMessagesAreKorean() {
  #expect(ImportError.payloadTooLarge.errorDescription?.isEmpty == false)
  #expect(ImportError.encryptedPDF.errorDescription?.isEmpty == false)
  #expect(ImportError.unreadablePDF.errorDescription?.isEmpty == false)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`ImportReport` 없음)

- [ ] **Step 3: ImportReport 구현** — `ImportAI/ImportReport.swift`:

```swift
/// 임포트 중 건너뛴 요소의 항목별 수집 (스펙 §5 — 조용한 데이터 손실 금지).
public struct ImportIssue: Equatable, Sendable {
  public enum Kind: String, Equatable, Sendable {
    case multiplePages
    case unsupportedShading
    case unsupportedImage
    case unsupportedText
    case unsupportedColorSpace
    case formRecursionLimit
    case corruptNativePayload
    case oversizedNativePayload
  }

  public var kind: Kind
  public var detail: String

  public init(kind: Kind, detail: String) {
    self.kind = kind
    self.detail = detail
  }
}

public struct ImportReport: Equatable, Sendable {
  public var issues: [ImportIssue]

  public init(issues: [ImportIssue] = []) {
    self.issues = issues
  }

  public static let empty = ImportReport()

  public var isEmpty: Bool { issues.isEmpty }

  public mutating func add(_ kind: ImportIssue.Kind, detail: String) {
    issues.append(ImportIssue(kind: kind, detail: detail))
  }
}

/// 임포트 결과 — 문서 + 리포트 (배너 표시용).
public struct ImportResult: Equatable, Sendable {
  public var document: VectorDocument
  public var report: ImportReport

  public init(document: VectorDocument, report: ImportReport) {
    self.document = document
    self.report = report
  }
}
```

- [ ] **Step 4: ImportError 확장** — `ImportError.swift`의 enum에 케이스·메시지 추가:

```swift
  case payloadTooLarge
  case encryptedPDF
  case unreadablePDF
```

```swift
    case .payloadTooLarge:
      return "파일에 저장된 Vecta 데이터가 비정상적으로 큽니다."
    case .encryptedPDF:
      return "암호로 보호된 파일은 열 수 없습니다."
    case .unreadablePDF:
      return "지원하지 않는 파일입니다. 파일이 손상되었을 수 있습니다."
```

또한 `noNativeData` 케이스의 메시지는 그대로 두되, M4a 이후 이 케이스는 더 이상 던져지지 않는다 (Task 11에서 AIFileReader가 파서 폴백으로 대체 — 케이스 자체는 Task 11에서 삭제).

- [ ] **Step 5: 페이로드 상한** — `NativeScenePayload.swift`에 상수 추가, `extract`의 base64 추출 직후 가드:

```swift
  /// 임베드 페이로드 상한 (M1 리뷰 보류 항목) — 비정상·악의적 파일의
  /// 메모리 폭주 방어. base64 텍스트 길이 기준 64MB.
  static let maxPayloadBytes = 64 * 1024 * 1024
```

```swift
    let base64 = data[beginRange.upperBound..<endRange.lowerBound]
    guard base64.count <= maxPayloadBytes else {
      throw ImportError.payloadTooLarge
    }
```

- [ ] **Step 6: 통과 확인** — `swift test` → 전체 PASS (230개 = 226 + 4)

- [ ] **Step 7: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: ImportReport 모델과 페이로드 상한·임포트 에러 확장"
```

---

### Task 4: 테스트 픽스처 — 수제 미니멀 PDF 빌더

**Files:**
- Create: `VectaEngine/Tests/VectaEngineTests/PDFFixture.swift`
- Test: 같은 파일에 셀프 테스트 2개

- [ ] **Step 1: 빌더 + 셀프 테스트 작성** (빌더는 테스트 지원 코드 — 셀프 테스트가 곧 검증이므로 RED 단계는 "CGPDFDocument가 못 여는 상태"가 아니라 작성 후 즉시 검증)

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 수제 미니멀 PDF (스펙 §11 — 연산자 케이스별 파싱 테스트용).
/// 객체 번호 규약: 1 카탈로그, 2 페이지 트리, 페이지 i(0부터)는
/// 3+2i(페이지)·4+2i(콘텐츠). extraObjects는 그 뒤 — 1페이지면 5번부터.
func makeTestPDF(
  pages: [String],
  mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
  resources: String = "<< >>",
  extraObjects: [String] = [],
  trailerExtra: String = ""
) -> Data {
  var objects: [String] = []
  let kids = (0..<pages.count).map { "\(3 + 2 * $0) 0 R" }.joined(separator: " ")
  objects.append("<< /Type /Catalog /Pages 2 0 R >>")
  objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
  for (index, content) in pages.enumerated() {
    let box =
      "[\(Int(mediaBox.minX)) \(Int(mediaBox.minY)) \(Int(mediaBox.maxX)) \(Int(mediaBox.maxY))]"
    objects.append(
      "<< /Type /Page /Parent 2 0 R /MediaBox \(box) "
        + "/Contents \(4 + 2 * index) 0 R /Resources \(resources) >>")
    objects.append("<< /Length \(content.utf8.count) >> stream\n\(content)\nendstream")
  }
  objects.append(contentsOf: extraObjects)

  var body = "%PDF-1.4\n"
  var offsets: [Int] = []
  for (index, object) in objects.enumerated() {
    offsets.append(body.utf8.count)
    body += "\(index + 1) 0 obj \(object) endobj\n"
  }
  let xrefOffset = body.utf8.count
  body += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
  for offset in offsets {
    body += String(format: "%010d 00000 n \n", offset)
  }
  body += "trailer << /Size \(objects.count + 1) /Root 1 0 R \(trailerExtra)>>\n"
  body += "startxref\n\(xrefOffset)\n%%EOF\n"
  return Data(body.utf8)
}

/// 콘텐츠 1개짜리 단축 헬퍼.
func makeTestPDF(
  content: String,
  mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
  resources: String = "<< >>",
  extraObjects: [String] = []
) -> Data {
  makeTestPDF(
    pages: [content], mediaBox: mediaBox, resources: resources, extraObjects: extraObjects)
}

@Test func fixtureOpensWithCGPDFDocument() {
  let data = makeTestPDF(content: "10 10 100 100 re f")
  let provider = CGDataProvider(data: data as CFData)!
  let pdf = CGPDFDocument(provider)
  #expect(pdf != nil)
  #expect(pdf?.numberOfPages == 1)
  #expect(pdf?.page(at: 1) != nil)
}

@Test func fixtureSupportsMultiplePages() {
  let data = makeTestPDF(pages: ["10 10 50 50 re f", "20 20 50 50 re f"])
  let provider = CGDataProvider(data: data as CFData)!
  let pdf = CGPDFDocument(provider)
  #expect(pdf?.numberOfPages == 2)
}
```

- [ ] **Step 2: 검증** — `swift test` → 전체 PASS (232개 = 230 + 2). 셀프 테스트가 실패하면 xref 오프셋·Length 계산을 수정한다 (CGPDFDocument는 엄격하지 않지만 startxref와 오브젝트 오프셋은 정확해야 한다).

- [ ] **Step 3: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "test: 수제 미니멀 PDF 픽스처 빌더 — xref 오프셋 계산"
```

---

### Task 5: PDFColor — 색공간 상태와 RGBA 변환

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/PDFColor.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PDFColorTests.swift` (생성)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

@Test func colorSpaceNamesMap() {
  #expect(PDFColorSpace.named("DeviceRGB") == .deviceRGB)
  #expect(PDFColorSpace.named("CalRGB") == .deviceRGB)
  #expect(PDFColorSpace.named("DeviceGray") == .deviceGray)
  #expect(PDFColorSpace.named("CalGray") == .deviceGray)
  #expect(PDFColorSpace.named("DeviceCMYK") == .deviceCMYK)
  #expect(PDFColorSpace.named("Pattern") == .pattern)
  #expect(PDFColorSpace.named("ICCBased") == .unsupported(name: "ICCBased"))
}

@Test func grayConvertsToEqualChannels() {
  #expect(
    PDFColorSpace.deviceGray.color(from: [0.5])
      == RGBA(red: 0.5, green: 0.5, blue: 0.5))
}

@Test func rgbPassesThrough() {
  #expect(
    PDFColorSpace.deviceRGB.color(from: [0.1, 0.2, 0.3])
      == RGBA(red: 0.1, green: 0.2, blue: 0.3))
}

@Test func cmykConvertsNaively() {
  // r = (1−c)(1−k): 시안(1,0,0,0) → (0,1,1), 검정(0,0,0,1) → (0,0,0)
  #expect(
    PDFColorSpace.deviceCMYK.color(from: [1, 0, 0, 0]) == RGBA(red: 0, green: 1, blue: 1))
  #expect(
    PDFColorSpace.deviceCMYK.color(from: [0, 0, 0, 1]) == RGBA(red: 0, green: 0, blue: 0))
}

@Test func insufficientComponentsReturnNil() {
  #expect(PDFColorSpace.deviceRGB.color(from: [0.5]) == nil)
  #expect(PDFColorSpace.pattern.color(from: []) == nil)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`PDFColorSpace` 없음)

- [ ] **Step 3: 구현** — `ImportAI/PDFColor.swift`:

```swift
import CoreGraphics

/// PDF 색공간 상태와 성분 → RGBA 변환 (스펙 §5 — CMYK/Gray→RGB).
/// 파서 내부 타입 — 공개 API가 아니다.
enum PDFColorSpace: Equatable {
  case deviceGray
  case deviceRGB
  case deviceCMYK
  case pattern
  case unsupported(name: String)

  static func named(_ name: String) -> PDFColorSpace {
    switch name {
    case "DeviceGray", "G", "CalGray": return .deviceGray
    case "DeviceRGB", "RGB", "CalRGB": return .deviceRGB
    case "DeviceCMYK", "CMYK": return .deviceCMYK
    case "Pattern": return .pattern
    default: return .unsupported(name: name)
    }
  }

  var componentCount: Int {
    switch self {
    case .deviceGray: return 1
    case .deviceRGB: return 3
    case .deviceCMYK: return 4
    case .pattern, .unsupported: return 0
    }
  }

  /// 성분 배열 → RGBA. 성분 수 부족·비색상 공간이면 nil.
  func color(from components: [CGFloat]) -> RGBA? {
    switch self {
    case .deviceGray where components.count >= 1:
      let gray = Double(components[0])
      return RGBA(red: gray, green: gray, blue: gray)
    case .deviceRGB where components.count >= 3:
      return RGBA(
        red: Double(components[0]), green: Double(components[1]),
        blue: Double(components[2]))
    case .deviceCMYK where components.count >= 4:
      let (c, m, y, k) = (
        Double(components[0]), Double(components[1]),
        Double(components[2]), Double(components[3])
      )
      return RGBA(red: (1 - c) * (1 - k), green: (1 - m) * (1 - k), blue: (1 - y) * (1 - k))
    default:
      return nil
    }
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (237개 = 232 + 5)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF 색공간 상태와 Gray·RGB·CMYK→RGBA 변환"
```

---

### Task 6: PDFPathBuilder — 패스 구성 연산자

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/PDFPathBuilder.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PDFPathBuilderTests.swift` (생성)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

@Test func polylineBuildsOpenSubpath() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  builder.line(to: CGPoint(x: 10, y: 10))
  let path = builder.finish()
  #expect(path.subpaths.count == 1)
  #expect(!path.subpaths[0].isClosed)
  #expect(path.subpaths[0].segments.count == 3)
}

@Test func moveStartsNewSubpath() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  builder.move(to: CGPoint(x: 50, y: 50))
  builder.line(to: CGPoint(x: 60, y: 50))
  let path = builder.finish()
  #expect(path.subpaths.count == 2)
}

@Test func curveVariantsMapControls() {
  // v: control1 = 현재 점, y: control2 = 종점 (PDF §8.5.2)
  var builder = PDFPathBuilder()
  builder.move(to: CGPoint(x: 0, y: 0))
  builder.curveV(to: CGPoint(x: 30, y: 0), control2: CGPoint(x: 20, y: 10))
  builder.curveY(to: CGPoint(x: 60, y: 0), control1: CGPoint(x: 40, y: 10))
  let path = builder.finish()
  guard case .curve(_, let vControl1, _) = path.subpaths[0].segments[1],
    case .curve(let yTo, _, let yControl2) = path.subpaths[0].segments[2]
  else {
    Issue.record("곡선이 아님")
    return
  }
  #expect(vControl1 == CGPoint(x: 0, y: 0))
  #expect(yControl2 == yTo)
}

@Test func closeThenLineStartsNewSubpathAtStart() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  builder.line(to: CGPoint(x: 10, y: 10))
  builder.close()
  builder.line(to: CGPoint(x: -5, y: -5))  // h 뒤 — 시작점에서 이어진다
  let path = builder.finish()
  #expect(path.subpaths.count == 2)
  #expect(path.subpaths[0].isClosed)
  #expect(path.subpaths[1].segments[0] == .move(to: .zero))
  #expect(path.subpaths[1].segments[1] == .line(to: CGPoint(x: -5, y: -5)))
}

@Test func rectAppendsClosedSubpath() {
  var builder = PDFPathBuilder()
  builder.rect(CGRect(x: 5, y: 5, width: 20, height: 10))
  let path = builder.finish()
  #expect(path.subpaths.count == 1)
  #expect(path.subpaths[0].isClosed)
  #expect(path.bounds == CGRect(x: 5, y: 5, width: 20, height: 10))
}

@Test func finishResetsBuilder() {
  var builder = PDFPathBuilder()
  builder.move(to: .zero)
  builder.line(to: CGPoint(x: 10, y: 0))
  _ = builder.finish()
  #expect(builder.finish().subpaths.isEmpty)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`PDFPathBuilder` 없음)

- [ ] **Step 3: 구현** — `ImportAI/PDFPathBuilder.swift`:

```swift
import CoreGraphics

/// PDF 패스 구성 연산자(m l c v y h re) → BezierPath. 좌표는 PDF 사용자
/// 공간 그대로 유지 — CTM·플립은 페인팅 시점에 적용된다 (파서 내부 타입).
struct PDFPathBuilder: Equatable {
  private var subpaths: [Subpath] = []
  private var segments: [PathSegment] = []
  private var currentPoint: CGPoint = .zero
  private var subpathStart: CGPoint = .zero

  mutating func move(to point: CGPoint) {
    flush(isClosed: false)
    currentPoint = point
    subpathStart = point
    segments = [.move(to: point)]
  }

  mutating func line(to point: CGPoint) {
    ensureOpenSubpath()
    segments.append(.line(to: point))
    currentPoint = point
  }

  mutating func curve(to point: CGPoint, control1: CGPoint, control2: CGPoint) {
    ensureOpenSubpath()
    segments.append(.curve(to: point, control1: control1, control2: control2))
    currentPoint = point
  }

  /// v 연산자 — control1 = 현재 점.
  mutating func curveV(to point: CGPoint, control2: CGPoint) {
    curve(to: point, control1: currentPoint, control2: control2)
  }

  /// y 연산자 — control2 = 종점.
  mutating func curveY(to point: CGPoint, control1: CGPoint) {
    curve(to: point, control1: control1, control2: point)
  }

  /// h 연산자 — 닫고, 이후 세그먼트는 시작점에서 새 subpath.
  mutating func close() {
    flush(isClosed: true)
    currentPoint = subpathStart
  }

  /// re 연산자 — 닫힌 사각형 subpath 추가, 현재 점 = 원점.
  mutating func rect(_ rect: CGRect) {
    flush(isClosed: false)
    segments = [
      .move(to: rect.origin),
      .line(to: CGPoint(x: rect.maxX, y: rect.minY)),
      .line(to: CGPoint(x: rect.maxX, y: rect.maxY)),
      .line(to: CGPoint(x: rect.minX, y: rect.maxY)),
    ]
    flush(isClosed: true)
    currentPoint = rect.origin
    subpathStart = rect.origin
  }

  /// 잔여 세그먼트를 포함한 전체 패스를 반환하고 리셋한다.
  mutating func finish() -> BezierPath {
    flush(isClosed: false)
    let path = BezierPath(subpaths: subpaths)
    subpaths = []
    return path
  }

  private mutating func flush(isClosed: Bool) {
    if !segments.isEmpty {
      subpaths.append(Subpath(segments: segments, isClosed: isClosed))
    }
    segments = []
  }

  private mutating func ensureOpenSubpath() {
    if segments.isEmpty {
      segments = [.move(to: currentPoint)]
      subpathStart = currentPoint
    }
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (243개 = 237 + 6)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF 패스 구성 연산자 빌더 — m·l·c·v·y·h·re"
```

---

### Task 7: ContentStreamParser 코어 — 상태·색·패스·페인팅

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserTests.swift` (생성)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

/// 픽스처 PDF 1페이지를 파싱해 노드를 돌려준다.
func parseFixture(
  content: String,
  mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
  resources: String = "<< >>",
  extraObjects: [String] = []
) -> (nodes: [Node], report: ImportReport) {
  let data = makeTestPDF(
    content: content, mediaBox: mediaBox, resources: resources, extraObjects: extraObjects)
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  return ContentStreamParser.parse(page: page)
}

private func firstPath(_ nodes: [Node]) -> PathNode? {
  guard case .path(let pathNode)? = nodes.first else { return nil }
  return pathNode
}

@Test func parsesFilledRectangleWithFlippedCoordinates() {
  let (nodes, report) = parseFixture(content: "1 0 0 rg 10 20 100 50 re f")
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  // PDF y 20…70 → 모델 y 130…180 (mediaBox 높이 200)
  #expect(pathNode.path.bounds == CGRect(x: 10, y: 130, width: 100, height: 50))
  #expect(pathNode.style.fill == .color(RGBA(red: 1, green: 0, blue: 0)))
  #expect(pathNode.style.stroke == nil)
  #expect(pathNode.transform == .identity)
  #expect(pathNode.fillRule == .winding)
}

@Test func parsesStrokeAttributes() {
  let (nodes, _) = parseFixture(content: "0 0 1 RG 4 w 1 J 2 j 10 10 m 100 100 l S")
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.style.fill == nil)
  let stroke = pathNode.style.stroke
  #expect(stroke?.paint == RGBA(red: 0, green: 0, blue: 1))
  #expect(stroke?.width == 4)
  #expect(stroke?.cap == .round)
  #expect(stroke?.join == .bevel)
}

@Test func parsesGrayAndCMYKColors() {
  let (nodes, _) = parseFixture(
    content: "0.5 g 10 10 20 20 re f 1 0 0 0 k 50 10 20 20 re f")
  #expect(nodes.count == 2)
  guard case .path(let gray) = nodes[0], case .path(let cyan) = nodes[1] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(gray.style.fill == .color(RGBA(red: 0.5, green: 0.5, blue: 0.5)))
  #expect(cyan.style.fill == .color(RGBA(red: 0, green: 1, blue: 1)))
}

@Test func ctmScalesGeometryAndStrokeWidth() {
  let (nodes, _) = parseFixture(content: "q 2 0 0 2 0 0 cm 3 w 10 10 m 50 10 l S Q")
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  // 기하 ×2: PDF (20,20)→(100,20) → 모델 y 180
  #expect(pathNode.path.bounds == CGRect(x: 20, y: 180, width: 80, height: 0))
  #expect(pathNode.style.stroke?.width == 6)  // √|det| = 2
}

@Test func evenOddOperatorSetsFillRule() {
  let (nodes, _) = parseFixture(
    content: "20 20 160 160 re 70 70 60 60 re f*")
  #expect(firstPath(nodes)?.fillRule == .evenOdd)
}

@Test func saveRestoreIsolatesState() {
  let (nodes, _) = parseFixture(
    content: "1 0 0 rg q 0 1 0 rg 10 10 20 20 re f Q 50 10 20 20 re f")
  guard case .path(let green) = nodes[0], case .path(let red) = nodes[1] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(green.style.fill == .color(RGBA(red: 0, green: 1, blue: 0)))
  #expect(red.style.fill == .color(RGBA(red: 1, green: 0, blue: 0)))
}

@Test func extGStateSetsFillAlpha() {
  let (nodes, _) = parseFixture(
    content: "/GS1 gs 10 10 20 20 re f",
    resources: "<< /ExtGState << /GS1 5 0 R >> >>",
    extraObjects: ["<< /Type /ExtGState /ca 0.5 >>"])
  #expect(firstPath(nodes)?.style.opacity == 0.5)
}

@Test func dashArrayIsParsed() {
  let (nodes, _) = parseFixture(content: "[3 2] 0 d 10 10 m 100 10 l S")
  #expect(firstPath(nodes)?.style.stroke?.dash == [3, 2])
}

@Test func bStarFillsAndStrokesWithClose() {
  let (nodes, _) = parseFixture(
    content: "1 0 0 rg 0 0 1 RG 10 10 m 100 10 l 100 100 l b")
  guard let pathNode = firstPath(nodes) else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.style.fill != nil)
  #expect(pathNode.style.stroke != nil)
  #expect(pathNode.path.subpaths[0].isClosed)
}

@Test func patternFillIsReportedAndSkipped() {
  let (nodes, report) = parseFixture(
    content: "/Pattern cs /P1 scn 10 10 20 20 re f")
  // 채움은 직전 색(기본 검정) 유지로 그려진다 — 색만 부정확, 도형은 보존
  #expect(nodes.count == 1)
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`ContentStreamParser` 없음)

- [ ] **Step 3: 구현** — `ImportAI/ContentStreamParser.swift`. C 콜백은 컨텍스트 캡처가 불가하므로 info 포인터로 파서를 복원하는 **파일 전역 함수**를 쓴다:

```swift
import CoreGraphics
import Foundation

/// info 포인터 → 파서 (C 콜백은 캡처 불가 — 파일 전역 함수로 복원).
private func parserFrom(_ info: UnsafeMutableRawPointer?) -> ContentStreamParser {
  Unmanaged<ContentStreamParser>.fromOpaque(info!).takeUnretainedValue()
}

/// PDF 콘텐츠 스트림 → [Node] (스펙 §5). CGPDFScanner 연산자 콜백으로
/// 그래픽 상태를 유지하며 페인팅 연산자마다 PathNode를 만든다.
/// CTM·페이지 플립은 좌표에 베이크 — 산출 노드의 transform은 identity.
final class ContentStreamParser {
  /// PDF 그래픽 상태 (q/Q 스택 단위).
  struct GraphicsState: Equatable {
    var ctm: CGAffineTransform = .identity
    var fillColorSpace: PDFColorSpace = .deviceGray
    var strokeColorSpace: PDFColorSpace = .deviceGray
    var fillColor: RGBA = .black
    var strokeColor: RGBA = .black
    var lineWidth: CGFloat = 1
    var lineCap: LineCap = .butt
    var lineJoin: LineJoin = .miter
    var dash: [CGFloat] = []
    var fillAlpha: Double = 1
    /// 누적 클립 (모델 좌표, winding 정규화 완료).
    var clip: BezierPath?
  }

  private struct ClippedNode {
    var clip: BezierPath?
    var node: Node
  }

  private enum PendingClip {
    case winding, evenOdd
  }

  static let maxFormDepth = 8

  private var state = GraphicsState()
  private var stateStack: [GraphicsState] = []
  private var pathBuilder = PDFPathBuilder()
  private var pendingClip: PendingClip?
  private var sinkStack: [[ClippedNode]] = [[]]
  private var contentStreamStack: [CGPDFContentStream] = []
  private var formDepth = 0
  private var didReportText = false
  private var didReportInlineImage = false
  private(set) var report = ImportReport()
  /// PDF 사용자 공간(bottom-left) → 모델(top-left) 변환.
  private let pageFlip: CGAffineTransform

  init(mediaBox: CGRect) {
    pageFlip = CGAffineTransform(
      a: 1, b: 0, c: 0, d: -1, tx: -mediaBox.minX, ty: mediaBox.maxY)
  }

  /// 페이지를 파싱해 노드와 리포트를 반환한다.
  static func parse(page: CGPDFPage) -> (nodes: [Node], report: ImportReport) {
    let parser = ContentStreamParser(mediaBox: page.getBoxRect(.mediaBox))
    let contentStream = CGPDFContentStreamCreateWithPage(page)
    parser.scan(contentStream: contentStream)
    CGPDFContentStreamRelease(contentStream)
    return (parser.finalizedNodes(), parser.report)
  }

  // MARK: - 스캐너

  private func scan(contentStream: CGPDFContentStream) {
    contentStreamStack.append(contentStream)
    defer { contentStreamStack.removeLast() }
    let table = CGPDFOperatorTableCreate()!
    Self.registerOperators(in: table)
    let scanner = CGPDFScannerCreate(
      contentStream, table, Unmanaged.passUnretained(self).toOpaque())
    CGPDFScannerScan(scanner)
    CGPDFScannerRelease(scanner)
    CGPDFOperatorTableRelease(table)
  }

  private static func registerOperators(in table: CGPDFOperatorTable) {
    // 상태
    CGPDFOperatorTableSetCallback(table, "q") { _, info in parserFrom(info).saveState() }
    CGPDFOperatorTableSetCallback(table, "Q") { _, info in parserFrom(info).restoreState() }
    CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
      parserFrom(info).concatenateMatrix(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "w") { scanner, info in
      parserFrom(info).setLineWidth(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "J") { scanner, info in
      parserFrom(info).setLineCap(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "j") { scanner, info in
      parserFrom(info).setLineJoin(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "d") { scanner, info in
      parserFrom(info).setDash(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "gs") { scanner, info in
      parserFrom(info).setExtGState(scanner)
    }
    // 색상
    CGPDFOperatorTableSetCallback(table, "g") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceGray, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "G") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceGray, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceRGB, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "RG") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceRGB, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "k") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceCMYK, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "K") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceCMYK, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "cs") { scanner, info in
      parserFrom(info).setColorSpace(scanner, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "CS") { scanner, info in
      parserFrom(info).setColorSpace(scanner, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "sc") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "scn") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "SC") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "SCN") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: true)
    }
    // 패스 구성
    CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
      parserFrom(info).pathMove(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
      parserFrom(info).pathLine(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
      parserFrom(info).pathCurve(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
      parserFrom(info).pathCurveV(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
      parserFrom(info).pathCurveY(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "h") { _, info in
      parserFrom(info).pathClose()
    }
    CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
      parserFrom(info).pathRect(scanner)
    }
    // 페인팅
    CGPDFOperatorTableSetCallback(table, "f") { _, info in
      parserFrom(info).paint(fill: true, stroke: false, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "F") { _, info in
      parserFrom(info).paint(fill: true, stroke: false, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "f*") { _, info in
      parserFrom(info).paint(fill: true, stroke: false, close: false, evenOdd: true)
    }
    CGPDFOperatorTableSetCallback(table, "B") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "B*") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: false, evenOdd: true)
    }
    CGPDFOperatorTableSetCallback(table, "b") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: true, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "b*") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: true, evenOdd: true)
    }
    CGPDFOperatorTableSetCallback(table, "S") { _, info in
      parserFrom(info).paint(fill: false, stroke: true, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "s") { _, info in
      parserFrom(info).paint(fill: false, stroke: true, close: true, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "n") { _, info in
      parserFrom(info).paint(fill: false, stroke: false, close: false, evenOdd: false)
    }
    // 클리핑·XObject·미지원 리포트는 Task 8~10에서 등록 추가
  }

  // MARK: - 피연산자 팝

  private static func popNumbers(_ scanner: CGPDFScannerRef, count: Int) -> [CGFloat]? {
    var values: [CGFloat] = []
    for _ in 0..<count {
      var value: CGPDFReal = 0
      guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
      values.append(CGFloat(value))
    }
    return Array(values.reversed())  // 피연산자 스택은 역순으로 팝된다
  }

  private static func popName(_ scanner: CGPDFScannerRef) -> String? {
    var pointer: UnsafePointer<CChar>? = nil
    guard CGPDFScannerPopName(scanner, &pointer), let pointer else { return nil }
    return String(cString: pointer)
  }

  // MARK: - 상태 연산자

  private func saveState() {
    stateStack.append(state)
  }

  private func restoreState() {
    if let restored = stateStack.popLast() {
      state = restored
    }
  }

  private func concatenateMatrix(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 6) else { return }
    let matrix = CGAffineTransform(
      a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    state.ctm = matrix.concatenating(state.ctm)
  }

  private func setLineWidth(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    state.lineWidth = values[0]
  }

  private func setLineCap(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    switch Int(values[0]) {
    case 1: state.lineCap = .round
    case 2: state.lineCap = .square
    default: state.lineCap = .butt
    }
  }

  private func setLineJoin(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    switch Int(values[0]) {
    case 1: state.lineJoin = .round
    case 2: state.lineJoin = .bevel
    default: state.lineJoin = .miter
    }
  }

  private func setDash(_ scanner: CGPDFScannerRef) {
    // phase는 모델에 없어 무시한다 (결정 기록).
    var phase: CGPDFReal = 0
    _ = CGPDFScannerPopNumber(scanner, &phase)
    var array: CGPDFArrayRef? = nil
    guard CGPDFScannerPopArray(scanner, &array), let array else { return }
    var dash: [CGFloat] = []
    for index in 0..<CGPDFArrayGetCount(array) {
      var value: CGPDFReal = 0
      if CGPDFArrayGetNumber(array, index, &value) {
        dash.append(CGFloat(value))
      }
    }
    state.dash = dash
  }

  private func setExtGState(_ scanner: CGPDFScannerRef) {
    guard let name = Self.popName(scanner),
      let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "ExtGState", name)
    else { return }
    var dictionary: CGPDFDictionaryRef? = nil
    guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary
    else { return }
    var alpha: CGPDFReal = 1
    if CGPDFDictionaryGetNumber(dictionary, "ca", &alpha) {
      state.fillAlpha = Double(alpha)
    }
  }

  // MARK: - 색상 연산자

  private func setColor(
    _ scanner: CGPDFScannerRef, space: PDFColorSpace, isStroke: Bool
  ) {
    guard let values = Self.popNumbers(scanner, count: space.componentCount),
      let color = space.color(from: values)
    else { return }
    if isStroke {
      state.strokeColorSpace = space
      state.strokeColor = color
    } else {
      state.fillColorSpace = space
      state.fillColor = color
    }
  }

  private func setColorSpace(_ scanner: CGPDFScannerRef, isStroke: Bool) {
    guard let name = Self.popName(scanner) else {
      // 배열형(ICCBased 등) 색공간 — 리포트 후 기존 공간 유지
      report.add(.unsupportedColorSpace, detail: "비단순 색공간")
      return
    }
    let space = PDFColorSpace.named(name)
    if case .unsupported(let unsupportedName) = space {
      report.add(.unsupportedColorSpace, detail: "색공간 \(unsupportedName)")
      return
    }
    if isStroke {
      state.strokeColorSpace = space
    } else {
      state.fillColorSpace = space
    }
  }

  private func setColorComponents(_ scanner: CGPDFScannerRef, isStroke: Bool) {
    let space = isStroke ? state.strokeColorSpace : state.fillColorSpace
    if space == .pattern {
      // scn /P1 — shading 패턴 채움은 M4b. 직전 색 유지, 리포트만.
      report.add(.unsupportedShading, detail: "패턴 채움 (M4b에서 지원 예정)")
      return
    }
    guard space.componentCount > 0,
      let values = Self.popNumbers(scanner, count: space.componentCount),
      let color = space.color(from: values)
    else { return }
    if isStroke {
      state.strokeColor = color
    } else {
      state.fillColor = color
    }
  }

  // MARK: - 패스 구성 연산자

  private func pathMove(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 2) else { return }
    pathBuilder.move(to: CGPoint(x: values[0], y: values[1]))
  }

  private func pathLine(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 2) else { return }
    pathBuilder.line(to: CGPoint(x: values[0], y: values[1]))
  }

  private func pathCurve(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 6) else { return }
    pathBuilder.curve(
      to: CGPoint(x: values[4], y: values[5]),
      control1: CGPoint(x: values[0], y: values[1]),
      control2: CGPoint(x: values[2], y: values[3]))
  }

  private func pathCurveV(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 4) else { return }
    pathBuilder.curveV(
      to: CGPoint(x: values[2], y: values[3]),
      control2: CGPoint(x: values[0], y: values[1]))
  }

  private func pathCurveY(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 4) else { return }
    pathBuilder.curveY(
      to: CGPoint(x: values[2], y: values[3]),
      control1: CGPoint(x: values[0], y: values[1]))
  }

  private func pathClose() {
    pathBuilder.close()
  }

  private func pathRect(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 4) else { return }
    pathBuilder.rect(
      CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
  }

  // MARK: - 페인팅

  private func paint(fill: Bool, stroke: Bool, close: Bool, evenOdd: Bool) {
    if close {
      pathBuilder.close()
    }
    let userPath = pathBuilder.finish()
    applyPendingClip(with: userPath)
    guard fill || stroke, !userPath.subpaths.isEmpty else { return }
    let toModel = state.ctm.concatenating(pageFlip)
    let modelPath = userPath.applying(toModel)
    var style = Style(opacity: state.fillAlpha)
    if fill {
      style.fill = .color(state.fillColor)
    }
    if stroke {
      // PDF 선폭은 사용자 공간 정의 — CTM의 √|det| 근사 스케일 (결정 기록).
      let widthScale = CGFloat(sqrt(abs(Transform2D(state.ctm).determinant)))
      style.stroke = Stroke(
        paint: state.strokeColor, width: state.lineWidth * widthScale,
        cap: state.lineCap, join: state.lineJoin,
        dash: state.dash.map { $0 * widthScale })
    }
    appendNode(
      .path(
        PathNode(
          path: modelPath, style: style, fillRule: evenOdd ? .evenOdd : .winding)))
  }

  private func appendNode(_ node: Node) {
    sinkStack[sinkStack.count - 1].append(ClippedNode(clip: state.clip, node: node))
  }

  /// W/W* 보류 클립을 현재 패스로 확정한다 (Task 8에서 W/W* 등록).
  private func applyPendingClip(with userPath: BezierPath) {
    guard let pending = pendingClip else { return }
    pendingClip = nil
    guard !userPath.subpaths.isEmpty else { return }
    let toModel = state.ctm.concatenating(pageFlip)
    let rule: CGPathFillRule = pending == .evenOdd ? .evenOdd : .winding
    let normalized = userPath.applying(toModel).cgPath.normalized(using: rule)
    if let existing = state.clip {
      state.clip = BezierPath(cgPath: existing.cgPath.intersection(normalized))
    } else {
      state.clip = BezierPath(cgPath: normalized)
    }
  }

  // MARK: - 결과 조립

  /// 같은 클립의 연속 노드를 GroupNode(clipPath:)로 묶는다.
  func finalizedNodes() -> [Node] {
    Self.grouped(sinkStack[0])
  }

  private static func grouped(_ entries: [ClippedNode]) -> [Node] {
    var result: [Node] = []
    var pendingClipped: (clip: BezierPath, nodes: [Node])?

    func flushClipped() {
      if let pending = pendingClipped {
        result.append(.group(GroupNode(children: pending.nodes, clipPath: pending.clip)))
        pendingClipped = nil
      }
    }

    for entry in entries {
      if let clip = entry.clip {
        if pendingClipped?.clip == clip {
          pendingClipped?.nodes.append(entry.node)
        } else {
          flushClipped()
          pendingClipped = (clip, [entry.node])
        }
      } else {
        flushClipped()
        result.append(entry.node)
      }
    }
    flushClipped()
    return result
  }
}
```

주의 — `pendingClip`/`sinkStack`/`grouped`는 이 태스크에서 함께 들어가지만 W/W* 콜백 등록은 Task 8이다 (이 태스크에서 clip은 항상 nil 경로).

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (253개 = 243 + 10)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF 콘텐츠 스트림 파서 코어 — 상태·색·패스·페인팅"
```

---

### Task 8: 클리핑 — W/W* → 클립 그룹

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserTests.swift` (추가)

- [ ] **Step 1: 실패하는 테스트 작성** — `ContentStreamParserTests.swift` 끝에 추가:

```swift
// MARK: - 클리핑

@Test func clipWrapsSubsequentNodesInGroup() {
  let (nodes, _) = parseFixture(
    content: "10 10 100 100 re W n 0 0 1 rg 0 0 200 200 re f")
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  // 클립 사각형: PDF (10,10,100,100) → 모델 y 90…190
  #expect(group.clipPath?.bounds == CGRect(x: 10, y: 90, width: 100, height: 100))
  #expect(group.children.count == 1)
}

@Test func clipIsRestoredByQ() {
  let (nodes, _) = parseFixture(
    content: "q 10 10 50 50 re W n 0 0 200 200 re f Q 0 0 20 20 re f")
  #expect(nodes.count == 2)
  guard case .group = nodes[0], case .path = nodes[1] else {
    Issue.record("구조가 다름 — 클립 그룹 + 최상위 패스여야 함")
    return
  }
}

@Test func nestedClipsIntersect() {
  let (nodes, _) = parseFixture(
    content: "0 0 100 100 re W n 50 50 100 100 re W n 0 0 200 200 re f")
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  // 교차: PDF (50,50)…(100,100) → 모델 y 100…150
  #expect(group.clipPath?.bounds == CGRect(x: 50, y: 100, width: 50, height: 50))
}

@Test func consecutiveNodesUnderSameClipShareOneGroup() {
  let (nodes, _) = parseFixture(
    content: "10 10 150 150 re W n 20 20 30 30 re f 60 20 30 30 re f")
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  #expect(group.children.count == 2)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (W 미등록 → 클립 없음)

- [ ] **Step 3: 콜백 등록** — `registerOperators` 끝의 주석 위에 추가:

```swift
    // 클리핑 — 다음 페인팅 연산자에서 확정된다
    CGPDFOperatorTableSetCallback(table, "W") { _, info in
      parserFrom(info).pendingClip = .winding
    }
    CGPDFOperatorTableSetCallback(table, "W*") { _, info in
      parserFrom(info).pendingClip = .evenOdd
    }
```

`pendingClip`의 접근 제어를 `private`에서 `fileprivate`로 바꾸거나, private 메서드 `markClip(evenOdd:)`를 추가해 콜백에서 호출한다 (전역 함수 `parserFrom`이 같은 파일이므로 `private(set)`도 가능 — 컴파일이 되는 가장 좁은 범위 선택).

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (257개 = 253 + 4)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF 클리핑 — W·W* 교차 누적과 클립 그룹화"
```

---

### Task 9: 폼 XObject — Do 재귀

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserTests.swift` (추가)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
// MARK: - 폼 XObject

@Test func formXObjectBecomesGroupWithMatrixApplied() {
  let formContent = "1 0 0 rg 0 0 20 20 re f"
  let form =
    "<< /Type /XObject /Subtype /Form /BBox [0 0 200 200] "
    + "/Matrix [1 0 0 1 50 0] /Length \(formContent.utf8.count) >> stream\n"
    + "\(formContent)\nendstream"
  let (nodes, report) = parseFixture(
    content: "/F0 Do",
    resources: "<< /XObject << /F0 5 0 R >> >>",
    extraObjects: [form])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("폼 그룹이 아님")
    return
  }
  #expect(group.children.count == 1)
  // /Matrix 평행이동 50 적용: PDF (50,0,20,20) → 모델 (50, 180, 20, 20)
  #expect(group.children[0].bounds == CGRect(x: 50, y: 180, width: 20, height: 20))
}

@Test func formBBoxClipsContent() {
  // BBox (0,0,30,30) 밖으로 그리는 폼 — BBox가 클립으로 적용된다
  let formContent = "1 0 0 rg 0 0 99 99 re f"
  let form =
    "<< /Type /XObject /Subtype /Form /BBox [0 0 30 30] "
    + "/Length \(formContent.utf8.count) >> stream\n\(formContent)\nendstream"
  let (nodes, _) = parseFixture(
    content: "/F0 Do",
    resources: "<< /XObject << /F0 5 0 R >> >>",
    extraObjects: [form])
  guard case .group(let outerGroup) = nodes[0],
    case .group(let clipGroup) = outerGroup.children[0]
  else {
    Issue.record("폼 그룹 안에 클립 그룹이어야 함")
    return
  }
  #expect(clipGroup.clipPath?.bounds == CGRect(x: 0, y: 170, width: 30, height: 30))
}

@Test func missingXObjectIsSilentlySkipped() {
  let (nodes, _) = parseFixture(content: "/Nope Do 10 10 20 20 re f")
  #expect(nodes.count == 1)  // Do 실패해도 이후 파싱 계속
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (Do 미등록)

- [ ] **Step 3: 구현** — `registerOperators`에 등록 추가:

```swift
    CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
      parserFrom(info).invokeXObject(scanner)
    }
```

핸들러·헬퍼 추가 (`// MARK: - 결과 조립` 위):

```swift
  // MARK: - XObject

  private func invokeXObject(_ scanner: CGPDFScannerRef) {
    guard let name = Self.popName(scanner),
      let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "XObject", name)
    else { return }
    var xobjectStream: CGPDFStreamRef? = nil
    guard CGPDFObjectGetValue(object, .stream, &xobjectStream), let xobjectStream,
      let dictionary = CGPDFStreamGetDictionary(xobjectStream)
    else { return }
    var subtypePointer: UnsafePointer<CChar>? = nil
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypePointer),
      let subtypePointer
    else { return }
    switch String(cString: subtypePointer) {
    case "Form":
      invokeForm(xobjectStream, dictionary: dictionary)
    case "Image":
      report.add(.unsupportedImage, detail: "이미지 XObject \(name) (M4b에서 지원 예정)")
    default:
      break
    }
  }

  private func invokeForm(_ formStream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef) {
    guard formDepth < Self.maxFormDepth else {
      report.add(.formRecursionLimit, detail: "폼 중첩 \(Self.maxFormDepth) 초과")
      return
    }
    formDepth += 1
    saveState()
    if let matrix = Self.matrix(from: dictionary, key: "Matrix") {
      state.ctm = matrix.concatenating(state.ctm)
    }
    // /BBox는 폼 콘텐츠의 클립 (PDF 의미론 — 결정 기록).
    if let bbox = Self.rect(from: dictionary, key: "BBox") {
      var bboxBuilder = PDFPathBuilder()
      bboxBuilder.rect(bbox)
      pendingClip = .winding
      applyPendingClip(with: bboxBuilder.finish())
    }
    sinkStack.append([])
    let childStream = CGPDFContentStreamCreateWithStream(
      formStream, dictionary, contentStreamStack.last)
    scan(contentStream: childStream)
    CGPDFContentStreamRelease(childStream)
    let formNodes = Self.grouped(sinkStack.removeLast())
    restoreState()
    formDepth -= 1
    if !formNodes.isEmpty {
      appendNode(.group(GroupNode(children: formNodes)))
    }
  }

  private static func matrix(
    from dictionary: CGPDFDictionaryRef, key: String
  ) -> CGAffineTransform? {
    guard let values = numbers(from: dictionary, key: key, count: 6) else { return nil }
    return CGAffineTransform(
      a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
  }

  private static func rect(from dictionary: CGPDFDictionaryRef, key: String) -> CGRect? {
    guard let values = numbers(from: dictionary, key: key, count: 4) else { return nil }
    return CGRect(
      x: values[0], y: values[1], width: values[2] - values[0],
      height: values[3] - values[1])
  }

  private static func numbers(
    from dictionary: CGPDFDictionaryRef, key: String, count: Int
  ) -> [CGFloat]? {
    var array: CGPDFArrayRef? = nil
    guard CGPDFDictionaryGetArray(dictionary, key, &array), let array,
      CGPDFArrayGetCount(array) >= count
    else { return nil }
    var values: [CGFloat] = []
    for index in 0..<count {
      var value: CGPDFReal = 0
      guard CGPDFArrayGetNumber(array, index, &value) else { return nil }
      values.append(CGFloat(value))
    }
    return values
  }
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (260개 = 257 + 3)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 폼 XObject 재귀 파싱 — Matrix·BBox 클립·그룹화"
```

---

### Task 10: 미지원 요소 리포트 — sh·텍스트·인라인 이미지

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserTests.swift` (추가)

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
// MARK: - 미지원 요소 리포트

@Test func shadingOperatorIsReported() {
  let (nodes, report) = parseFixture(content: "/Sh0 sh 10 10 20 20 re f")
  #expect(nodes.count == 1)  // 파싱은 계속
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
}

@Test func textBlockIsReportedOncePerParse() {
  let (_, report) = parseFixture(
    content: "BT ET BT ET 10 10 20 20 re f")
  #expect(report.issues.filter { $0.kind == .unsupportedText }.count == 1)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL

- [ ] **Step 3: 콜백 등록** — `registerOperators`에 추가:

```swift
    // 미지원 요소 — 건너뛰고 리포트 (M4b: 이슈 #11)
    CGPDFOperatorTableSetCallback(table, "sh") { scanner, info in
      _ = ContentStreamParser.popName(scanner)
      parserFrom(info).report.add(
        .unsupportedShading, detail: "그라디언트 셰이딩 (M4b에서 지원 예정)")
    }
    CGPDFOperatorTableSetCallback(table, "BT") { _, info in
      parserFrom(info).reportTextOnce()
    }
    CGPDFOperatorTableSetCallback(table, "BI") { _, info in
      parserFrom(info).reportInlineImageOnce()
    }
```

(`report`가 `private(set)`이면 콜백에서 add가 안 되므로 `fileprivate` 메서드로 감싼다):

```swift
  fileprivate func reportTextOnce() {
    guard !didReportText else { return }
    didReportText = true
    report.add(.unsupportedText, detail: "텍스트 (M4b에서 지원 예정)")
  }

  fileprivate func reportInlineImageOnce() {
    guard !didReportInlineImage else { return }
    didReportInlineImage = true
    report.add(.unsupportedImage, detail: "인라인 이미지 (M4b에서 지원 예정)")
  }
```

sh 콜백도 같은 패턴의 fileprivate 메서드(`reportShading(detail:)`)로 정리해 접근 제어 문제를 피한다.

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (262개 = 260 + 2)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 미지원 셰이딩·텍스트·인라인 이미지 리포트 수집"
```

---

### Task 11: PDFDocumentImporter + AIFileReader 통합 (폴백·다중 페이지·암호화)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/PDFDocumentImporter.swift`
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/AIFileReader.swift`
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ImportError.swift` (`noNativeData` 삭제)
- Test: `VectaEngine/Tests/VectaEngineTests/AIFileReaderImportTests.swift` (생성)

기존 `AIFileReaderTests.swift`에서 `noNativeData`를 기대하는 테스트가 있으면 새 동작(파서 폴백)에 맞게 수정한다 — 마커 없는 유효 PDF는 이제 에러가 아니라 파싱 결과를 반환한다.

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@Test func nativePayloadStillWinsWithEmptyReport() throws {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers[0].nodes = [
    .path(
      PathNode(
        path: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50)),
        style: .defaultShape))
  ]
  let data = try AIFileWriter.data(for: document)
  let result = try AIFileReader.read(from: data)
  #expect(result.document == document)
  #expect(result.report.isEmpty)
}

@Test func externalPDFParsesViaContentStream() throws {
  let data = makeTestPDF(content: "1 0 0 rg 10 20 100 50 re f")
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers.count == 1)
  #expect(result.document.layers[0].nodes.count == 1)
  #expect(result.document.artboard.size == CGSize(width: 200, height: 200))
}

@Test func corruptPayloadFallsBackToParserWithIssue() throws {
  // BEGIN만 있고 END 없는 손상 블록을 startxref 직전에 삽입
  var data = makeTestPDF(content: "10 10 50 50 re f")
  let marker = Data("\(NativeScenePayload.beginMarker)\n%AAAA\n".utf8)
  let startxref = data.range(of: Data("startxref".utf8), options: .backwards)!
  data.insert(contentsOf: marker, at: startxref.lowerBound)
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers[0].nodes.count == 1)  // 파서 폴백 성공
  #expect(result.report.issues.contains { $0.kind == .corruptNativePayload })
}

@Test func oversizedPayloadFallsBackToParserWithIssue() throws {
  var data = makeTestPDF(content: "10 10 50 50 re f")
  var block = Data("\(NativeScenePayload.beginMarker)\n%".utf8)
  block.append(
    Data(repeating: UInt8(ascii: "A"), count: NativeScenePayload.maxPayloadBytes + 1))
  block.append(Data("\n\(NativeScenePayload.endMarker)\n".utf8))
  let startxref = data.range(of: Data("startxref".utf8), options: .backwards)!
  data.insert(contentsOf: block, at: startxref.lowerBound)
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers[0].nodes.count == 1)
  #expect(result.report.issues.contains { $0.kind == .oversizedNativePayload })
}

@Test func multiPageLoadsFirstPageWithWarning() throws {
  let data = makeTestPDF(pages: ["10 10 50 50 re f", "20 20 50 50 re f 60 60 50 50 re f"])
  let result = try AIFileReader.read(from: data)
  #expect(result.document.layers[0].nodes.count == 1)  // 1페이지만
  #expect(result.report.issues.contains { $0.kind == .multiplePages })
}

@Test func encryptedPDFThrowsClearError() {
  // 트레일러에 /Encrypt 참조 → CGPDFDocument가 암호화로 인식
  let data = makeTestPDF(
    pages: ["10 10 50 50 re f"], trailerExtra: "/Encrypt << /Filter /Standard >> ")
  #expect(throws: ImportError.encryptedPDF) {
    try AIFileReader.read(from: data)
  }
}

@Test func nonPDFStillThrowsNotPDF() {
  #expect(throws: ImportError.notPDF) {
    try AIFileReader.read(from: Data("hello".utf8))
  }
}

@Test func vectaOwnPDFContentParsesWhenPayloadStripped() throws {
  // 우리 익스포터의 PDF 본문도 파서가 읽을 수 있다 (페이로드 제거 후)
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
  document.layers[0].nodes = [
    .path(
      PathNode(
        path: .rectangle(CGRect(x: 10, y: 10, width: 80, height: 40)),
        style: Style(fill: .color(RGBA(red: 1, green: 0, blue: 0)))))
  ]
  var data = try AIFileWriter.data(for: document)
  // 페이로드 블록 제거
  let begin = data.range(of: Data(NativeScenePayload.beginMarker.utf8))!
  let end = data.range(
    of: Data((NativeScenePayload.endMarker + "\n").utf8),
    in: begin.lowerBound..<data.endIndex)!
  data.removeSubrange(begin.lowerBound..<end.upperBound)
  let result = try AIFileReader.read(from: data)
  let imported = result.document.layers[0].nodes
  #expect(imported.count == 1)
  // CG가 좌표를 어떻게 직렬화하든 바운드는 보존되어야 한다
  #expect(imported[0].bounds == CGRect(x: 10, y: 10, width: 80, height: 40))
}
```

`encryptedPDFThrowsClearError` 주의: CGPDFDocument가 이 픽스처를 아예 못 열면(`nil`) `unreadablePDF`가 던져진다. 실패 시 실제 동작을 확인하고 — `isEncrypted`가 true가 되는 trailerExtra 형태(`/Encrypt 99 0 R` 간접 참조 등)로 조정하거나, 그래도 안 되면 기대 에러를 실제 동작으로 고정하고 보고서에 기록한다.

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`AIFileReader.read` 없음)

- [ ] **Step 3: PDFDocumentImporter 구현** — `ImportAI/PDFDocumentImporter.swift`:

```swift
import CoreGraphics
import Foundation

/// CGPDFDocument → ImportResult (스펙 §5). 1페이지만 파싱하고
/// 다중 페이지는 경고를 남긴다 (스펙 §10).
enum PDFDocumentImporter {
  static func importDocument(from data: Data) throws -> ImportResult {
    guard let provider = CGDataProvider(data: data as CFData),
      let pdf = CGPDFDocument(provider)
    else {
      throw ImportError.unreadablePDF
    }
    if pdf.isEncrypted && !pdf.isUnlocked {
      throw ImportError.encryptedPDF
    }
    guard pdf.numberOfPages >= 1, let page = pdf.page(at: 1) else {
      throw ImportError.unreadablePDF
    }
    var (nodes, report) = ContentStreamParser.parse(page: page)
    if pdf.numberOfPages > 1 {
      report.add(
        .multiplePages,
        detail: "\(pdf.numberOfPages)페이지 중 1페이지만 가져왔습니다")
    }
    let mediaBox = page.getBoxRect(.mediaBox)
    var document = VectorDocument.empty(size: mediaBox.size)
    document.layers[0].nodes = nodes
    return ImportResult(document: document, report: report)
  }
}
```

- [ ] **Step 4: AIFileReader 교체** — `AIFileReader.swift` 전체:

```swift
import Foundation

public enum AIFileReader {
  /// 임베드 JSON이 있으면 100% 복원, 없으면(외부 파일) 콘텐츠 스트림 파싱.
  /// 손상·과대 페이로드는 파싱 폴백 + 리포트 (조용한 데이터 손실 금지 — 스펙 §5).
  public static func read(from data: Data) throws -> ImportResult {
    guard data.starts(with: Data("%PDF-".utf8)) else {
      throw ImportError.notPDF
    }
    do {
      if let native = try NativeScenePayload.extract(from: data) {
        return ImportResult(document: native, report: .empty)
      }
    } catch ImportError.corruptNativeData {
      return try fallback(
        data: data, kind: .corruptNativePayload,
        detail: "저장된 Vecta 데이터가 손상되어 PDF 본문에서 가져왔습니다")
    } catch ImportError.payloadTooLarge {
      return try fallback(
        data: data, kind: .oversizedNativePayload,
        detail: "저장된 Vecta 데이터가 비정상적으로 커서 PDF 본문에서 가져왔습니다")
    }
    return try PDFDocumentImporter.importDocument(from: data)
  }

  private static func fallback(
    data: Data, kind: ImportIssue.Kind, detail: String
  ) throws -> ImportResult {
    var result = try PDFDocumentImporter.importDocument(from: data)
    result.report.issues.insert(ImportIssue(kind: kind, detail: detail), at: 0)
    return result
  }
}
```

`ImportError`에서 `noNativeData` 케이스와 메시지를 삭제한다. 기존 `AIFileReaderTests.swift`의 관련 테스트는 새 의미(마커 없음 → 파서 폴백)로 갱신.

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (270개 = 262 + 8, 기존 테스트 수정분 포함 — 실제 수와 다르면 보고)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: AIFileReader 파서 폴백 — 외부 PDF·다중 페이지·암호화·손상 처리"
```

---

### Task 12: 앱 — .pdf 문서 타입 + read 갱신

UI 셸 — 빌드 + 스모크 검증.

**Files:**
- Modify: `VectaApp/project.yml`
- Modify: `VectaApp/Sources/Document/VectaDocument.swift`

- [ ] **Step 1: project.yml** — `CFBundleDocumentTypes` 배열에 항목 추가:

```yaml
          - CFBundleTypeName: PDF Document
            CFBundleTypeRole: Viewer
            LSItemContentTypes: [com.adobe.pdf]
            LSHandlerRank: Alternate
            NSDocumentClass: Vecta.VectaDocument
```

- [ ] **Step 2: VectaDocument read 갱신** — 프로퍼티 추가 + `read(from:ofType:)` 교체:

```swift
  /// 마지막 열기에서 수집된 임포트 리포트 (배너 표시용 — Task 13).
  private(set) var importReport = ImportReport.empty
```

```swift
  override func read(from data: Data, ofType typeName: String) throws {
    // read(from:ofType:)는 SDK상 nonisolated이지만 canConcurrentlyReadDocuments
    // (기본 false)를 재정의하지 않는 한 메인 스레드에서 호출된다.
    // 이 클래스에서 canConcurrentlyReadDocuments를 절대 재정의하지 말 것.
    let result = try AIFileReader.read(from: data)
    MainActor.assumeIsolated {
      store.load(result.document)
      importReport = result.report
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

- [ ] **Step 4: 실행 스모크** — `open VectaApp/build/Build/Products/Debug/Vecta.app` → 3초 → `pgrep -x Vecta` → `pkill -x Vecta`

- [ ] **Step 5: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: .pdf 문서 타입과 임포트 리포트 보관"
```

---

### Task 13: 앱 — ImportReport 비모달 배너

UI 셸 — 빌드 + 스모크 검증.

**Files:**
- Create: `VectaApp/Sources/Panels/ImportReportBanner.swift`
- Modify: `VectaApp/Sources/Document/VectaDocument.swift`

- [ ] **Step 1: 배너 뷰** — `Panels/ImportReportBanner.swift`:

```swift
import SwiftUI
import VectaEngine

/// 임포트 경고 비모달 배너 (스펙 §5) — "N개 객체를 가져오지 못했습니다 (자세히)".
struct ImportReportBanner: View {
  let report: ImportReport
  let onDismiss: () -> Void
  @State private var showingDetails = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
      Text("\(report.issues.count)개 객체를 가져오지 못했습니다")
      Button("자세히") {
        showingDetails = true
      }
      .buttonStyle(.link)
      .popover(isPresented: $showingDetails) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
            Text("• \(issue.detail)")
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(12)
        .frame(maxWidth: 360)
      }
      Spacer()
      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.borderless)
      .help("배너 닫기")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.yellow.opacity(0.15))
  }
}
```

- [ ] **Step 2: 윈도우 통합** — `VectaDocument.makeContentView`를 수정해 기존 수평 스택을 변수로 두고, 리포트가 있으면 수직 스택으로 감싼다:

```swift
  private func makeContentView(canvasView: CanvasView) -> NSView {
    // (기존 scrollView/toolbar/sidePanel 구성은 그대로)
    ...
    let horizontal = NSStackView(views: [toolbar, scrollView, sidePanel])
    horizontal.orientation = .horizontal
    horizontal.distribution = .fill
    horizontal.spacing = 0
    sidePanel.widthAnchor.constraint(equalToConstant: 260).isActive = true

    guard !importReport.isEmpty else { return horizontal }
    let banner = NSHostingView(
      rootView: ImportReportBanner(report: importReport) { [weak self] in
        self?.bannerView?.isHidden = true
      })
    bannerView = banner
    let vertical = NSStackView(views: [banner, horizontal])
    vertical.orientation = .vertical
    vertical.alignment = .width
    vertical.spacing = 0
    return vertical
  }
```

클래스에 프로퍼티 추가:

```swift
  private weak var bannerView: NSView?
```

(NSStackView는 `isHidden` 뷰를 레이아웃에서 자동 분리한다 — 닫기 = isHidden.)

- [ ] **Step 3: 빌드 + 엔진 회귀** — Task 12 Step 3과 동일 명령. 전체 PASS + BUILD SUCCEEDED

- [ ] **Step 4: 실행 스모크** — 외부 PDF를 만들어 열어본다:

```bash
# 텍스트가 든 PDF를 즉석 생성해 배너 표시를 확인 (수동 — 가능하면)
open VectaApp/build/Build/Products/Debug/Vecta.app
pgrep -x Vecta && pkill -x Vecta
```

(GUI 배너 확인은 사용자 수동 체크리스트 항목.)

- [ ] **Step 5: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: 임포트 경고 비모달 배너 — 자세히 팝오버·닫기"
```

---

### Task 14: 통합 회귀 + README + PR

- [ ] **Step 1: 전체 회귀** — 엔진 `swift test` 전체 PASS + 앱 xcodebuild BUILD SUCCEEDED + 스모크

- [ ] **Step 2: 수동 검증 체크리스트** (사용자 수행)

1. 외부 도구(Illustrator/Inkscape/미리보기 인쇄 등)가 만든 PDF 열기 → 패스·단색 도형 표시
2. Vecta로 저장한 .ai를 텍스트 에디터에서 `%VectaSceneJSON` 블록 삭제 후 열기 → 본문 파싱으로 복원 (배너 없음)
3. 텍스트/이미지가 든 PDF 열기 → "N개 객체를 가져오지 못했습니다" 배너 + 자세히 팝오버 + 닫기
4. 여러 페이지 PDF → 1페이지만 + 배너 경고
5. .pdf 파일을 열고 편집 → 저장 시 .ai로 다른 이름 저장 흐름
6. 암호화 PDF → "암호로 보호된 파일은 열 수 없습니다"
7. 기존 Vecta .ai 열기/저장 회귀 — 100% 라운드트립 (M3 문서 포함)
8. 가져온 문서를 편집 후 .ai 저장 → 재열기 100%

- [ ] **Step 3: README 갱신** — 마일스톤 체크리스트의 M4 줄을 분할 갱신:

```markdown
- [x] M4a 외부 .ai 임포트: 파서 코어(패스·스타일·클립·폼)·ImportReport 배너
- [ ] M4b 외부 .ai 임포트: 그라디언트·이미지·텍스트
```

(기존 M4 한 줄이 있으면 교체, 없으면 M3 아래 삽입 — 실제 README 형식에 맞춘다.)

- [ ] **Step 4: PR 생성** — base 결정: PR #10(M3)이 머지됐으면 `main`, 아니면 `m3-style-layers`(스택). 푸시 전 `gh pr view 10 --json state`로 확인.

```bash
git push -u origin m4a-import-core
gh pr create --base <위에서 결정> --title "feat: M4a 외부 .ai 임포트 — 파서 코어·ImportReport" \
  --body "$(cat <<'EOF'
## Summary
- 엔진: CGPDFScanner 콘텐츠 스트림 파서 (상태/색/패스/페인팅/클립/폼 XObject), PathNode.fillRule(짝홀), CGPath→BezierPath 역변환, ImportReport 수집, AIFileReader 폴백(부재·손상·과대 페이로드), 다중 페이지 경고, 암호화 에러, 페이로드 64MB 상한
- 앱: .pdf 문서 타입(Viewer), 임포트 경고 비모달 배너
- 그라디언트·이미지·텍스트 파싱은 M4b (이슈 #11)

## Test Plan
- [x] 엔진 swift test 전체 통과
- [x] xcodebuild BUILD SUCCEEDED + 스모크
- [ ] 수동 체크리스트 8항목 (plan Task 14 Step 2)

Closes #5

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 완료 기준 (M4a Definition of Done)

- 엔진 테스트 전체 그린 (베이스 215 + 신규 ~55)
- 외부 PDF(패스·단색)가 열리고, 미지원 요소는 배너로 보고됨 — 조용한 데이터 손실 없음
- 기존 Vecta 파일 100% 라운드트립 회귀 없음 (fillRule 호환 디코드 포함)
- 손상/과대 페이로드 → 파서 폴백 + 리포트
- PR이 이슈 #5를 닫음

## M4b 예고 (이슈 #11)

그라디언트(sh + shading 패턴 type 2/3, PDF function type 2/3), 이미지 XObject(PNG 정규화 + SceneRenderer 이미지 렌더), 텍스트(BT~TJ, 표준 인코딩 + ToUnicode) — 이 파서 코어 위에 콜백·핸들러만 추가하는 구조.
