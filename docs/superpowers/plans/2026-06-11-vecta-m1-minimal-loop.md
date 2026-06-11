# Vecta M1 — 최소 루프 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 도형(사각형/타원)을 드래그로 그리고, .ai(PDF) 파일로 저장하고, 다시 열어 100% 복원하는 macOS 앱의 최소 루프 완성.

**Architecture:** VectaEngine(SPM 패키지, UI 의존성 없음)에 모델·렌더러·.ai 입출력·undo 스토어를 두고 `swift test`로 검증한다. VectaApp(XcodeGen 생성 Xcode 프로젝트)은 NSDocument + AppKit 캔버스 + SwiftUI 툴바의 얇은 셸이다. .ai 저장은 CGContext로 PDF를 그리고 마지막 `startxref` 직전에 씬그래프 JSON을 base64 주석 블록으로 삽입한다(스파이크 검증 완료 — 스펙 6절).

**Tech Stack:** Swift 6.3 툴체인(언어 모드 v5), Swift Testing(`import Testing`), CoreGraphics, AppKit, SwiftUI, XcodeGen 2.45, swift-format(툴체인 내장).

**참조 스펙:** `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md`

---

## 사전 확인 (검증 완료 상태)

| 도구 | 버전 | 확인 명령 |
|---|---|---|
| Swift | 6.3.2 | `swift --version` |
| Xcode | 26.5 | `xcodebuild -version` |
| XcodeGen | 2.45.4 | `xcodegen --version` |
| swift-format | 6.3.0 | `swift format --version` |

## 커밋 규칙 (사용자 전역 규칙)

매 커밋 전 **순서 고정**: ① analyze → ② test → ③ format → ④ commit.

- 엔진: ① `swift build` ② `swift test` ③ `swift format --in-place --recursive Sources Tests` (VectaEngine 디렉토리에서)
- 앱 변경 시 ①은 `xcodebuild` 빌드, ③은 `swift format --in-place --recursive VectaApp/Sources`
- 커밋 메시지는 한국어 + `feat:`/`test:`/`chore:` 접두사, Co-Authored-By 금지

## 파일 구조 (M1 완성 시점)

```
vecta/
├── .gitignore
├── VectaEngine/
│   ├── Package.swift
│   ├── Sources/VectaEngine/
│   │   ├── Model/
│   │   │   ├── NodeID.swift          # UUID 래퍼
│   │   │   ├── RGBA.swift            # 색상 (0…1 Double 4채널)
│   │   │   ├── Transform2D.swift     # Codable 가능한 2D 아핀 변환
│   │   │   ├── BezierPath.swift      # PathSegment/Subpath/BezierPath
│   │   │   ├── Style.swift           # Paint/Gradient/Stroke/Style
│   │   │   ├── Node.swift            # Node enum + 4종 노드 구조체
│   │   │   ├── Layer.swift
│   │   │   └── VectorDocument.swift  # Artboard + VectorDocument
│   │   ├── Geometry/
│   │   │   ├── BezierPath+Factory.swift   # rectangle/ellipse 팩토리
│   │   │   ├── BezierPath+CGPath.swift
│   │   │   └── CGRect+Corners.swift       # 드래그 두 점 → 정규화 CGRect
│   │   ├── Rendering/
│   │   │   └── SceneRenderer.swift   # 씬그래프 → CGContext (캔버스/PDF 공용)
│   │   ├── State/
│   │   │   └── DocumentStore.swift   # 변경 단일 경로 + 스냅샷 undo
│   │   ├── ImportAI/
│   │   │   ├── ImportError.swift
│   │   │   └── AIFileReader.swift    # M1: 네이티브 JSON만, 외부 파일은 에러
│   │   └── ExportAI/
│   │       ├── ExportError.swift
│   │       ├── NativeScenePayload.swift   # JSON 임베드/추출
│   │       └── AIFileWriter.swift
│   └── Tests/VectaEngineTests/
│       ├── TestSupport.swift          # 비트맵 렌더·픽셀 검사 헬퍼
│       ├── RGBATests.swift
│       ├── Transform2DTests.swift
│       ├── BezierPathTests.swift
│       ├── StyleTests.swift
│       ├── VectorDocumentTests.swift
│       ├── SceneRendererTests.swift
│       ├── NativeScenePayloadTests.swift
│       ├── AIFileWriterTests.swift
│       ├── AIFileReaderTests.swift
│       └── DocumentStoreTests.swift
└── VectaApp/
    ├── project.yml                    # XcodeGen 정의 (Vecta.xcodeproj는 git 무시)
    └── Sources/
        ├── main.swift
        ├── AppDelegate.swift
        ├── MainMenuBuilder.swift
        ├── Document/VectaDocument.swift
        ├── Canvas/CanvasView.swift
        ├── Canvas/ToolState.swift
        └── Panels/ToolbarView.swift
```

좌표계 계약 (전체 코드가 의존하는 불변식):
- **모델 좌표 = top-left 원점, y 아래 방향.**
- `SceneRenderer`는 "현재 CTM이 모델 좌표를 매핑한다"고 가정하고 그린다.
- 캔버스 `NSView`는 `isFlipped = true`라 변환 불필요. PDF 컨텍스트(bottom-left)는 그리기 전에 `translateBy(0, height)` + `scaleBy(1, -1)`로 뒤집는다.

---

### Task 1: 리포 기반 + VectaEngine 패키지 스캐폴드

**Files:**
- Create: `.gitignore`
- Create: `VectaEngine/Package.swift`
- Create: `VectaEngine/Sources/VectaEngine/Model/NodeID.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/RGBATests.swift` (다음 태스크에서 본격 사용, 여기선 스모크)

- [ ] **Step 1: .gitignore 작성**

```gitignore
.DS_Store
.build/
.swiftpm/
xcuserdata/
VectaApp/Vecta.xcodeproj
VectaApp/build/
```

- [ ] **Step 2: Package.swift 작성**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VectaEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VectaEngine", targets: ["VectaEngine"])
    ],
    targets: [
        .target(
            name: "VectaEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VectaEngineTests",
            dependencies: ["VectaEngine"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

언어 모드 v5인 이유: M1에서 Swift 6 strict concurrency와 AppKit/UndoManager 통합의 마찰을 피한다. M6(마감)에서 v6 전환을 검토한다.

- [ ] **Step 3: 첫 모델 타입 NodeID 작성** — `Sources/VectaEngine/Model/NodeID.swift`

```swift
import Foundation

/// 씬그래프 노드 식별자. 선택 상태는 모델 밖에서 `Set<NodeID>`로 관리한다.
public struct NodeID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
```

- [ ] **Step 4: 스모크 테스트 작성** — `Tests/VectaEngineTests/RGBATests.swift`

```swift
import Foundation
import Testing
@testable import VectaEngine

@Test func nodeIDCodableRoundTrip() throws {
    let original = NodeID()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(NodeID.self, from: data)
    #expect(decoded == original)
}
```

(파일명이 RGBATests인 이유: Task 2에서 RGBA 테스트가 이 파일에 추가되고 NodeID 테스트도 같은 "기본 타입" 분류라 함께 둔다.)

- [ ] **Step 5: 빌드·테스트 실행**

Run: `cd VectaEngine && swift build && swift test`
Expected: 빌드 성공, `1 test passed`

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A
git commit -m "feat: VectaEngine 패키지 스캐폴드와 NodeID 모델 추가"
```

---

### Task 2: RGBA 색상 모델

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/RGBA.swift`
- Modify: `VectaEngine/Tests/VectaEngineTests/RGBATests.swift`

- [ ] **Step 1: 실패하는 테스트 추가** — RGBATests.swift에 append

```swift
@Test func rgbaCodableRoundTrip() throws {
    let original = RGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RGBA.self, from: data)
    #expect(decoded == original)
}

@Test func rgbaDefaultAlphaIsOpaque() {
    #expect(RGBA(red: 1, green: 0, blue: 0).alpha == 1)
}

@Test func rgbaPresetColors() {
    #expect(RGBA.black == RGBA(red: 0, green: 0, blue: 0))
    #expect(RGBA.white == RGBA(red: 1, green: 1, blue: 1))
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'RGBA' in scope`

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Model/RGBA.swift`

```swift
/// sRGB 색상. 각 채널 0…1.
public struct RGBA: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let white = RGBA(red: 1, green: 1, blue: 1)
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS (4 tests)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: RGBA 색상 모델 추가"
```

---

### Task 3: Transform2D

CGAffineTransform은 Codable이 아니므로 retroactive conformance 대신 자체 타입을 둔다.

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/Transform2D.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/Transform2DTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

@Test func transform2DIdentity() {
    #expect(Transform2D.identity.cgAffineTransform == .identity)
}

@Test func transform2DCGConversionRoundTrip() {
    let cg = CGAffineTransform(translationX: 10, y: 20).rotated(by: .pi / 4)
    let roundTripped = Transform2D(cg).cgAffineTransform
    #expect(abs(roundTripped.a - cg.a) < 1e-12)
    #expect(abs(roundTripped.b - cg.b) < 1e-12)
    #expect(abs(roundTripped.c - cg.c) < 1e-12)
    #expect(abs(roundTripped.d - cg.d) < 1e-12)
    #expect(abs(roundTripped.tx - cg.tx) < 1e-12)
    #expect(abs(roundTripped.ty - cg.ty) < 1e-12)
}

@Test func transform2DCodableRoundTrip() throws {
    let original = Transform2D(CGAffineTransform(scaleX: 2, y: 3))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Transform2D.self, from: data)
    #expect(decoded == original)
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'Transform2D' in scope`

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Model/Transform2D.swift`

```swift
import CoreGraphics

/// Codable 가능한 2D 아핀 변환. 필드명 a/b/c/d/tx/ty는 PDF·CoreGraphics
/// 아핀 행렬의 표준 표기를 따른다.
public struct Transform2D: Equatable, Codable, Sendable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public static let identity = Transform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public init(_ transform: CGAffineTransform) {
        self.init(
            a: transform.a, b: transform.b, c: transform.c,
            d: transform.d, tx: transform.tx, ty: transform.ty)
    }

    public var cgAffineTransform: CGAffineTransform {
        CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: Codable 2D 아핀 변환 Transform2D 추가"
```

---

### Task 4: BezierPath 모델 + 팩토리 + CGPath 변환 + 코너 정규화

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/BezierPath.swift`
- Create: `VectaEngine/Sources/VectaEngine/Geometry/BezierPath+Factory.swift`
- Create: `VectaEngine/Sources/VectaEngine/Geometry/BezierPath+CGPath.swift`
- Create: `VectaEngine/Sources/VectaEngine/Geometry/CGRect+Corners.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/BezierPathTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

@Test func rectangleFactoryProducesClosedSubpath() {
    let path = BezierPath.rectangle(CGRect(x: 10, y: 20, width: 100, height: 50))
    #expect(path.subpaths.count == 1)
    let subpath = path.subpaths[0]
    #expect(subpath.isClosed)
    // move + 3 lines (마지막 변은 close가 담당)
    #expect(subpath.segments.count == 4)
    #expect(subpath.segments[0] == .move(to: CGPoint(x: 10, y: 20)))
}

@Test func ellipseFactoryProducesFourCurves() {
    let path = BezierPath.ellipse(in: CGRect(x: 0, y: 0, width: 100, height: 60))
    let subpath = path.subpaths[0]
    #expect(subpath.isClosed)
    let curveCount = subpath.segments.filter {
        if case .curve = $0 { return true } else { return false }
    }.count
    #expect(curveCount == 4)
}

@Test func cgPathBoundingBoxMatchesSourceRect() {
    let rect = CGRect(x: 10, y: 20, width: 100, height: 50)
    #expect(BezierPath.rectangle(rect).cgPath.boundingBox == rect)
}

@Test func ellipseCGPathBoundingBoxMatchesRect() {
    let rect = CGRect(x: 5, y: 5, width: 80, height: 40)
    let box = BezierPath.ellipse(in: rect).cgPath.boundingBox
    #expect(abs(box.minX - rect.minX) < 0.001)
    #expect(abs(box.minY - rect.minY) < 0.001)
    #expect(abs(box.maxX - rect.maxX) < 0.001)
    #expect(abs(box.maxY - rect.maxY) < 0.001)
}

@Test func bezierPathCodableRoundTrip() throws {
    let original = BezierPath.ellipse(in: CGRect(x: 1, y: 2, width: 3, height: 4))
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(BezierPath.self, from: data)
    #expect(decoded == original)
}

@Test func rectFromCornersNormalizesNegativeDrag() {
    let rect = CGRect(corner: CGPoint(x: 100, y: 80), oppositeCorner: CGPoint(x: 40, y: 20))
    #expect(rect == CGRect(x: 40, y: 20, width: 60, height: 60))
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'BezierPath' in scope`

- [ ] **Step 3: 모델 구현** — `Sources/VectaEngine/Model/BezierPath.swift`

```swift
import CoreGraphics

/// 베지어 패스 한 구간. 첫 세그먼트는 항상 `.move`다.
public enum PathSegment: Equatable, Codable, Sendable {
    case move(to: CGPoint)
    case line(to: CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
}

public struct Subpath: Equatable, Codable, Sendable {
    public var segments: [PathSegment]
    public var isClosed: Bool

    public init(segments: [PathSegment], isClosed: Bool) {
        self.segments = segments
        self.isClosed = isClosed
    }
}

public struct BezierPath: Equatable, Codable, Sendable {
    public var subpaths: [Subpath]

    public init(subpaths: [Subpath]) {
        self.subpaths = subpaths
    }
}
```

- [ ] **Step 4: 팩토리 구현** — `Sources/VectaEngine/Geometry/BezierPath+Factory.swift`

```swift
import CoreGraphics

extension BezierPath {
    /// 원호 1/4을 3차 베지어로 근사할 때의 컨트롤 포인트 비율.
    private static let circleApproximationKappa = 0.5522847498307936

    public static func rectangle(_ rect: CGRect) -> BezierPath {
        let segments: [PathSegment] = [
            .move(to: CGPoint(x: rect.minX, y: rect.minY)),
            .line(to: CGPoint(x: rect.maxX, y: rect.minY)),
            .line(to: CGPoint(x: rect.maxX, y: rect.maxY)),
            .line(to: CGPoint(x: rect.minX, y: rect.maxY)),
        ]
        return BezierPath(subpaths: [Subpath(segments: segments, isClosed: true)])
    }

    public static func ellipse(in rect: CGRect) -> BezierPath {
        let offsetX = rect.width / 2 * circleApproximationKappa
        let offsetY = rect.height / 2 * circleApproximationKappa
        let east = CGPoint(x: rect.maxX, y: rect.midY)
        let south = CGPoint(x: rect.midX, y: rect.maxY)
        let west = CGPoint(x: rect.minX, y: rect.midY)
        let north = CGPoint(x: rect.midX, y: rect.minY)
        let segments: [PathSegment] = [
            .move(to: east),
            .curve(
                to: south,
                control1: CGPoint(x: rect.maxX, y: rect.midY + offsetY),
                control2: CGPoint(x: rect.midX + offsetX, y: rect.maxY)),
            .curve(
                to: west,
                control1: CGPoint(x: rect.midX - offsetX, y: rect.maxY),
                control2: CGPoint(x: rect.minX, y: rect.midY + offsetY)),
            .curve(
                to: north,
                control1: CGPoint(x: rect.minX, y: rect.midY - offsetY),
                control2: CGPoint(x: rect.midX - offsetX, y: rect.minY)),
            .curve(
                to: east,
                control1: CGPoint(x: rect.midX + offsetX, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.midY - offsetY)),
        ]
        return BezierPath(subpaths: [Subpath(segments: segments, isClosed: true)])
    }
}
```

- [ ] **Step 5: CGPath 변환 구현** — `Sources/VectaEngine/Geometry/BezierPath+CGPath.swift`

```swift
import CoreGraphics

extension BezierPath {
    public var cgPath: CGPath {
        let path = CGMutablePath()
        for subpath in subpaths {
            for segment in subpath.segments {
                switch segment {
                case .move(let point):
                    path.move(to: point)
                case .line(let point):
                    path.addLine(to: point)
                case .curve(let point, let control1, let control2):
                    path.addCurve(to: point, control1: control1, control2: control2)
                }
            }
            if subpath.isClosed {
                path.closeSubpath()
            }
        }
        return path
    }
}
```

- [ ] **Step 6: 코너 정규화 구현** — `Sources/VectaEngine/Geometry/CGRect+Corners.swift`

```swift
import CoreGraphics

extension CGRect {
    /// 드래그 시작·끝점처럼 순서가 보장되지 않는 두 모서리에서 정규화된 rect 생성.
    public init(corner: CGPoint, oppositeCorner: CGPoint) {
        self.init(
            x: min(corner.x, oppositeCorner.x),
            y: min(corner.y, oppositeCorner.y),
            width: abs(corner.x - oppositeCorner.x),
            height: abs(corner.y - oppositeCorner.y))
    }
}
```

- [ ] **Step 7: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 8: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: BezierPath 모델과 도형 팩토리, CGPath 변환 추가"
```

---

### Task 5: 스타일 타입 (Paint / Gradient / Stroke / Style)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/Style.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/StyleTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

@Test func styleCodableRoundTrip() throws {
    let original = Style(
        fill: .linearGradient(
            Gradient(
                stops: [
                    GradientStop(location: 0, color: .black),
                    GradientStop(location: 1, color: .white),
                ],
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 100, y: 0))),
        stroke: Stroke(paint: .black, width: 2),
        opacity: 0.5)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Style.self, from: data)
    #expect(decoded == original)
}

@Test func strokeDefaults() {
    let stroke = Stroke(paint: .black, width: 1)
    #expect(stroke.cap == .butt)
    #expect(stroke.join == .miter)
    #expect(stroke.dash.isEmpty)
}

@Test func defaultShapeStyleHasFillAndStroke() {
    #expect(Style.defaultShape.fill != nil)
    #expect(Style.defaultShape.stroke != nil)
    #expect(Style.defaultShape.opacity == 1)
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'Style' in scope`

- [ ] **Step 3: 구현** — `Sources/VectaEngine/Model/Style.swift`

```swift
import CoreGraphics

public struct GradientStop: Equatable, Codable, Sendable {
    public var location: Double
    public var color: RGBA

    public init(location: Double, color: RGBA) {
        self.location = location
        self.color = color
    }
}

/// start/end는 객체 로컬 좌표 (스펙 4절).
public struct Gradient: Equatable, Codable, Sendable {
    public var stops: [GradientStop]
    public var start: CGPoint
    public var end: CGPoint

    public init(stops: [GradientStop], start: CGPoint, end: CGPoint) {
        self.stops = stops
        self.start = start
        self.end = end
    }
}

public enum Paint: Equatable, Codable, Sendable {
    case color(RGBA)
    case linearGradient(Gradient)
    case radialGradient(Gradient)
}

public enum LineCap: String, Codable, Sendable {
    case butt, round, square
}

public enum LineJoin: String, Codable, Sendable {
    case miter, round, bevel
}

public struct Stroke: Equatable, Codable, Sendable {
    public var paint: RGBA
    public var width: CGFloat
    public var cap: LineCap
    public var join: LineJoin
    public var dash: [CGFloat]

    public init(
        paint: RGBA, width: CGFloat,
        cap: LineCap = .butt, join: LineJoin = .miter, dash: [CGFloat] = []
    ) {
        self.paint = paint
        self.width = width
        self.cap = cap
        self.join = join
        self.dash = dash
    }
}

public struct Style: Equatable, Codable, Sendable {
    public var fill: Paint?
    public var stroke: Stroke?
    public var opacity: Double

    public init(fill: Paint? = nil, stroke: Stroke? = nil, opacity: Double = 1) {
        self.fill = fill
        self.stroke = stroke
        self.opacity = opacity
    }

    /// 새 도형의 기본 스타일 (파란 면 + 검정 1pt 선).
    public static let defaultShape = Style(
        fill: .color(RGBA(red: 0.27, green: 0.51, blue: 0.96)),
        stroke: Stroke(paint: .black, width: 1))
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: Paint·Gradient·Stroke·Style 스타일 모델 추가"
```

---

### Task 6: 노드 트리 + Layer + VectorDocument

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Model/Node.swift`
- Create: `VectaEngine/Sources/VectaEngine/Model/Layer.swift`
- Create: `VectaEngine/Sources/VectaEngine/Model/VectorDocument.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/VectorDocumentTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
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
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'PathNode' in scope`

- [ ] **Step 3: 노드 구현** — `Sources/VectaEngine/Model/Node.swift`

```swift
import CoreGraphics
import Foundation

public struct PathNode: Equatable, Codable, Sendable {
    public let id: NodeID
    public var path: BezierPath
    public var style: Style
    public var transform: Transform2D

    public init(
        id: NodeID = NodeID(), path: BezierPath, style: Style,
        transform: Transform2D = .identity
    ) {
        self.id = id
        self.path = path
        self.style = style
        self.transform = transform
    }
}

public struct GroupNode: Equatable, Codable, Sendable {
    public let id: NodeID
    public var children: [Node]
    public var clipPath: BezierPath?
    public var transform: Transform2D

    public init(
        id: NodeID = NodeID(), children: [Node],
        clipPath: BezierPath? = nil, transform: Transform2D = .identity
    ) {
        self.id = id
        self.children = children
        self.clipPath = clipPath
        self.transform = transform
    }
}

public struct TextNode: Equatable, Codable, Sendable {
    public let id: NodeID
    public var string: String
    public var fontName: String
    public var fontSize: Double
    public var fill: Paint
    public var position: CGPoint
    public var transform: Transform2D

    public init(
        id: NodeID = NodeID(), string: String, fontName: String,
        fontSize: Double, fill: Paint, position: CGPoint,
        transform: Transform2D = .identity
    ) {
        self.id = id
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.fill = fill
        self.position = position
        self.transform = transform
    }
}

public struct ImageNode: Equatable, Codable, Sendable {
    public let id: NodeID
    public var imageData: Data
    public var frame: CGRect
    public var transform: Transform2D

    public init(
        id: NodeID = NodeID(), imageData: Data, frame: CGRect,
        transform: Transform2D = .identity
    ) {
        self.id = id
        self.imageData = imageData
        self.frame = frame
        self.transform = transform
    }
}

public enum Node: Equatable, Codable, Sendable {
    case path(PathNode)
    case group(GroupNode)
    case text(TextNode)
    case image(ImageNode)

    public var id: NodeID {
        switch self {
        case .path(let node): return node.id
        case .group(let node): return node.id
        case .text(let node): return node.id
        case .image(let node): return node.id
        }
    }
}
```

- [ ] **Step 4: Layer 구현** — `Sources/VectaEngine/Model/Layer.swift`

```swift
public struct Layer: Equatable, Codable, Sendable {
    public let id: NodeID
    public var name: String
    public var isVisible: Bool
    public var isLocked: Bool
    public var nodes: [Node]

    public init(
        id: NodeID = NodeID(), name: String,
        isVisible: Bool = true, isLocked: Bool = false, nodes: [Node] = []
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.nodes = nodes
    }
}
```

- [ ] **Step 5: VectorDocument 구현** — `Sources/VectaEngine/Model/VectorDocument.swift`

```swift
import CoreGraphics

public struct Artboard: Equatable, Codable, Sendable {
    public var size: CGSize

    public init(size: CGSize) {
        self.size = size
    }
}

public struct VectorDocument: Equatable, Codable, Sendable {
    public var artboard: Artboard
    public var layers: [Layer]

    public init(artboard: Artboard, layers: [Layer]) {
        self.artboard = artboard
        self.layers = layers
    }

    /// 기본 크기는 A4 (포인트 단위).
    public static func empty(size: CGSize = CGSize(width: 595, height: 842)) -> VectorDocument {
        VectorDocument(
            artboard: Artboard(size: size),
            layers: [Layer(name: "레이어 1")])
    }
}
```

- [ ] **Step 6: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 7: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 노드 트리·레이어·VectorDocument 씬그래프 모델 완성"
```

---

### Task 7: SceneRenderer (캔버스/PDF 공용 렌더러)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Rendering/SceneRenderer.swift`
- Create: `VectaEngine/Tests/VectaEngineTests/TestSupport.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/SceneRendererTests.swift`

- [ ] **Step 1: 테스트 지원 헬퍼 작성** — `Tests/VectaEngineTests/TestSupport.swift`

```swift
import CoreGraphics
@testable import VectaEngine

/// sRGB premultipliedLast(RGBA8) 비트맵에 모델 좌표(top-left)로 렌더링한다.
/// CTM 플립 덕분에 "모델 (x, y) = 비트맵 row y" 가 성립한다.
func renderToBitmap(_ document: VectorDocument, size: CGSize) -> CGContext {
    let context = CGContext(
        data: nil,
        width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    SceneRenderer.render(document, in: context)
    return context
}

func pixelColor(x: Int, y: Int, in context: CGContext) -> (
    red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
) {
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let offset = y * context.bytesPerRow + x * 4
    return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
}
```

- [ ] **Step 2: 실패하는 테스트 작성** — `Tests/VectaEngineTests/SceneRendererTests.swift`

```swift
import CoreGraphics
import Testing
@testable import VectaEngine

private func documentWithRedRect() -> VectorDocument {
    var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
    let red = Style(fill: .color(RGBA(red: 1, green: 0, blue: 0)))
    let rect = PathNode(
        path: .rectangle(CGRect(x: 20, y: 20, width: 100, height: 100)),
        style: red)
    document.layers[0].nodes = [.path(rect)]
    return document
}

@Test func rendersFilledRectAtModelCoordinates() {
    let context = renderToBitmap(
        documentWithRedRect(), size: CGSize(width: 200, height: 200))
    let inside = pixelColor(x: 70, y: 70, in: context)
    #expect(inside.red == 255)
    #expect(inside.green == 0)
    #expect(inside.alpha == 255)
    // 모델 y=20 위쪽(top)은 비어 있어야 한다 — 좌표 플립 검증
    let above = pixelColor(x: 70, y: 5, in: context)
    #expect(above.alpha == 0)
    let below = pixelColor(x: 70, y: 180, in: context)
    #expect(below.alpha == 0)
}

@Test func hiddenLayerIsNotRendered() {
    var document = documentWithRedRect()
    document.layers[0].isVisible = false
    let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
    #expect(pixelColor(x: 70, y: 70, in: context).alpha == 0)
}

@Test func nodeTransformIsApplied() {
    var document = documentWithRedRect()
    guard case .path(var node) = document.layers[0].nodes[0] else {
        Issue.record("path 노드가 아님")
        return
    }
    node.transform = Transform2D(CGAffineTransform(translationX: 60, y: 0))
    document.layers[0].nodes[0] = .path(node)
    let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
    // 원래 (20…120) → 이동 후 (80…180)
    #expect(pixelColor(x: 70, y: 70, in: context).alpha == 0)
    #expect(pixelColor(x: 170, y: 70, in: context).red == 255)
}

@Test func strokeOnlyPathRendersOutline() {
    var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
    let outlined = PathNode(
        path: .rectangle(CGRect(x: 50, y: 50, width: 100, height: 100)),
        style: Style(stroke: Stroke(paint: .black, width: 4)))
    document.layers[0].nodes = [.path(outlined)]
    let context = renderToBitmap(document, size: CGSize(width: 200, height: 200))
    #expect(pixelColor(x: 100, y: 50, in: context).alpha == 255)  // 윗변 위
    #expect(pixelColor(x: 100, y: 100, in: context).alpha == 0)  // 중앙은 비어 있음
}
```

- [ ] **Step 3: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'SceneRenderer' in scope`

- [ ] **Step 4: 구현** — `Sources/VectaEngine/Rendering/SceneRenderer.swift`

```swift
import CoreGraphics

/// 씬그래프를 CGContext에 그린다. 캔버스(NSView)와 PDF 익스포트가 공유한다.
///
/// 계약: 호출 시점의 CTM이 모델 좌표(top-left 원점, y 아래 방향)를 매핑해야
/// 한다. flipped NSView는 그대로, PDF 컨텍스트는 플립 후 호출한다.
public enum SceneRenderer {
    public static func render(_ document: VectorDocument, in context: CGContext) {
        for layer in document.layers where layer.isVisible {
            for node in layer.nodes {
                render(node, in: context)
            }
        }
    }

    static func render(_ node: Node, in context: CGContext) {
        switch node {
        case .path(let pathNode):
            render(pathNode, in: context)
        case .group(let groupNode):
            render(groupNode, in: context)
        case .text, .image:
            // M4(임포트)·M5(도구)에서 구현 예정. M1 모델은 생성 경로가 없다.
            break
        }
    }

    static func render(_ group: GroupNode, in context: CGContext) {
        context.saveGState()
        context.concatenate(group.transform.cgAffineTransform)
        if let clipPath = group.clipPath {
            context.addPath(clipPath.cgPath)
            context.clip()
        }
        for child in group.children {
            render(child, in: context)
        }
        context.restoreGState()
    }

    static func render(_ pathNode: PathNode, in context: CGContext) {
        context.saveGState()
        context.concatenate(pathNode.transform.cgAffineTransform)
        context.setAlpha(CGFloat(pathNode.style.opacity))
        if let fill = pathNode.style.fill {
            renderFill(fill, path: pathNode.path, in: context)
        }
        if let stroke = pathNode.style.stroke {
            renderStroke(stroke, path: pathNode.path, in: context)
        }
        context.restoreGState()
    }

    private static func renderFill(_ paint: Paint, path: BezierPath, in context: CGContext) {
        switch paint {
        case .color(let color):
            context.setFillColor(color.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()
        case .linearGradient, .radialGradient:
            break  // M3에서 CGShading으로 구현
        }
    }

    private static func renderStroke(_ stroke: Stroke, path: BezierPath, in context: CGContext) {
        context.setStrokeColor(stroke.paint.cgColor)
        context.setLineWidth(stroke.width)
        context.setLineCap(stroke.cap.cgLineCap)
        context.setLineJoin(stroke.join.cgLineJoin)
        context.setLineDash(phase: 0, lengths: stroke.dash)
        context.addPath(path.cgPath)
        context.strokePath()
    }
}

extension RGBA {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension LineCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

extension LineJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 캔버스·PDF 공용 SceneRenderer 추가"
```

---

### Task 8: 에러 타입 + NativeScenePayload (JSON 임베드/추출)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/ImportError.swift`
- Create: `VectaEngine/Sources/VectaEngine/ExportAI/ExportError.swift`
- Create: `VectaEngine/Sources/VectaEngine/ExportAI/NativeScenePayload.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/NativeScenePayloadTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

/// startxref와 %%EOF를 가진 최소 형태의 가짜 PDF 꼬리.
private let fakePDF = Data(
    """
    %PDF-1.4
    1 0 obj << >> endobj
    xref
    trailer << >>
    startxref
    9
    %%EOF
    """.utf8)

@Test func embedThenExtractRoundTrips() throws {
    let document = VectorDocument.empty(size: CGSize(width: 100, height: 80))
    let embedded = try NativeScenePayload.embed(document, into: fakePDF)
    let extracted = try NativeScenePayload.extract(from: embedded)
    #expect(extracted == document)
}

@Test func embedInsertsBeforeStartxref() throws {
    let document = VectorDocument.empty()
    let embedded = try NativeScenePayload.embed(document, into: fakePDF)
    let text = String(decoding: embedded, as: UTF8.self)
    let markerIndex = text.range(of: "%VectaSceneJSON-BEGIN")!.lowerBound
    let startxrefIndex = text.range(of: "startxref")!.lowerBound
    #expect(markerIndex < startxrefIndex)
    #expect(text.hasSuffix("%%EOF"))
}

@Test func extractReturnsNilWhenMarkerAbsent() throws {
    #expect(try NativeScenePayload.extract(from: fakePDF) == nil)
}

@Test func extractThrowsOnCorruptPayload() throws {
    let corrupt = Data(
        """
        %PDF-1.4
        %VectaSceneJSON-BEGIN
        %!!!이건 base64가 아님!!!
        %VectaSceneJSON-END
        startxref
        9
        %%EOF
        """.utf8)
    #expect(throws: ImportError.corruptNativeData) {
        try NativeScenePayload.extract(from: corrupt)
    }
}

@Test func embedThrowsWhenStartxrefMissing() {
    #expect(throws: ExportError.pdfGenerationFailed) {
        try NativeScenePayload.embed(VectorDocument.empty(), into: Data("no pdf".utf8))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'NativeScenePayload' in scope`

- [ ] **Step 3: 에러 타입 구현**

`Sources/VectaEngine/ImportAI/ImportError.swift`:

```swift
import Foundation

public enum ImportError: Error, Equatable, LocalizedError {
    case notPDF
    case noNativeData
    case corruptNativeData

    public var errorDescription: String? {
        switch self {
        case .notPDF:
            return "지원하지 않는 파일입니다. PDF 호환 .ai 파일만 열 수 있습니다."
        case .noNativeData:
            return "다른 앱에서 만든 .ai 파일 가져오기는 아직 지원하지 않습니다."
        case .corruptNativeData:
            return "파일에 저장된 Vecta 데이터가 손상되었습니다."
        }
    }
}
```

`Sources/VectaEngine/ExportAI/ExportError.swift`:

```swift
import Foundation

public enum ExportError: Error, Equatable, LocalizedError {
    case pdfGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .pdfGenerationFailed:
            return "PDF 생성에 실패했습니다."
        }
    }
}
```

- [ ] **Step 4: NativeScenePayload 구현** — `Sources/VectaEngine/ExportAI/NativeScenePayload.swift`

```swift
import Foundation

/// 씬그래프 JSON을 PDF의 마지막 `startxref` 직전에 base64 주석 블록으로
/// 삽입/추출한다. 주석은 xref 오프셋에 영향을 주지 않으므로 파일은 유효한
/// PDF로 유지된다 (스펙 6절, 2026-06-11 스파이크로 검증).
public enum NativeScenePayload {
    static let beginMarker = "%VectaSceneJSON-BEGIN"
    static let endMarker = "%VectaSceneJSON-END"

    public static func embed(_ document: VectorDocument, into pdfData: Data) throws -> Data {
        guard
            let startxrefRange = pdfData.range(
                of: Data("startxref".utf8), options: .backwards)
        else {
            throw ExportError.pdfGenerationFailed
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(document).base64EncodedString()
        let block = "\(beginMarker)\n%\(payload)\n\(endMarker)\n"
        var result = pdfData
        result.insert(contentsOf: Data(block.utf8), at: startxrefRange.lowerBound)
        return result
    }

    /// 마커가 없으면 nil (외부 파일 → 콘텐츠 스트림 파싱 폴백 대상).
    public static func extract(from data: Data) throws -> VectorDocument? {
        guard
            let beginRange = data.range(of: Data((beginMarker + "\n%").utf8)),
            let endRange = data.range(
                of: Data(("\n" + endMarker).utf8), in: beginRange.upperBound..<data.endIndex)
        else {
            return nil
        }
        let base64 = data[beginRange.upperBound..<endRange.lowerBound]
        guard let json = Data(base64Encoded: Data(base64)) else {
            throw ImportError.corruptNativeData
        }
        do {
            return try JSONDecoder().decode(VectorDocument.self, from: json)
        } catch {
            throw ImportError.corruptNativeData
        }
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 씬그래프 JSON을 PDF에 임베드하는 NativeScenePayload 추가"
```

---

### Task 9: AIFileWriter

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ExportAI/AIFileWriter.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/AIFileWriterTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

private func documentWithRedRect() -> VectorDocument {
    var document = VectorDocument.empty(size: CGSize(width: 200, height: 200))
    let rect = PathNode(
        path: .rectangle(CGRect(x: 20, y: 20, width: 100, height: 100)),
        style: Style(fill: .color(RGBA(red: 1, green: 0, blue: 0))))
    document.layers[0].nodes = [.path(rect)]
    return document
}

@Test func outputIsValidPDFWithArtboardMediaBox() throws {
    let data = try AIFileWriter.data(for: documentWithRedRect())
    #expect(data.starts(with: Data("%PDF-".utf8)))
    let provider = CGDataProvider(data: data as CFData)!
    let pdf = CGPDFDocument(provider)
    #expect(pdf != nil)
    #expect(pdf!.numberOfPages == 1)
    let mediaBox = pdf!.page(at: 1)!.getBoxRect(.mediaBox)
    #expect(mediaBox == CGRect(x: 0, y: 0, width: 200, height: 200))
}

@Test func outputContainsExtractableSceneJSON() throws {
    let document = documentWithRedRect()
    let data = try AIFileWriter.data(for: document)
    let extracted = try NativeScenePayload.extract(from: data)
    #expect(extracted == document)
}

@Test func pdfPageRendersShapeAtModelPosition() throws {
    let data = try AIFileWriter.data(for: documentWithRedRect())
    let pdf = CGPDFDocument(CGDataProvider(data: data as CFData)!)!
    let page = pdf.page(at: 1)!
    let context = CGContext(
        data: nil, width: 200, height: 200,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.drawPDFPage(page)
    // 모델 top-left (70,70)은 PDF(bottom-left) 렌더 후에도 비트맵 row 70
    let inside = pixelColor(x: 70, y: 70, in: context)
    #expect(inside.red == 255)
    let outside = pixelColor(x: 70, y: 180, in: context)
    #expect(outside.alpha == 0)
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'AIFileWriter' in scope`

- [ ] **Step 3: 구현** — `Sources/VectaEngine/ExportAI/AIFileWriter.swift`

```swift
import CoreGraphics
import Foundation

/// 씬그래프를 PDF로 그려 .ai 파일 데이터를 만든다.
/// 텍스트·이미지·그라디언트 렌더링은 SceneRenderer 확장에 따라온다.
public enum AIFileWriter {
    public static func data(for document: VectorDocument) throws -> Data {
        let pdf = try renderPDF(document)
        return try NativeScenePayload.embed(document, into: pdf)
    }

    private static func renderPDF(_ document: VectorDocument) throws -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: document.artboard.size)
        guard
            let consumer = CGDataConsumer(data: output as CFMutableData),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ExportError.pdfGenerationFailed
        }
        context.beginPDFPage(nil)
        // 모델 좌표(top-left) → PDF 좌표(bottom-left) 플립
        context.translateBy(x: 0, y: mediaBox.height)
        context.scaleBy(x: 1, y: -1)
        SceneRenderer.render(document, in: context)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 씬그래프를 .ai(PDF)로 저장하는 AIFileWriter 추가"
```

---

### Task 10: AIFileReader

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/AIFileReader.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/AIFileReaderTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

@Test func writerOutputRoundTripsThroughReader() throws {
    var document = VectorDocument.empty(size: CGSize(width: 300, height: 200))
    document.layers[0].nodes = [
        .path(
            PathNode(
                path: .ellipse(in: CGRect(x: 10, y: 10, width: 80, height: 40)),
                style: .defaultShape))
    ]
    let data = try AIFileWriter.data(for: document)
    let loaded = try AIFileReader.document(from: data)
    #expect(loaded == document)
}

@Test func foreignPDFThrowsNoNativeData() throws {
    // 외부 도구가 만든 PDF(페이로드 없음) 흉내: CG로 직접 생성
    let raw = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 100, height: 100)
    let context = CGContext(
        consumer: CGDataConsumer(data: raw as CFMutableData)!,
        mediaBox: &mediaBox, nil)!
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()
    #expect(throws: ImportError.noNativeData) {
        try AIFileReader.document(from: raw as Data)
    }
}

@Test func nonPDFDataThrowsNotPDF() {
    #expect(throws: ImportError.notPDF) {
        try AIFileReader.document(from: Data("이건 PDF가 아님".utf8))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'AIFileReader' in scope`

- [ ] **Step 3: 구현** — `Sources/VectaEngine/ImportAI/AIFileReader.swift`

```swift
import Foundation

public enum AIFileReader {
    /// M1: Vecta가 저장한 파일(임베드 JSON)만 연다.
    /// M4에서 noNativeData 경로가 콘텐츠 스트림 파싱 폴백으로 대체된다.
    public static func document(from data: Data) throws -> VectorDocument {
        guard data.starts(with: Data("%PDF-".utf8)) else {
            throw ImportError.notPDF
        }
        guard let native = try NativeScenePayload.extract(from: data) else {
            throw ImportError.noNativeData
        }
        return native
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: .ai 파일을 씬그래프로 복원하는 AIFileReader 추가"
```

---

### Task 11: DocumentStore (변경 단일 경로 + 스냅샷 undo)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/State/DocumentStore.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/DocumentStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing
@testable import VectaEngine

private func makeRectNode() -> Node {
    .path(
        PathNode(
            path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
            style: .defaultShape))
}

@Test func applyMutatesDocument() {
    let store = DocumentStore(document: .empty())
    store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
    #expect(store.document.layers[0].nodes.count == 1)
}

@Test func undoRestoresPreviousDocumentAndRedoReapplies() {
    let undoManager = UndoManager()
    let store = DocumentStore(document: .empty()) { undoManager }
    store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(store.document.layers[0].nodes.isEmpty)
    #expect(undoManager.canRedo)
    undoManager.redo()
    #expect(store.document.layers[0].nodes.count == 1)
}

@Test func noOpChangeRegistersNoUndo() {
    let undoManager = UndoManager()
    let store = DocumentStore(document: .empty()) { undoManager }
    store.apply(actionName: "아무것도 안 함") { _ in }
    #expect(!undoManager.canUndo)
}

@Test func loadReplacesDocumentAndClearsUndoStack() {
    let undoManager = UndoManager()
    let store = DocumentStore(document: .empty()) { undoManager }
    store.apply(actionName: "도형 추가") { $0.layers[0].nodes.append(makeRectNode()) }
    let replacement = VectorDocument.empty(size: CGSize(width: 50, height: 50))
    store.load(replacement)
    #expect(store.document == replacement)
    #expect(!undoManager.canUndo)
}
```

- [ ] **Step 2: 실패 확인**

Run: `cd VectaEngine && swift test`
Expected: FAIL — `cannot find 'DocumentStore' in scope`

- [ ] **Step 3: 구현** — `Sources/VectaEngine/State/DocumentStore.swift`

```swift
import Combine
import Foundation

/// 모든 모델 변경의 단일 경로. 메인 스레드에서만 사용한다 (스펙 9절).
///
/// undo는 스냅샷 방식: apply 1회 = undo 1단계. 드래그 중에는 호출하지 말고
/// 제스처가 끝나는 시점(mouseUp)에 1회 호출한다.
public final class DocumentStore: ObservableObject {
    @Published public private(set) var document: VectorDocument

    private let undoManagerProvider: () -> UndoManager?

    public init(
        document: VectorDocument,
        undoManagerProvider: @escaping () -> UndoManager? = { nil }
    ) {
        self.document = document
        self.undoManagerProvider = undoManagerProvider
    }

    public func apply(actionName: String, _ change: (inout VectorDocument) -> Void) {
        var updated = document
        change(&updated)
        guard updated != document else { return }
        registerUndo(restoring: document, actionName: actionName)
        document = updated
    }

    /// 파일 열기 등 undo 대상이 아닌 전체 교체.
    public func load(_ newDocument: VectorDocument) {
        document = newDocument
        undoManagerProvider()?.removeAllActions(withTarget: self)
    }

    private func registerUndo(restoring snapshot: VectorDocument, actionName: String) {
        guard let undoManager = undoManagerProvider() else { return }
        undoManager.registerUndo(withTarget: self) { store in
            // apply를 재사용하므로 undo 실행이 redo 등록까지 처리한다.
            store.apply(actionName: actionName) { $0 = snapshot }
        }
        undoManager.setActionName(actionName)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `cd VectaEngine && swift test`
Expected: PASS (전체 테스트 — 이 시점에 엔진 테스트 전부 그린이어야 함)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 스냅샷 undo를 갖춘 DocumentStore 추가"
```

---

### Task 12: 앱 스캐폴드 (XcodeGen + 문서 기반 앱 골격)

이 태스크는 UI 셸이라 단위 테스트 대신 **빌드 성공 + 실행 스모크**로 검증한다.

**Files:**
- Create: `VectaApp/project.yml`
- Create: `VectaApp/Sources/main.swift`
- Create: `VectaApp/Sources/AppDelegate.swift`
- Create: `VectaApp/Sources/MainMenuBuilder.swift`
- Create: `VectaApp/Sources/Document/VectaDocument.swift` (이 단계에선 빈 문서)

- [ ] **Step 1: project.yml 작성**

```yaml
name: Vecta
options:
  bundleIdPrefix: dev.vecta
  deploymentTarget:
    macOS: "14.0"
packages:
  VectaEngine:
    path: ../VectaEngine
targets:
  Vecta:
    type: application
    platform: macOS
    sources: [Sources]
    dependencies:
      - package: VectaEngine
    settings:
      base:
        SWIFT_VERSION: "5.0"
        PRODUCT_BUNDLE_IDENTIFIER: dev.vecta.app
        CODE_SIGN_IDENTITY: "-"
    info:
      path: Sources/Info.plist
      properties:
        CFBundleName: Vecta
        NSPrincipalClass: NSApplication
        LSMinimumSystemVersion: "14.0"
        CFBundleDocumentTypes:
          - CFBundleTypeName: Adobe Illustrator Document
            CFBundleTypeRole: Editor
            LSItemContentTypes: [com.adobe.illustrator]
            LSHandlerRank: Alternate
            NSDocumentClass: Vecta.VectaDocument
        UTImportedTypeDeclarations:
          - UTTypeIdentifier: com.adobe.illustrator
            UTTypeDescription: Adobe Illustrator Document
            UTTypeConformsTo: [com.adobe.pdf]
            UTTypeTagSpecification:
              public.filename-extension: [ai]
schemes:
  Vecta:
    build:
      targets:
        Vecta: all
    run:
      config: Debug
```

- [ ] **Step 2: 앱 진입점 작성**

`VectaApp/Sources/main.swift`:

```swift
import AppKit

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

`VectaApp/Sources/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenuBuilder.build()
    }
}
```

- [ ] **Step 3: 메뉴 빌더 작성** — `VectaApp/Sources/MainMenuBuilder.swift`

```swift
import AppKit

enum MainMenuBuilder {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(wrap(appMenu()))
        mainMenu.addItem(wrap(fileMenu()))
        mainMenu.addItem(wrap(editMenu()))
        return mainMenu
    }

    private static func wrap(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Vecta")
        menu.addItem(
            withTitle: "Vecta에 관하여",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Vecta 종료",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "파일")
        menu.addItem(
            withTitle: "새 문서",
            action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        menu.addItem(
            withTitle: "열기…",
            action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "닫기",
            action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(
            withTitle: "저장…",
            action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = menu.addItem(
            withTitle: "다른 이름으로 저장…",
            action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "편집")
        menu.addItem(
            withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(
            withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        return menu
    }
}
```

- [ ] **Step 4: 빈 NSDocument 작성** — `VectaApp/Sources/Document/VectaDocument.swift`

```swift
import AppKit
import VectaEngine

final class VectaDocument: NSDocument {
    private(set) lazy var store = DocumentStore(document: .empty()) {
        [weak self] in self?.undoManager
    }

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        addWindowController(NSWindowController(window: window))
    }
}
```

(읽기/쓰기는 Task 13, 캔버스 UI는 Task 14에서 채운다.)

- [ ] **Step 5: 프로젝트 생성·빌드**

Run:
```bash
cd VectaApp && xcodegen generate && \
xcodebuild -project Vecta.xcodeproj -scheme Vecta -configuration Debug \
  -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 실행 스모크 (수동)**

Run: `open VectaApp/build/Build/Products/Debug/Vecta.app`
확인: 앱 실행 → 빈 윈도우가 뜨고("제목 없음") 메뉴에 파일/편집이 보인다. ⌘Q로 종료.

- [ ] **Step 7: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: XcodeGen 기반 문서형 앱 골격 추가"
```

---

### Task 13: VectaDocument 파일 I/O 연결

**Files:**
- Modify: `VectaApp/Sources/Document/VectaDocument.swift`

- [ ] **Step 1: 읽기/쓰기 오버라이드 추가** — VectaDocument 클래스에 추가

```swift
    override func data(ofType typeName: String) throws -> Data {
        try AIFileWriter.data(for: store.document)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let document = try AIFileReader.document(from: data)
        store.load(document)
    }
```

`ImportError`/`ExportError`가 `LocalizedError`라 NSDocument가 한국어 메시지를
에러 시트로 그대로 보여준다 — 추가 변환 불필요.

- [ ] **Step 2: 빌드 확인**

Run:
```bash
cd VectaApp && xcodebuild -project Vecta.xcodeproj -scheme Vecta \
  -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 수동 스모크**

`open VectaApp/build/Build/Products/Debug/Vecta.app`
확인: 빈 문서를 ⌘S → `~/Desktop/m1-empty.ai` 저장 → ⌘W → ⌘O로 다시 열기 →
에러 없이 빈 문서가 열린다. `open -a Preview ~/Desktop/m1-empty.ai`로
미리보기에서도 흰 페이지가 열린다.

- [ ] **Step 4: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: NSDocument에 .ai 읽기·쓰기 연결"
```

---

### Task 14: 캔버스 + 도구 상태 + 툴바

**Files:**
- Create: `VectaApp/Sources/Canvas/ToolState.swift`
- Create: `VectaApp/Sources/Canvas/CanvasView.swift`
- Create: `VectaApp/Sources/Panels/ToolbarView.swift`
- Modify: `VectaApp/Sources/Document/VectaDocument.swift` (윈도우 콘텐츠 구성)

- [ ] **Step 1: ToolState 작성** — `VectaApp/Sources/Canvas/ToolState.swift`

```swift
import Foundation

enum ShapeKind: String, CaseIterable {
    case rectangle
    case ellipse

    var koreanName: String {
        switch self {
        case .rectangle: return "사각형"
        case .ellipse: return "타원"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        }
    }
}

final class ToolState: ObservableObject {
    @Published var activeShape: ShapeKind = .rectangle
}
```

- [ ] **Step 2: CanvasView 작성** — `VectaApp/Sources/Canvas/CanvasView.swift`

```swift
import AppKit
import Combine
import VectaEngine

/// 아트보드 크기와 동일한 frame을 갖는 문서 뷰. 모델 좌표 = 뷰 좌표(flipped).
final class CanvasView: NSView {
    private let store: DocumentStore
    private let toolState: ToolState
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var storeSubscription: AnyCancellable?

    override var isFlipped: Bool { true }

    init(store: DocumentStore, toolState: ToolState) {
        self.store = store
        self.toolState = toolState
        super.init(frame: NSRect(origin: .zero, size: store.document.artboard.size))
        storeSubscription = store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.documentDidChange() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Interface Builder를 사용하지 않는다")
    }

    private func documentDidChange() {
        setFrameSize(store.document.artboard.size)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(CGColor.white)
        context.fill(CGRect(origin: .zero, size: store.document.artboard.size))
        SceneRenderer.render(store.document, in: context)
        drawDragPreview(in: context)
    }

    // MARK: - 도형 드래그

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
        guard let start = dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = CGRect(corner: start, oppositeCorner: end)
        guard rect.width >= 1, rect.height >= 1 else { return }
        let path = makePath(in: rect)
        store.apply(actionName: "도형 추가") { document in
            document.layers[0].nodes.append(
                .path(PathNode(path: path, style: .defaultShape)))
        }
    }

    private func makePath(in rect: CGRect) -> BezierPath {
        switch toolState.activeShape {
        case .rectangle: return .rectangle(rect)
        case .ellipse: return .ellipse(in: rect)
        }
    }

    private func drawDragPreview(in context: CGContext) {
        guard let start = dragStart, let current = dragCurrent else { return }
        let rect = CGRect(corner: start, oppositeCorner: current)
        context.saveGState()
        context.setAlpha(0.5)
        context.addPath(makePath(in: rect).cgPath)
        context.setFillColor(CGColor(srgbRed: 0.27, green: 0.51, blue: 0.96, alpha: 1))
        context.fillPath()
        context.restoreGState()
    }
}
```

- [ ] **Step 3: ToolbarView 작성** — `VectaApp/Sources/Panels/ToolbarView.swift`

```swift
import SwiftUI

struct ToolbarView: View {
    @ObservedObject var toolState: ToolState

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ShapeKind.allCases, id: \.self) { kind in
                Button {
                    toolState.activeShape = kind
                } label: {
                    Image(systemName: kind.symbolName)
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .background(
                    toolState.activeShape == kind
                        ? Color.accentColor.opacity(0.25) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
                .help(kind.koreanName)
                .accessibilityLabel(kind.koreanName)
            }
            Spacer()
        }
        .padding(.top, 12)
        .frame(width: 56)
    }
}
```

- [ ] **Step 4: 윈도우 콘텐츠 구성** — VectaDocument의 `makeWindowControllers()`를 교체

파일 상단에 `import SwiftUI` 추가 (NSHostingView 사용).

```swift
    private let toolState = ToolState()

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentView = makeContentView()
        window.center()
        addWindowController(NSWindowController(window: window))
    }

    private func makeContentView() -> NSView {
        let scrollView = NSScrollView()
        scrollView.documentView = CanvasView(store: store, toolState: toolState)
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

- [ ] **Step 5: 빌드 확인**

Run:
```bash
cd VectaApp && xcodebuild -project Vecta.xcodeproj -scheme Vecta \
  -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 수동 스모크**

`open VectaApp/build/Build/Products/Debug/Vecta.app`
확인: 드래그로 사각형이 그려진다. 툴바에서 타원 선택 후 타원도 그려진다.
⌘Z로 사라지고 ⇧⌘Z로 돌아온다.

- [ ] **Step 7: 포맷 후 커밋**

```bash
swift format --in-place --recursive VectaApp/Sources
git add -A && git commit -m "feat: 캔버스 드래그 도형 그리기와 SwiftUI 툴바 추가"
```

---

### Task 15: 통합 수동 검증 + README

**Files:**
- Create: `README.md`

- [ ] **Step 1: 엔진 전체 회귀**

Run: `cd VectaEngine && swift build && swift test`
Expected: 전체 PASS

- [ ] **Step 2: 통합 수동 검증 체크리스트**

앱 실행 (`open VectaApp/build/Build/Products/Debug/Vecta.app`) 후 순서대로:

1. 새 문서가 자동으로 열린다 (제목 없음)
2. 사각형 3개 + 타원 2개를 드래그로 그린다
3. ⌘Z 5회 → 전부 사라짐, ⇧⌘Z 5회 → 전부 복귀
4. ⌘S → `~/Desktop/m1-test.ai` 저장
5. `open -a Preview ~/Desktop/m1-test.ai` → 미리보기에서 도형 5개가 같은 위치에 렌더링
6. 앱에서 ⌘W로 닫고 ⌘O로 `m1-test.ai` 다시 열기 → 도형 5개 그대로 복원
7. 다시 연 문서에 도형 1개 추가 → ⌘S 덮어쓰기 → 재열기 → 6개 확인
8. 핀치(또는 ⌘+스크롤)로 줌 동작 확인

하나라도 실패하면 superpowers:systematic-debugging 스킬로 원인을 찾고
수정 후 체크리스트를 처음부터 다시 수행한다.

- [ ] **Step 3: README 작성** — `README.md`

```markdown
# Vecta

macOS 네이티브 벡터 그래픽 에디터. Adobe Illustrator 없이 .ai(PDF 호환)
파일을 만들고, 열고, 편집하는 것이 목표다.

## 구조

- `VectaEngine/` — 모델·렌더러·.ai 입출력·undo 스토어 (SPM, UI 의존성 없음)
- `VectaApp/` — AppKit 캔버스 + SwiftUI 패널 셸 (XcodeGen)
- `docs/superpowers/specs/` — 설계 스펙
- `docs/superpowers/plans/` — 마일스톤별 구현 계획

## 빌드

```bash
# 엔진 테스트
cd VectaEngine && swift test

# 앱 빌드 (XcodeGen 필요: brew install xcodegen)
cd VectaApp && xcodegen generate && \
  xcodebuild -project Vecta.xcodeproj -scheme Vecta \
    -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Vecta.app
```

## 현재 상태

- [x] M1 최소 루프: 도형 그리기 → .ai 저장 → 재열기 100% 복원
- [ ] M2 편집: 선택/이동/리사이즈/직접선택/펜
- [ ] M3 스타일·구조: 인스펙터, 레이어 패널
- [ ] M4 외부 .ai 임포트 (PDF 콘텐츠 스트림 파서)
- [ ] M5 텍스트·이미지·패스파인더·정렬
- [ ] M6 마감
```

- [ ] **Step 4: 커밋**

```bash
git add -A && git commit -m "docs: README 추가 — M1 최소 루프 완료"
```

---

## 완료 기준 (M1 Definition of Done)

- `swift test` 전체 그린 (엔진 단위 테스트 ~25개)
- 앱에서 도형 드래그 생성·undo/redo·.ai 저장·재열기 100% 복원
- 저장된 .ai가 미리보기(Preview.app)에서 동일하게 렌더링
- 모든 커밋이 analyze → test → format 순서를 지킴

## M2 예고 (다음 계획에서 다룸)

선택 도구(클릭/마퀴/이동/리사이즈/회전), 직접 선택(앵커 편집), 펜 도구,
Tool 프로토콜 + CanvasEvent 추상화 도입(CanvasView 리팩토링), 히트테스트
(`BezierPath` bounds·contains 기하 추가).
