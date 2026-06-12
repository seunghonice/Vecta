# Vecta M4b-1 — 외부 .ai 임포트: 그라디언트 (sh·shading 패턴) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** M4a 파서 코어 위에 그라디언트 임포트를 얹는다 — `sh` 연산자와 패턴 컬러스페이스 shading 채움(`scn /P1`)을 PDF Function(type 2·3) 평가로 GradientStop을 샘플링해 M3 `Gradient`(선형/원형) fill PathNode로 변환한다. 미지원(mesh·function type 0/4·tiling pattern)은 ImportReport로 수집한다. (GitHub 이슈 #11, PR은 `Closes #11`. 이미지=#13/M4b-2, 텍스트=#14/M4b-3는 별도 PR)

**Architecture:** PDF Function을 순수 값 타입(`PDFFunction` enum)으로 모델링해 헤드리스로 평가·검증하고, `PDFShading`이 CGPDF shading 객체를 읽어 `Gradient`로 변환한다. `ContentStreamParser`의 기존 미지원-리포트 콜백(`sh`, `scn` 패턴)을 실제 변환 경로로 교체한다. 그라디언트 좌표는 다른 임포트 노드와 동일하게 모델 좌표로 베이크하며(노드 transform=identity), SceneRenderer는 무변경 — M3 그라디언트 렌더가 그대로 그린다.

**Tech Stack:** Swift 6 (언어 모드 v5), Swift Testing, CoreGraphics(CGPDFScanner/CGPDFDictionary/CGPDFArray/CGPDFStream), XcodeGen. 엔진 플랫폼 .v14.

**참조:** 스펙 `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` §5(ImportAI)·§12-M4, 이슈 #11(M4b-1 재범위), M4a 계획(파서 컨벤션·결정 기록), PDF 32000-1 §7.10(Function)·§8.7.4.5(Shading)·§8.7.3.3(Pattern).

---

## 커밋 규칙 (전역 규칙 — 기존과 동일)

매 커밋 전: ① `cd VectaEngine && swift build`(앱 변경 시 xcodebuild 추가) → ② `swift test` → ③ `swift format --in-place --recursive Sources Tests`(앱은 `VectaApp/Sources`) → ④ commit. 한국어 메시지+접두사, Co-Authored-By 금지. 테스트 실패 시 수정 후 ①부터 재수행.

## 결정 기록 (이 계획에서 확정)

| 결정 | 근거 |
|---|---|
| Function은 type 2(지수 보간)·3(스티칭)만 지원 | 실무 그라디언트 절대다수. type 0(샘플)·4(포스트스크립트)는 스트림 디코드/인터프리터가 필요 — 미지원 리포트 |
| Shading은 type 2(axial)·3(radial)만 | type 1(function-based)·4–7(mesh)은 모델 표현 불가 — 미지원 리포트 |
| radial 두 원 → M3 단일원 근사 (끝 원 c1·r1 사용, 시작 원 r0·c0 무시) | M3 `Gradient`는 단일 반지름(start=중심, end=원주점)만 표현. r0≠0 또는 c0≠c1이면 손실 → `unsupportedShading` 리포트 |
| Function을 도메인 **9등분 균등 샘플** → 9 GradientStop | 선형(type2 N=1)도 9개 — 렌더 결과 동일하고 분기 단순. 비선형 곡선도 9점이면 시각적 충분 |
| `/Function`이 배열(색성분 분리)이면 best-effort 첫 요소만 + 손실 가능 리포트 | 실무 대부분 단일 다출력 함수. 성분별 분리 함수는 드묾 |
| `/ColorSpace`는 name(DeviceGray/RGB/CMYK)만; ICCBased 등 배열 → 미지원 리포트 | PDFColorSpace 재사용. ICC 프로파일 파싱은 비목표 |
| `sh` → 현재 클립(없으면 mediaBox 사각형) 패스를 그라디언트 fill PathNode로 | 모델엔 "셰이딩 전용 노드"가 없음. sh는 클립 영역을 칠하므로 클립=채울 패스. 실무는 sh 직전 `W n` 클립이 일반적 |
| 패턴은 PatternType 2(shading)만; type 1(tiling) → 리포트 + fill 스킵 | tiling은 반복 콘텐츠 — 모델 표현 불가 |
| pattern 좌표 = pattern `/Matrix` × pageFlip (CTM 미적용) | 패턴 matrix는 패턴 공간 → 부모 콘텐츠 스트림 기본 좌표계(보통 페이지) 매핑. 폼 내부 패턴의 CTM 합성은 드묾 — 근사 |
| `/Extend`는 미반영 (M3는 항상 색 연장) | Extend [false false]의 "경계 밖 투명"은 M3 렌더와 다르나 드묾 — 리포트 생략 |
| Gradient 좌표는 모델 좌표로 베이크 (노드 transform=identity) | 다른 임포트 노드와 일관. M3 SceneRenderer는 gradient start/end를 패스 로컬로 해석 — identity면 로컬=모델 |

## 파일 구조 (M4b-1 추가/변경분)

```
VectaEngine/Sources/VectaEngine/ImportAI/
├── PDFFunction.swift            (생성)  # 순수 값 모델 + evaluate + sampleStops (Task 1)
│                                        # + CGPDF parse extension (Task 2)
├── CGPDFReading.swift           (생성)  # CGPDFDictionary/Array/Object 읽기 헬퍼 (Task 2)
├── PDFShading.swift             (생성)  # CGPDF shading → Gradient (Task 2)
└── ContentStreamParser.swift    (수정)  # sh 실제 변환(Task 3), 패턴 fill(Task 4), mediaBox 저장

VectaEngine/Sources/VectaEngine/Model/
└── Style.swift                  (수정)  # Gradient.applying(_:)·Paint 헬퍼 (Task 3)

VectaEngine/Tests/VectaEngineTests/
├── PDFFunctionTests.swift           (생성)  # 순수 평가 (Task 1)
├── PDFShadingTests.swift            (생성)  # 픽스처 shading → Gradient (Task 2)
└── ContentStreamParserShadingTests.swift (생성)  # sh·패턴 통합 (Task 3·4)
```

핵심 계약 (기존 — 신규 코드가 의존):
- `ContentStreamParser`는 CTM·pageFlip을 좌표에 베이크 (산출 노드 transform=identity).
- `PDFColorSpace.color(from:)` (M4a) — 성분 배열 → RGBA, 성분 수 부족 시 nil.
- M3 `Gradient { stops, start, end }`, `Paint { color, linearGradient, radialGradient }`.
- 테스트 베이스라인: 엔진 279개 그린. 브랜치 `m4b1-gradient-import` (base: `m4a-import-core` — PR #12 미머지 시 스택).
- `makeTestPDF` 픽스처(M4a): `resources`·`extraObjects` 주입, 객체 번호 = `3 + 2×pages.count`번부터.

---

### Task 1: PDFFunction 값 모델 + 평가 (순수, 헤드리스)

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/PDFFunction.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PDFFunctionTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

private func expectClose(
  _ values: [CGFloat], _ expected: [CGFloat],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(values.count == expected.count, sourceLocation: sourceLocation)
  for (actual, want) in zip(values, expected) {
    #expect(abs(actual - want) < 0.0001, sourceLocation: sourceLocation)
  }
}

@Test func exponentialLinearInterpolates() {
  let function = PDFFunction.exponential(
    c0: [0], c1: [1], exponent: 1, domain: 0...1)
  expectClose(function.evaluate(0), [0])
  expectClose(function.evaluate(0.5), [0.5])
  expectClose(function.evaluate(1), [1])
}

@Test func exponentialNonLinearUsesExponent() {
  let function = PDFFunction.exponential(
    c0: [0], c1: [1], exponent: 2, domain: 0...1)
  expectClose(function.evaluate(0.5), [0.25])
}

@Test func exponentialMultiComponentRGB() {
  let function = PDFFunction.exponential(
    c0: [1, 0, 0], c1: [0, 0, 1], exponent: 1, domain: 0...1)
  expectClose(function.evaluate(0.5), [0.5, 0, 0.5])
}

@Test func evaluateClampsToDomain() {
  let function = PDFFunction.exponential(
    c0: [0.2], c1: [0.8], exponent: 1, domain: 0...1)
  expectClose(function.evaluate(-1), [0.2])
  expectClose(function.evaluate(2), [0.8])
}

@Test func stitchingRoutesToSubinterval() {
  // 두 구간 [0,0.5)→f0, [0.5,1]→f1. 각 encode 0…1.
  let f0 = PDFFunction.exponential(c0: [0], c1: [1], exponent: 1, domain: 0...1)
  let f1 = PDFFunction.exponential(c0: [0], c1: [2], exponent: 1, domain: 0...1)
  let stitch = PDFFunction.stitching(
    functions: [f0, f1], bounds: [0.5],
    encode: [(0, 1), (0, 1)], domain: 0...1)
  // t=0.25 → f0의 입력 0.5 → 0.5
  expectClose(stitch.evaluate(0.25), [0.5])
  // t=0.75 → f1의 입력 0.5 → 1.0
  expectClose(stitch.evaluate(0.75), [1.0])
}

@Test func stitchingReversedEncodeMapsBackwards() {
  let f0 = PDFFunction.exponential(c0: [0], c1: [1], exponent: 1, domain: 0...1)
  let stitch = PDFFunction.stitching(
    functions: [f0], bounds: [], encode: [(1, 0)], domain: 0...1)
  // 단일 구간 [0,1] → encode (1,0): t=0 → 입력 1 → 1.0
  expectClose(stitch.evaluate(0), [1.0])
  expectClose(stitch.evaluate(1), [0.0])
}

@Test func sampleStopsProducesEvenlySpacedStops() {
  let function = PDFFunction.exponential(
    c0: [1, 0, 0], c1: [0, 0, 1], exponent: 1, domain: 0...1)
  let stops = function.sampleStops(count: 3, colorSpace: .deviceRGB, domain: 0...1)
  #expect(stops.count == 3)
  #expect(stops[0].location == 0)
  #expect(stops[1].location == 0.5)
  #expect(stops[2].location == 1)
  #expect(stops[0].color == RGBA(red: 1, green: 0, blue: 0))
  #expect(stops[2].color == RGBA(red: 0, green: 0, blue: 1))
}

@Test func sampleStopsSkipsComponentMismatch() {
  // RGB 색공간(3성분)인데 함수가 1성분 → 색 변환 실패로 모든 스톱 제외
  let function = PDFFunction.exponential(c0: [0], c1: [1], exponent: 1, domain: 0...1)
  let stops = function.sampleStops(count: 3, colorSpace: .deviceRGB, domain: 0...1)
  #expect(stops.isEmpty)
}
```

- [ ] **Step 2: 실패 확인** — `cd VectaEngine && swift test` → FAIL (`PDFFunction` 없음)

- [ ] **Step 3: 구현** — `ImportAI/PDFFunction.swift`

```swift
import CoreGraphics

/// PDF 함수 (PDF §7.10) — 그라디언트 색 보간용. type 2(지수)·3(스티칭)만 모델링.
/// type 0(샘플)·4(포스트스크립트)는 파싱 단계에서 nil (미지원 리포트 — Task 2).
enum PDFFunction: Equatable {
  case exponential(
    c0: [CGFloat], c1: [CGFloat], exponent: CGFloat, domain: ClosedRange<CGFloat>)
  indirect case stitching(
    functions: [PDFFunction], bounds: [CGFloat],
    encode: [(CGFloat, CGFloat)], domain: ClosedRange<CGFloat>)

  /// 입력 t의 색 성분 배열. domain 밖은 클램프.
  func evaluate(_ t: CGFloat) -> [CGFloat] {
    switch self {
    case .exponential(let c0, let c1, let exponent, let domain):
      let x = min(max(t, domain.lowerBound), domain.upperBound)
      let factor = pow(x, exponent)
      return zip(c0, c1).map { $0 + factor * ($1 - $0) }
    case .stitching(let functions, let bounds, let encode, let domain):
      guard !functions.isEmpty, encode.count == functions.count else { return [] }
      let x = min(max(t, domain.lowerBound), domain.upperBound)
      // 구간 k: x < bounds[k] 인 첫 k (없으면 마지막).
      var k = 0
      while k < bounds.count, x >= bounds[k] { k += 1 }
      k = min(k, functions.count - 1)
      let lo = k == 0 ? domain.lowerBound : bounds[k - 1]
      let hi = k == bounds.count ? domain.upperBound : bounds[k]
      let (encodeLo, encodeHi) = encode[k]
      let mapped =
        hi == lo
        ? encodeLo
        : encodeLo + (x - lo) * (encodeHi - encodeLo) / (hi - lo)
      return functions[k].evaluate(mapped)
    }
  }

  /// 도메인을 count등분 균등 샘플해 GradientStop 배열을 만든다.
  /// 성분→RGBA는 colorSpace가 담당하며, 성분 수 불일치 시 그 스톱을 건너뛴다.
  func sampleStops(
    count: Int, colorSpace: PDFColorSpace, domain: ClosedRange<CGFloat>
  ) -> [GradientStop] {
    guard count >= 2 else { return [] }
    var stops: [GradientStop] = []
    for index in 0..<count {
      let fraction = CGFloat(index) / CGFloat(count - 1)
      let t = domain.lowerBound + fraction * (domain.upperBound - domain.lowerBound)
      guard let color = colorSpace.color(from: evaluate(t)) else { continue }
      stops.append(GradientStop(location: Double(fraction), color: color))
    }
    return stops
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (288개 = 279 + 9)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF 함수 모델 — 지수·스티칭 평가와 그라디언트 스톱 샘플링"
```

---

### Task 2: CGPDF 읽기 헬퍼 + PDFFunction·PDFShading 파싱 → Gradient

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/CGPDFReading.swift`
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/PDFFunction.swift` (parse extension)
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/PDFShading.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PDFShadingTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성** — 픽스처 PDF의 `/Shading` 리소스를 꺼내 변환을 검증한다. 헬퍼는 M4a `makeTestPDF`를 쓴다.

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

/// 픽스처 PDF의 첫 페이지 /Resources/Shading/<name> 객체를 PDFShading으로 파싱한다.
private func parseShadingResource(
  name: String, shadingObject: String, mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200)
) -> (gradient: Gradient, isRadial: Bool, lossyRadial: Bool)? {
  // sh 한 줄로 셰이딩 리소스를 참조하는 최소 콘텐츠.
  let data = makeTestPDF(
    content: "/\(name) sh",
    mediaBox: mediaBox,
    resources: "<< /Shading << /\(name) 5 0 R >> >>",
    extraObjects: [shadingObject])
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  guard let object = CGPDFContentStreamGetResource(stream, "Shading", name) else { return nil }
  return PDFShading.parse(object)
}

private let exponentialFunction =
  "<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"

@Test func parsesAxialShadingToLinearGradient() {
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceRGB "
    + "/Coords [10 20 90 20] /Function \(exponentialFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(!parsed.isRadial)
  #expect(!parsed.lossyRadial)
  #expect(parsed.gradient.start == CGPoint(x: 10, y: 20))
  #expect(parsed.gradient.end == CGPoint(x: 90, y: 20))
  #expect(parsed.gradient.stops.count == 9)  // 9등분 샘플
  #expect(parsed.gradient.stops.first?.color == RGBA(red: 1, green: 0, blue: 0))
  #expect(parsed.gradient.stops.last?.color == RGBA(red: 0, green: 0, blue: 1))
}

@Test func parsesRadialShadingWithEndCircle() {
  // 동심원(c0==c1, r0=0) — 손실 없음
  let shading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB "
    + "/Coords [50 50 0 50 50 40] /Function \(exponentialFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.isRadial)
  #expect(!parsed.lossyRadial)
  #expect(parsed.gradient.start == CGPoint(x: 50, y: 50))  // 끝 원 중심
  #expect(parsed.gradient.end == CGPoint(x: 90, y: 50))  // 중심 + 반지름 40
}

@Test func radialWithNonZeroStartRadiusReportsLossy() {
  let shading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB "
    + "/Coords [50 50 10 50 50 40] /Function \(exponentialFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.lossyRadial)  // r0=10 ≠ 0 → 근사 손실
}

@Test func stitchingFunctionShadingSamples() {
  let stitch =
    "<< /FunctionType 3 /Domain [0 1] /Bounds [0.5] /Encode [0 1 0 1] "
    + "/Functions [\(exponentialFunction) "
    + "<< /FunctionType 2 /Domain [0 1] /C0 [0 1 0] /C1 [1 1 1] /N 1 >>] >>"
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function \(stitch) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.gradient.stops.count == 9)
}

@Test func unsupportedShadingTypeReturnsNil() {
  // type 1(function-based) 미지원
  let shading =
    "<< /ShadingType 1 /ColorSpace /DeviceRGB /Function \(exponentialFunction) >>"
  #expect(parseShadingResource(name: "Sh0", shadingObject: shading) == nil)
}

@Test func unsupportedFunctionTypeReturnsNil() {
  // function type 0(샘플) 미지원 → shading 파싱도 nil
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] "
    + "/Function << /FunctionType 0 /Domain [0 1] >> >>"
  #expect(parseShadingResource(name: "Sh0", shadingObject: shading) == nil)
}

@Test func grayColorSpaceShadingConverts() {
  let grayFunction = "<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>"
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function \(grayFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.gradient.stops.first?.color == RGBA(red: 0, green: 0, blue: 0))
  #expect(parsed.gradient.stops.last?.color == RGBA(red: 1, green: 1, blue: 1))
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`PDFShading` 없음)

- [ ] **Step 3: CGPDF 읽기 헬퍼** — `ImportAI/CGPDFReading.swift`. CGPDF 객체에서 숫자·배열·정수·딕셔너리를 읽는 공용 헬퍼 (파서·셰이딩·함수 공유).

```swift
import CoreGraphics

/// CGPDF 객체 그래프 읽기 헬퍼 (ImportAI 내부 공용).
enum CGPDFReading {
  /// 객체가 dict면 그대로, stream이면 그 dict를 반환.
  static func dictionary(from object: CGPDFObjectRef) -> CGPDFDictionaryRef? {
    var dict: CGPDFDictionaryRef? = nil
    if CGPDFObjectGetValue(object, .dictionary, &dict) { return dict }
    var stream: CGPDFStreamRef? = nil
    if CGPDFObjectGetValue(object, .stream, &stream), let stream {
      return CGPDFStreamGetDictionary(stream)
    }
    return nil
  }

  static func integer(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Int? {
    var value: CGPDFInteger = 0
    guard CGPDFDictionaryGetInteger(dictionary, key, &value) else { return nil }
    return value
  }

  static func number(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGFloat? {
    var value: CGPDFReal = 0
    guard CGPDFDictionaryGetNumber(dictionary, key, &value) else { return nil }
    return CGFloat(value)
  }

  static func array(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
    var array: CGPDFArrayRef? = nil
    guard CGPDFDictionaryGetArray(dictionary, key, &array) else { return nil }
    return array
  }

  /// 배열을 CGFloat 목록으로 (숫자가 아닌 원소가 있으면 nil).
  static func numbers(_ dictionary: CGPDFDictionaryRef, _ key: String) -> [CGFloat]? {
    guard let array = array(dictionary, key) else { return nil }
    var result: [CGFloat] = []
    for index in 0..<CGPDFArrayGetCount(array) {
      var value: CGPDFReal = 0
      guard CGPDFArrayGetNumber(array, index, &value) else { return nil }
      result.append(CGFloat(value))
    }
    return result
  }

  /// [lo hi] 2원소 배열 → ClosedRange (lo ≤ hi 보장 못 하면 nil).
  static func range(_ dictionary: CGPDFDictionaryRef, _ key: String) -> ClosedRange<CGFloat>? {
    guard let values = numbers(dictionary, key), values.count >= 2,
      values[0] <= values[1]
    else { return nil }
    return values[0]...values[1]
  }

  /// dict의 name 값 (DeviceRGB 등).
  static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
    var pointer: UnsafePointer<CChar>? = nil
    guard CGPDFDictionaryGetName(dictionary, key, &pointer), let pointer else { return nil }
    return String(cString: pointer)
  }

  /// dict의 임의 객체 (배열/딕셔너리/스트림 등).
  static func object(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFObjectRef? {
    var object: CGPDFObjectRef? = nil
    guard CGPDFDictionaryGetObject(dictionary, key, &object) else { return nil }
    return object
  }
}
```

- [ ] **Step 4: PDFFunction.parse** — `PDFFunction.swift` 끝에 extension 추가

```swift
extension PDFFunction {
  /// CGPDF 함수 객체(dict 또는 stream) → PDFFunction. type 2/3만, 그 외 nil.
  /// 도메인은 /Domain (없으면 0…1).
  static func parse(_ object: CGPDFObjectRef) -> PDFFunction? {
    guard let dictionary = CGPDFReading.dictionary(from: object),
      let functionType = CGPDFReading.integer(dictionary, "FunctionType")
    else { return nil }
    let domain = CGPDFReading.range(dictionary, "Domain") ?? (0...1)
    switch functionType {
    case 2:
      let c0 = CGPDFReading.numbers(dictionary, "C0") ?? [0]
      let c1 = CGPDFReading.numbers(dictionary, "C1") ?? [1]
      let exponent = CGPDFReading.number(dictionary, "N") ?? 1
      guard c0.count == c1.count, !c0.isEmpty else { return nil }
      return .exponential(c0: c0, c1: c1, exponent: exponent, domain: domain)
    case 3:
      guard let functionsArray = CGPDFReading.array(dictionary, "Functions") else { return nil }
      var subfunctions: [PDFFunction] = []
      for index in 0..<CGPDFArrayGetCount(functionsArray) {
        var element: CGPDFObjectRef? = nil
        guard CGPDFArrayGetObject(functionsArray, index, &element), let element,
          let sub = parse(element)
        else { return nil }
        subfunctions.append(sub)
      }
      guard !subfunctions.isEmpty else { return nil }
      let bounds = CGPDFReading.numbers(dictionary, "Bounds") ?? []
      let encodeRaw = CGPDFReading.numbers(dictionary, "Encode") ?? []
      var encode: [(CGFloat, CGFloat)] = []
      var index = 0
      while index + 1 < encodeRaw.count {
        encode.append((encodeRaw[index], encodeRaw[index + 1]))
        index += 2
      }
      guard encode.count == subfunctions.count, bounds.count == subfunctions.count - 1
      else { return nil }
      return .stitching(
        functions: subfunctions, bounds: bounds, encode: encode, domain: domain)
    default:
      return nil  // type 0(샘플)·4(포스트스크립트) 미지원
    }
  }
}
```

- [ ] **Step 5: PDFShading 구현** — `ImportAI/PDFShading.swift`

```swift
import CoreGraphics

/// CGPDF shading 객체 → M3 Gradient (스펙 §5). ShadingType 2(axial)/3(radial)만.
/// type 1·4–7(mesh)·미지원 함수·비단순 색공간은 nil (호출부가 리포트).
/// 좌표는 셰이딩 좌표계 그대로 — 호출부가 모델 좌표로 베이크한다.
enum PDFShading {
  /// 함수를 균등 샘플하는 GradientStop 개수.
  static let sampleCount = 9

  static func parse(
    _ object: CGPDFObjectRef
  ) -> (gradient: Gradient, isRadial: Bool, lossyRadial: Bool)? {
    guard let dictionary = CGPDFReading.dictionary(from: object),
      let shadingType = CGPDFReading.integer(dictionary, "ShadingType"),
      shadingType == 2 || shadingType == 3,
      let colorSpace = colorSpace(dictionary),
      let functionObject = functionObject(dictionary),
      let function = PDFFunction.parse(functionObject),
      let coords = CGPDFReading.numbers(dictionary, "Coords")
    else { return nil }
    let domain = CGPDFReading.range(dictionary, "Domain") ?? (0...1)
    let stops = function.sampleStops(
      count: sampleCount, colorSpace: colorSpace, domain: domain)
    guard stops.count >= 2 else { return nil }

    if shadingType == 2 {
      guard coords.count >= 4 else { return nil }
      let gradient = Gradient(
        stops: stops,
        start: CGPoint(x: coords[0], y: coords[1]),
        end: CGPoint(x: coords[2], y: coords[3]))
      return (gradient, false, false)
    } else {
      guard coords.count >= 6 else { return nil }
      // M3 단일원 근사: 끝 원(c1, r1) 사용, 시작 원(r0, c0) 무시.
      let startRadius = coords[2]
      let endCenter = CGPoint(x: coords[3], y: coords[4])
      let endRadius = coords[5]
      let lossy =
        startRadius != 0 || coords[0] != coords[3] || coords[1] != coords[4]
      let gradient = Gradient(
        stops: stops, start: endCenter,
        end: CGPoint(x: endCenter.x + endRadius, y: endCenter.y))
      return (gradient, true, lossy)
    }
  }

  /// /ColorSpace name(DeviceGray/RGB/CMYK)만 — 배열형(ICCBased 등)은 nil.
  private static func colorSpace(_ dictionary: CGPDFDictionaryRef) -> PDFColorSpace? {
    guard let name = CGPDFReading.name(dictionary, "ColorSpace") else { return nil }
    let space = PDFColorSpace.named(name)
    if case .unsupported = space { return nil }
    if space == .pattern { return nil }
    return space
  }

  /// /Function — 단일 함수 또는 배열(배열이면 첫 요소만, best-effort).
  private static func functionObject(_ dictionary: CGPDFDictionaryRef) -> CGPDFObjectRef? {
    guard let object = CGPDFReading.object(dictionary, "Function") else { return nil }
    // 배열이면 첫 요소 (성분별 분리 함수 — 근사).
    var array: CGPDFArrayRef? = nil
    if CGPDFObjectGetValue(object, .array, &array), let array,
      CGPDFArrayGetCount(array) > 0
    {
      var first: CGPDFObjectRef? = nil
      if CGPDFArrayGetObject(array, 0, &first) { return first }
    }
    return object
  }
}
```

- [ ] **Step 6: 통과 확인** — `swift test` → 전체 PASS (295개 = 288 + 7)

- [ ] **Step 7: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF shading·function 파싱 — axial·radial → Gradient 변환"
```

---

### Task 3: sh 연산자 — 셰이딩 채움 + Gradient 좌표 베이크

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/Model/Style.swift` (Gradient.applying)
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserShadingTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성** — `ContentStreamParserShadingTests.swift`. `parseFixture`(M4a, ContentStreamParserTests.swift)는 같은 테스트 타깃이라 직접 호출 가능.

```swift
import CoreGraphics
import Testing

@testable import VectaEngine

private let rgbFunction = "<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"

private func axialShading(coords: String) -> String {
  "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [\(coords)] /Function \(rgbFunction) >>"
}

@Test func shFillsClipRegionWithLinearGradient() {
  // W n 으로 클립을 잡고 sh — 클립 사각형이 그라디언트 fill 패스가 된다.
  let (nodes, report) = parseFixture(
    content: "10 10 80 80 re W n /Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [axialShading(coords: "10 10 90 10")])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  guard case .linearGradient(let gradient) = pathNode.style.fill else {
    Issue.record("선형 그라디언트가 아님")
    return
  }
  // 클립 (10,10,80,80) PDF → 모델 y 110…190
  #expect(pathNode.path.bounds == CGRect(x: 10, y: 110, width: 80, height: 80))
  // 그라디언트 좌표 베이크: PDF (10,10)→(90,10) → 모델 (10,190)→(90,190)
  #expect(gradient.start == CGPoint(x: 10, y: 190))
  #expect(gradient.end == CGPoint(x: 90, y: 190))
  #expect(gradient.stops.count == 9)
}

@Test func shWithoutClipFillsMediaBox() {
  let (nodes, _) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [axialShading(coords: "0 0 200 0")])
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  // 클립 없음 → mediaBox 전체 (모델 0,0,200,200)
  #expect(pathNode.path.bounds == CGRect(x: 0, y: 0, width: 200, height: 200))
  #expect(pathNode.style.fill != nil)
}

@Test func shRadialProducesRadialGradient() {
  let radialShading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [100 100 0 100 100 50] "
    + "/Function \(rgbFunction) >>"
  let (nodes, _) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [radialShading])
  guard case .path(let pathNode) = nodes[0],
    case .radialGradient = pathNode.style.fill
  else {
    Issue.record("원형 그라디언트가 아님")
    return
  }
}

@Test func unsupportedShadingStillReports() {
  // mesh(type 4) → 변환 실패, 리포트, 노드 없음
  let mesh = "<< /ShadingType 4 /ColorSpace /DeviceRGB >>"
  let (nodes, report) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [mesh])
  #expect(nodes.isEmpty)
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
}

@Test func radialLossyApproximationReports() {
  let radialShading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB /Coords [100 100 20 100 100 50] "
    + "/Function \(rgbFunction) >>"
  let (_, report) = parseFixture(
    content: "/Sh0 sh",
    resources: "<< /Shading << /Sh0 5 0 R >> >>",
    extraObjects: [radialShading])
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (sh가 아직 리포트만)

- [ ] **Step 3: Gradient.applying** — `Model/Style.swift`의 `Gradient` 정의 뒤에 추가

```swift
extension Gradient {
  /// start/end에 아핀 변환을 적용한 새 그라디언트 (임포트 좌표 베이크용).
  /// 균등 스케일 가정 — radial 반지름(start–end 거리)도 함께 스케일된다.
  public func applying(_ transform: CGAffineTransform) -> Gradient {
    Gradient(
      stops: stops,
      start: start.applying(transform),
      end: end.applying(transform))
  }
}
```

- [ ] **Step 4: ContentStreamParser 수정** — ① mediaBox 모델 사각형 저장, ② sh 핸들러 교체

`init`에 mediaBox 모델 패스 저장 (pageFlip 저장 줄 근처):

```swift
  /// PDF 사용자 공간(bottom-left) → 모델(top-left) 변환.
  private let pageFlip: CGAffineTransform
  /// 클립 없는 sh의 폴백 패스 (모델 좌표 mediaBox 사각형).
  private let mediaBoxPath: BezierPath

  init(mediaBox: CGRect) {
    pageFlip = CGAffineTransform(
      a: 1, b: 0, c: 0, d: -1, tx: -mediaBox.minX, ty: mediaBox.maxY)
    var builder = PDFPathBuilder()
    builder.rect(CGRect(origin: .zero, size: mediaBox.size))
    mediaBoxPath = builder.finish()
  }
```

`registerOperators`의 `sh` 콜백을 실제 변환으로 교체 (기존 리포트-only 제거):

```swift
    CGPDFOperatorTableSetCallback(table, "sh") { scanner, info in
      parserFrom(info).paintShading(scanner)
    }
```

`reportShading` 메서드 근처(또는 XObject 섹션 뒤)에 핸들러 추가:

```swift
  // MARK: - 셰이딩 (M4b-1)

  /// sh 연산자 — Shading 리소스를 그라디언트로 변환해 현재 클립(없으면
  /// mediaBox) 패스에 fill한다.
  private func paintShading(_ scanner: CGPDFScannerRef) {
    guard let name = Self.popName(scanner),
      let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "Shading", name)
    else {
      report.add(.unsupportedShading, detail: "셰이딩 리소스를 찾지 못함")
      return
    }
    guard let parsed = PDFShading.parse(object) else {
      report.add(.unsupportedShading, detail: "미지원 셰이딩 (mesh·function type·색공간)")
      return
    }
    if parsed.lossyRadial {
      report.add(.unsupportedShading, detail: "원형 셰이딩 근사 — 끝 원만 반영 (시작 원 무시)")
    }
    let toModel = state.ctm.concatenating(pageFlip)
    let gradient = parsed.gradient.applying(toModel)
    let paint: Paint =
      parsed.isRadial ? .radialGradient(gradient) : .linearGradient(gradient)
    let fillPath = state.clip ?? mediaBoxPath
    appendNode(
      .path(PathNode(path: fillPath, style: Style(fill: paint, opacity: state.fillAlpha))),
      explicitClip: state.clip)
  }
```

(기존 `reportShading(detail:)` 메서드는 다른 호출부가 없어졌다면 삭제. 패턴 채움 Task 4에서 다시 쓰므로 남겨둬도 무방 — 컴파일 경고가 없으면 유지, 미사용 경고 나면 삭제.)

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (300개 = 295 + 5)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: sh 연산자 — 셰이딩을 그라디언트 fill로·좌표 모델 베이크"
```

---

### Task 4: 패턴 컬러스페이스 shading 채움 (scn /P1)

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserShadingTests.swift` (추가)

- [ ] **Step 1: 실패하는 테스트 작성** — 추가

```swift
// MARK: - 패턴 채움

@Test func shadingPatternFillsPathWithGradient() {
  // cs /Pattern + scn /P1 + 패스 f — 패턴의 shading이 패스 fill 그라디언트가 된다.
  let pattern =
    "<< /Type /Pattern /PatternType 2 /Matrix [1 0 0 1 0 0] "
    + "/Shading \(axialShading(coords: "0 0 100 0")) >>"
  let (nodes, report) = parseFixture(
    content: "/Pattern cs /P1 scn 10 10 80 80 re f",
    resources: "<< /Pattern << /P1 5 0 R >> >>",
    extraObjects: [pattern])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .path(let pathNode) = nodes[0],
    case .linearGradient(let gradient) = pathNode.style.fill
  else {
    Issue.record("선형 그라디언트 fill이 아님")
    return
  }
  // 패스 (10,10,80,80) PDF → 모델 y 110…190
  #expect(pathNode.path.bounds == CGRect(x: 10, y: 110, width: 80, height: 80))
  // 패턴 좌표 베이크(Matrix identity × pageFlip): PDF (0,0)→(100,0) → 모델 (0,200)→(100,200)
  #expect(gradient.start == CGPoint(x: 0, y: 200))
  #expect(gradient.end == CGPoint(x: 100, y: 200))
}

@Test func shadingPatternHonorsPatternMatrix() {
  // /Matrix 평행이동 50 — 그라디언트 좌표가 따라 이동
  let pattern =
    "<< /Type /Pattern /PatternType 2 /Matrix [1 0 0 1 50 0] "
    + "/Shading \(axialShading(coords: "0 0 100 0")) >>"
  let (nodes, _) = parseFixture(
    content: "/Pattern cs /P1 scn 0 0 200 200 re f",
    resources: "<< /Pattern << /P1 5 0 R >> >>",
    extraObjects: [pattern])
  guard case .path(let pathNode) = nodes[0],
    case .linearGradient(let gradient) = pathNode.style.fill
  else {
    Issue.record("그라디언트가 아님")
    return
  }
  // (0,0)+50 → 모델 (50,200), (100,0)+50 → (150,200)
  #expect(gradient.start == CGPoint(x: 50, y: 200))
  #expect(gradient.end == CGPoint(x: 150, y: 200))
}

@Test func tilingPatternIsReportedAndFillSkipped() {
  // PatternType 1(tiling) → 미지원, fill 없음(패스만)
  let tiling =
    "<< /Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 "
    + "/BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >> /Length 0 >> stream\n\nendstream"
  let (nodes, report) = parseFixture(
    content: "/Pattern cs /P1 scn 10 10 80 80 re f",
    resources: "<< /Pattern << /P1 5 0 R >> >>",
    extraObjects: [tiling])
  #expect(report.issues.contains { $0.kind == .unsupportedShading })
  guard case .path(let pathNode) = nodes[0] else {
    Issue.record("패스가 아님")
    return
  }
  #expect(pathNode.style.fill == nil)  // 채움 스킵, 도형은 보존
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (패턴 fill 미구현)

- [ ] **Step 3: 구현** — `ContentStreamParser` 수정

`GraphicsState`에 패턴 이름 필드 추가:

```swift
    var fillAlpha: Double = 1
    /// scn으로 지정된 fill 패턴 이름 (Pattern 색공간일 때).
    var fillPattern: String?
    /// 누적 클립 (모델 좌표, winding 정규화 완료).
    var clip: BezierPath?
```

`setColorComponents`의 패턴 분기를 교체 — 리포트 대신 패턴 이름을 상태에 기록:

```swift
  private func setColorComponents(_ scanner: CGPDFScannerRef, isStroke: Bool) {
    let space = isStroke ? state.strokeColorSpace : state.fillColorSpace
    if space == .pattern {
      // scn /P1 — 패턴 이름 기록 (해석은 페인팅 시점). stroke 패턴은 비목표.
      if let name = Self.popName(scanner), !isStroke {
        state.fillPattern = name
      }
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
```

비패턴 색공간으로 전환 시 fillPattern을 비운다 — `setColorSpace`의 fill 분기(else)를 교체:

```swift
    if isStroke {
      state.strokeColorSpace = space
    } else {
      state.fillColorSpace = space
      if space != .pattern { state.fillPattern = nil }
    }
```

직접 색 지정(g/rg/k 등)도 패턴을 무효화해야 한다 — `setColor`의 fill 분기(else) 안에 `state.fillPattern = nil` 한 줄 추가 (이 분기는 이미 isStroke=false 컨텍스트):

```swift
    if isStroke {
      state.strokeColorSpace = space
      state.strokeColor = color
    } else {
      state.fillColorSpace = space
      state.fillColor = color
      state.fillPattern = nil
    }
```

`paint(fill:stroke:close:evenOdd:)`의 fill 스타일 결정부를 패턴 우선으로 교체:

```swift
    var style = Style(opacity: state.fillAlpha)
    if fill {
      if let patternName = state.fillPattern {
        style.fill = resolveShadingPatternFill(patternName)  // nil이면 채움 없음
      } else {
        style.fill = .color(state.fillColor)
      }
    }
```

핸들러 추가 (셰이딩 섹션):

```swift
  /// fill 패턴 이름 → 그라디언트 Paint. PatternType 2(shading)만 지원하며
  /// tiling(type 1)·해석 실패는 리포트 후 nil (채움 스킵).
  private func resolveShadingPatternFill(_ name: String) -> Paint? {
    guard let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "Pattern", name),
      let dictionary = CGPDFReading.dictionary(from: object)
    else {
      report.add(.unsupportedShading, detail: "패턴 리소스를 찾지 못함")
      return nil
    }
    guard CGPDFReading.integer(dictionary, "PatternType") == 2 else {
      report.add(.unsupportedShading, detail: "타일링 패턴 (반복 콘텐츠 — 미지원)")
      return nil
    }
    guard let shadingObject = CGPDFReading.object(dictionary, "Shading"),
      let parsed = PDFShading.parse(shadingObject)
    else {
      report.add(.unsupportedShading, detail: "패턴 셰이딩 변환 실패")
      return nil
    }
    if parsed.lossyRadial {
      report.add(.unsupportedShading, detail: "원형 패턴 근사 — 끝 원만 반영")
    }
    // 패턴 좌표 = pattern /Matrix × pageFlip (CTM 미적용 — 결정 기록).
    let patternMatrix = Self.matrix(from: dictionary, key: "Matrix") ?? .identity
    let toModel = patternMatrix.concatenating(pageFlip)
    let gradient = parsed.gradient.applying(toModel)
    return parsed.isRadial ? .radialGradient(gradient) : .linearGradient(gradient)
  }
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (303개 = 300 + 3)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 패턴 셰이딩 채움 — scn 패턴을 패스 그라디언트 fill로"
```

---

### Task 5: 통합 회귀 + README + 이슈 코멘트 + PR

- [ ] **Step 1: 전체 회귀**

```bash
cd VectaEngine && swift build && swift test   # 303 PASS
cd ../VectaApp && xcodegen generate && \
xcodebuild -project Vecta.xcodeproj -scheme Vecta -configuration Debug \
  -derivedDataPath build build                # BUILD SUCCEEDED
```

스모크: `open VectaApp/build/Build/Products/Debug/Vecta.app` → 3s → `pgrep -x Vecta` → `pkill -x Vecta`.

- [ ] **Step 2: 수동 검증 체크리스트** (사용자 수행)

1. 외부 도구(Illustrator/Inkscape)가 선형 그라디언트로 채운 PDF 열기 → 그라디언트 표시
2. 원형 그라디언트 PDF 열기 → 원형 그라디언트 표시 (두 원이면 끝 원 근사 + 배너 경고)
3. sh 직접 셰이딩 PDF (배경 그라디언트) → 클립 영역 채움
4. 메시 그라디언트(type 4–7) PDF → "N개 객체를 가져오지 못했습니다" 배너
5. 가져온 그라디언트 문서를 .ai로 저장 → 재열기 100% 라운드트립 (JSON 임베드)
6. 기존 M3·M4a 문서 회귀 (그라디언트 편집·패스 임포트 무영향)

- [ ] **Step 3: README 갱신** — M4b 줄 추가/세분화. 기존 `- [ ] M4b 외부 .ai 임포트: 그라디언트·이미지·텍스트` 줄을 다음으로 교체:

```markdown
- [x] M4b-1 외부 .ai 임포트: 그라디언트 (sh·shading 패턴)
- [ ] M4b-2 외부 .ai 임포트: 이미지
- [ ] M4b-3 외부 .ai 임포트: 텍스트
```

(실제 README 형식에 맞춘다.)

- [ ] **Step 4: 이슈 코멘트 + PR** — base 결정: PR #12(M4a)가 머지됐으면 `main`(또는 그 직후 머지될 브랜치), 아니면 `m4a-import-core`(스택). `gh pr view 12 --json state`로 확인.

```bash
gh issue comment 11 --body "M4b-1 구현 노트:
- Function type 2/3만 지원 (0 샘플·4 포스트스크립트는 리포트)
- Shading type 2/3만 (1·4–7 mesh는 리포트)
- radial 두 원은 M3 단일원 모델로 끝 원 근사 — 손실 시 배너 리포트
- function 9등분 균등 샘플 → 9 GradientStop
- 후속(이미지 #13, 텍스트 #14)에서 ContentStreamParser 800줄 근접 시 operator 등록 extension 분리 검토"

git push -u origin m4b1-gradient-import
gh pr create --base <위에서 결정> --title "feat: M4b-1 외부 .ai 임포트 — 그라디언트" \
  --body "$(cat <<'EOF'
## Summary
- 엔진: PDF Function 평가(type 2 지수·3 스티칭), PDF Shading 파싱(axial·radial → Gradient), sh 연산자(클립/mediaBox 패스 그라디언트 fill), 패턴 셰이딩 채움(scn /P1), 좌표 모델 베이크
- radial 두 원 → M3 단일원 근사(끝 원), 손실 리포트. mesh·function type 0/4·tiling은 미지원 리포트
- 렌더러 무변경 — M3 그라디언트 렌더가 그대로 그림. SceneRenderer·앱 변경 없음

## Test Plan
- [x] 엔진 swift test 전체 통과 (베이스 279 + 신규 24 = 303)
- [x] xcodebuild BUILD SUCCEEDED + 스모크
- [ ] 수동 체크리스트 6항목 (plan Task 5 Step 2)

Closes #11

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 완료 기준 (M4b-1 Definition of Done)

- 엔진 테스트 전체 그린 (베이스 279 + 신규 ~24)
- 외부 PDF의 선형·원형 그라디언트(sh·패턴 둘 다)가 그라디언트 fill로 임포트됨
- 미지원(mesh·function type 0/4·tiling·radial 근사)은 배너로 보고 — 조용한 데이터 손실 없음
- 좌표가 모델 좌표로 정확히 베이크 (sh 클립/mediaBox, 패턴 matrix)
- 기존 M3·M4a 회귀 0
- PR이 이슈 #11을 닫음

## M4b-2 예고 (이슈 #13)

이미지 XObject 디코드 → CGImage → PNG 정규화 → ImageNode, SceneRenderer 이미지 렌더링. 이 그라디언트 PR과 독립 — 같은 파서 코어 위에 image XObject 분기만 추가.

## Self-Review 메모

- 스펙 §5 그라디언트 행("sh, 패턴 컬러스페이스의 shading 패턴 type 2/3 → linear/radialGradient") 전부 커버.
- radial 근사·extend 미반영은 모델 한계로 결정 기록에 명시. M3 Gradient 모델을 바꾸지 않는다 (M3 인스펙터·렌더·라운드트립 호환 유지).
- 좌표 베이크: sh는 CTM×pageFlip, 패턴은 patternMatrix×pageFlip — 테스트가 두 경로의 정확한 모델 좌표를 고정.
