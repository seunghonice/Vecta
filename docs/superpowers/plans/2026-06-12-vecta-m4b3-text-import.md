# Vecta M4b-3 — 외부 .ai 임포트: 텍스트 (텍스트 연산자 → TextNode) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 외부 PDF의 텍스트 표시 연산자(BT~ET)를 파싱해 `TextNode`로 임포트하고, SceneRenderer에 CoreText 텍스트 렌더링을 추가해 가져온 텍스트가 캔버스·PDF 출력에 보이게 한다. 인코딩(표준 + ToUnicode)으로 바이트를 문자열로 디코드하고, 미지원(CID 폰트, Differences, 수직 쓰기)은 ImportReport로 수집한다. (GitHub 이슈 #14, PR은 `Closes #14`. M4b 마지막 도메인)

**Architecture:** ToUnicode CMap 파서(`ToUnicodeCMap`: 순수 텍스트 파싱)와 폰트 디코더(`PDFFontDecoder`: 폰트 dict → 바이트→문자열 함수)를 ImportAI에 두고 헤드리스 테스트한다. 텍스트 상태 머신(text/line matrix, font)과 연산자 핸들러는 `ContentStreamParser+Text.swift` extension으로 분리해 본체 800줄 캡을 지킨다. `SceneRenderer`가 `TextNode`를 CoreText로 그리면 AIFileWriter(공유)가 PDF 출력에도 텍스트를 넣고, 텍스트 bounds·HitTesting을 CTLine 측정으로 정밀화한다(스펙 §11의 "M5 정밀 바운드"를 여기서 달성).

**Tech Stack:** Swift 6 (언어 모드 v5), Swift Testing, CoreGraphics(CGPDFScanner/CGPDFString), CoreText(CTFont/CTLine), XcodeGen. 엔진 플랫폼 .v14.

**참조:** 스펙 `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` §4(TextNode)·§5(ImportAI 텍스트 인코딩)·§6(ExportAI 텍스트 CoreText)·§11·§12-M4, 이슈 #14, M4b-1/M4b-2 계획(파서 컨벤션·좌표 베이크·결정 기록), PDF 32000-1 §9(Text).

---

## 커밋 규칙 (전역 규칙 — 기존과 동일)

매 커밋 전: ① `cd VectaEngine && swift build`(앱 변경 시 xcodebuild 추가) → ② `swift test` → ③ `swift format --in-place --recursive Sources Tests`(앱은 `VectaApp/Sources`) → ④ commit. 한국어 메시지+접두사, Co-Authored-By 금지. 테스트 실패 시 수정 후 ①부터 재수행.

## 결정 기록 (이 계획에서 확정)

| 결정 | 근거 |
|---|---|
| 바이트→문자열: `/ToUnicode` 있으면 CMap 우선; 없으면 표준 인코딩 | 스펙 §5. ToUnicode가 가장 정확. 없으면 인코딩 근사 |
| 표준 인코딩은 시스템 인코딩으로 근사: WinAnsi→`.windowsCP1252`, MacRoman→`.macOSRoman`, Standard→`.isoLatin1` | 256-글리프 Adobe 테이블 직접 내장 회피. `String(bytes:encoding:)` 활용 — 충분히 근사 |
| `/Encoding`의 `/Differences`는 best-effort 무시 + 리포트 | Adobe 글리프명→유니코드 매핑(AGL)은 방대 — 비목표. Differences는 드묾 |
| CID/Type0 복합 폰트: ToUnicode 있으면 처리(2바이트 코드), 없으면 리포트 | CIDToGIDMap·CMap 인코딩 직접 파싱은 비목표. ToUnicode가 대부분 동반됨 |
| 코드 바이트 폭: Type0=2바이트, 그 외 simple 폰트=1바이트 | codespacerange 정밀 파싱 대신 Subtype로 근사 |
| 각 텍스트 표시 연산(Tj/TJ/'/")이 하나의 TextNode | position=그 시점 text matrix 원점(모델 좌표), string=디코드 결과. 한 줄 여러 Tj는 여러 노드 |
| TJ 배열의 글리프 조정값(숫자)은 무시, 문자열만 연결 | 자간 미세조정은 시각 근사 — 위치 정밀도 손실 허용 |
| Tj 간 advance는 CoreText로 측정해 text matrix 이동 | 같은 줄 연속 Tj가 이어지도록. 렌더와 동일 폰트 경로 재사용 |
| fontName = 폰트의 `/BaseFont`(없으면 리소스 이름) 보존; 렌더는 시스템 폰트 매칭, 없으면 폴백 | 스펙 §4 "fontName 원본 보존". 폰트 미설치 시 폴백 렌더 |
| 텍스트 위치 베이크: textMatrix × CTM × pageFlip (노드 transform에) | 텍스트는 변환된 baseline에 그려진다. 다른 임포트 노드(이미지)처럼 transform 사용 |
| 회전·기울임 텍스트는 정립으로 근사 + 리포트 (transform=identity) | 회전을 transform에 넣으면 pageFlip y-flip이 섞여 렌더 이중 플립. 완전 회전 지원은 M5+ |
| 텍스트 fill은 단색만 (`state.fillColor`) | 텍스트 그라디언트/패턴 채움은 드물고 모델 표현 복잡 — 단색 근사. SceneRenderer도 `.color`만 그림 |
| 텍스트 bounds·HitTesting: CTLine 측정으로 정밀화 (스펙 §11 "M5"를 여기서) | 렌더와 동일 경로. 텍스트가 보이면 선택/마퀴도 동작해야 |
| 수직 쓰기(WMode 1)·텍스트 렌더 모드(Tr 3 invisible·clip 등) 비목표 + 리포트 | MVP 범위. 가로 쓰기·채움만 |
| 텍스트 연산자 핸들러는 `ContentStreamParser+Text.swift` extension으로 분리 | 본체 728줄 + 텍스트 핸들러 → 800 초과 방지. Tidy First |

## 파일 구조 (M4b-3 추가/변경분)

```
VectaEngine/Sources/VectaEngine/
├── ImportAI/
│   ├── ToUnicodeCMap.swift            (생성)  # CMap 텍스트 → 바이트 매핑 (Task 1)
│   ├── PDFFontDecoder.swift           (생성)  # 폰트 dict → 바이트→문자열 (Task 2)
│   ├── ContentStreamParser.swift      (수정)  # textState 필드·텍스트 연산자 등록 (Task 3)
│   └── ContentStreamParser+Text.swift (생성)  # 텍스트 상태 머신·핸들러 (Task 3)
├── Rendering/
│   ├── SceneRenderer.swift            (수정)  # TextNode 렌더 (Task 4)
│   └── TextRendering.swift            (생성)  # CTLine 생성·측정 공용 (Task 4)
└── Geometry/
    ├── BezierPath+Bounds.swift        (수정)  # text bounds CTLine 측정 (Task 4)
    └── HitTesting.swift               (수정)  # text 히트테스트 (Task 4)

VectaEngine/Tests/VectaEngineTests/
├── ToUnicodeCMapTests.swift               (생성)  # Task 1
├── PDFFontDecoderTests.swift              (생성)  # Task 2
├── ContentStreamParserTextTests.swift     (생성)  # Task 3
└── SceneRendererTextTests.swift           (생성)  # Task 4
```

핵심 계약 (기존 — 신규 코드가 의존):
- `SceneRenderer`는 캔버스와 PDF 익스포트가 공유 — 텍스트 렌더만 넣으면 .ai 출력에도 반영된다.
- `TextNode { id, string, fontName, fontSize: Double, fill: Paint, position: CGPoint, transform: Transform2D }` (M1 모델, Codable).
- `ContentStreamParser`: CTM·pageFlip 좌표 베이크. `state.ctm`/`pageFlip`/`appendNode(_:explicitClip:)`/`contentStreamStack`. BT 콜백은 현재 `reportTextOnce`만 — 교체.
- `CGPDFReading`(M4b-1·2): dictionary/integer/name/object/stream/boolean 헬퍼.
- 테스트 베이스라인: 엔진 327개 그린. 브랜치 `m4b3-text-import` (base: `main` — M4b-2까지 머지됨).
- 픽스처: `makeTestPDF`(M4a). 폰트/ToUnicode는 `extraObjects`에 dict/stream String으로 주입.

---

### Task 1: ToUnicodeCMap — CMap 텍스트 파서

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/ToUnicodeCMap.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ToUnicodeCMapTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import Testing

@testable import VectaEngine

private let sampleCMap = """
/CIDInit /ProcSet findresource begin
12 dict begin begincmap
/CMapName /Adobe-Identity-UCS def
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
2 beginbfchar
<0041> <0041>
<0042> <00E9>
endbfchar
1 beginbfrange
<0061> <0063> <0061>
endbfrange
endcmap
"""

@Test func parsesBfcharSingleMappings() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  #expect(cmap.string(forCode: 0x41) == "A")
  #expect(cmap.string(forCode: 0x42) == "é")  // 0x00E9
}

@Test func parsesBfrangeMappings() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  #expect(cmap.string(forCode: 0x61) == "a")
  #expect(cmap.string(forCode: 0x62) == "b")
  #expect(cmap.string(forCode: 0x63) == "c")
}

@Test func unmappedCodeReturnsNil() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  #expect(cmap.string(forCode: 0x99) == nil)
}

@Test func decodesByteSequenceWithCodeWidth() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  // 1바이트 코드: 0x41 0x42 0x61 → "Aéa"
  #expect(cmap.decode([0x41, 0x42, 0x61], codeBytes: 1) == "Aéa")
}

@Test func twoByteCodeDecodes() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  // 2바이트 코드: 0x00 0x41 → "A"
  #expect(cmap.decode([0x00, 0x41], codeBytes: 2) == "A")
}

@Test func bfrangeWithArrayDestinations() {
  let arrayCMap = """
  1 beginbfrange
  <0080> <0082> [<0041> <0042> <0043>]
  endbfrange
  endcmap
  """
  let cmap = ToUnicodeCMap.parse(arrayCMap)
  #expect(cmap.string(forCode: 0x80) == "A")
  #expect(cmap.string(forCode: 0x81) == "B")
  #expect(cmap.string(forCode: 0x82) == "C")
}

@Test func multiCharDestination() {
  // dst가 여러 UTF-16 코드유닛 (예: ﬁ ligature → "fi")
  let ligCMap = """
  1 beginbfchar
  <0001> <00660069>
  endbfchar
  endcmap
  """
  let cmap = ToUnicodeCMap.parse(ligCMap)
  #expect(cmap.string(forCode: 0x01) == "fi")
}
```

- [ ] **Step 2: 실패 확인** — `cd VectaEngine && swift test` → FAIL (`ToUnicodeCMap` 없음)

- [ ] **Step 3: 구현** — `ImportAI/ToUnicodeCMap.swift`

```swift
import Foundation

/// PDF /ToUnicode CMap (스펙 §5) — 폰트 코드 바이트 → 유니코드 문자열.
/// beginbfchar/beginbfrange 블록만 파싱한다(codespacerange는 코드 폭 추정에
/// 쓰지 않고 폰트 Subtype으로 결정 — 결정 기록).
struct ToUnicodeCMap: Equatable {
  private var singles: [UInt32: String] = [:]
  private var ranges: [(lo: UInt32, hi: UInt32, destinations: [String])] = []

  static func == (lhs: ToUnicodeCMap, rhs: ToUnicodeCMap) -> Bool {
    lhs.singles == rhs.singles
      && lhs.ranges.count == rhs.ranges.count
      && zip(lhs.ranges, rhs.ranges).allSatisfy {
        $0.lo == $1.lo && $0.hi == $1.hi && $0.destinations == $1.destinations
      }
  }

  /// 코드 → 문자열 (없으면 nil).
  func string(forCode code: UInt32) -> String? {
    if let single = singles[code] { return single }
    for range in ranges where code >= range.lo && code <= range.hi {
      let offset = Int(code - range.lo)
      if range.destinations.count == 1 {
        // 단일 시작 dst + 오프셋 (스칼라 증가)
        guard let base = range.destinations.first?.unicodeScalars.first else { return nil }
        return Unicode.Scalar(base.value + UInt32(offset)).map(String.init)
      }
      guard offset < range.destinations.count else { return nil }
      return range.destinations[offset]
    }
    return nil
  }

  /// 바이트 시퀀스를 codeBytes 폭 코드로 끊어 문자열로 디코드.
  /// 매핑 없는 코드는 건너뛴다(또는 대체문자 — 여기선 건너뜀).
  func decode(_ bytes: [UInt8], codeBytes: Int) -> String {
    var result = ""
    var index = 0
    while index + codeBytes <= bytes.count {
      var code: UInt32 = 0
      for offset in 0..<codeBytes {
        code = (code << 8) | UInt32(bytes[index + offset])
      }
      if let mapped = string(forCode: code) { result += mapped }
      index += codeBytes
    }
    return result
  }

  /// CMap 텍스트를 파싱한다.
  static func parse(_ text: String) -> ToUnicodeCMap {
    var cmap = ToUnicodeCMap()
    let tokens = tokenize(text)
    var index = 0
    while index < tokens.count {
      switch tokens[index] {
      case "beginbfchar":
        index += 1
        while index < tokens.count, tokens[index] != "endbfchar" {
          if let src = hexValue(tokens[index]),
            index + 1 < tokens.count, let dst = hexString(tokens[index + 1])
          {
            cmap.singles[src] = dst
            index += 2
          } else {
            index += 1
          }
        }
      case "beginbfrange":
        index += 1
        while index < tokens.count, tokens[index] != "endbfrange" {
          guard let lo = hexValue(tokens[index]), index + 2 < tokens.count,
            let hi = hexValue(tokens[index + 1])
          else {
            index += 1
            continue
          }
          let third = tokens[index + 2]
          if third == "[" {
            // 배열형: [<dst0> <dst1> ...]
            var destinations: [String] = []
            var cursor = index + 3
            while cursor < tokens.count, tokens[cursor] != "]" {
              if let dst = hexString(tokens[cursor]) { destinations.append(dst) }
              cursor += 1
            }
            cmap.ranges.append((lo, hi, destinations))
            index = cursor + 1
          } else if let dst = hexString(third) {
            cmap.ranges.append((lo, hi, [dst]))
            index += 3
          } else {
            index += 1
          }
        }
      default:
        index += 1
      }
    }
    return cmap
  }

  // MARK: - 토큰화

  /// `<hex>` · `[` · `]` · 키워드를 토큰으로 분리.
  private static func tokenize(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      switch character {
      case "<":
        flush(&current, into: &tokens)
        var hex = "<"
        index = text.index(after: index)
        while index < text.endIndex, text[index] != ">" {
          hex.append(text[index])
          index = text.index(after: index)
        }
        hex.append(">")
        tokens.append(hex)
      case "[", "]":
        flush(&current, into: &tokens)
        tokens.append(String(character))
      case " ", "\n", "\r", "\t":
        flush(&current, into: &tokens)
      default:
        current.append(character)
      }
      if index < text.endIndex { index = text.index(after: index) }
    }
    flush(&current, into: &tokens)
    return tokens
  }

  private static func flush(_ current: inout String, into tokens: inout [String]) {
    if !current.isEmpty {
      tokens.append(current)
      current = ""
    }
  }

  /// `<0041>` → 0x41 (UInt32).
  private static func hexValue(_ token: String) -> UInt32? {
    guard token.hasPrefix("<"), token.hasSuffix(">") else { return nil }
    let hex = token.dropFirst().dropLast()
    return UInt32(hex, radix: 16)
  }

  /// `<0041>` → "A", `<00660069>` → "fi" (UTF-16BE 코드유닛 시퀀스).
  private static func hexString(_ token: String) -> String? {
    guard token.hasPrefix("<"), token.hasSuffix(">") else { return nil }
    let hex = token.dropFirst().dropLast()
    guard hex.count % 4 == 0 else {
      // 4자리(2바이트=UTF16 1유닛) 배수가 아니면 단일 스칼라로 시도
      guard let value = UInt32(hex, radix: 16),
        let scalar = Unicode.Scalar(value)
      else { return nil }
      return String(scalar)
    }
    var units: [UInt16] = []
    var cursor = hex.startIndex
    while cursor < hex.endIndex {
      let next = hex.index(cursor, offsetBy: 4)
      guard let unit = UInt16(hex[cursor..<next], radix: 16) else { return nil }
      units.append(unit)
      cursor = next
    }
    return String(decoding: units, as: UTF16.self)
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (334개 = 327 + 7)

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: ToUnicode CMap 파서 — bfchar·bfrange 바이트 매핑"
```

---

### Task 2: PDFFontDecoder — 폰트 dict → 바이트→문자열

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/PDFFontDecoder.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PDFFontDecoderTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성** — 픽스처 폰트 dict를 꺼내 디코더를 만든다.

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 픽스처 PDF의 /Resources/Font/<name> dict로 PDFFont를 만든다.
private func fontFromResource(
  name: String, fontObject: String, extraObjects: [String] = []
) -> (font: PDFFont?, unsupported: String?) {
  let data = makeTestPDF(
    content: "BT /\(name) 12 Tf (X) Tj ET",
    resources: "<< /Font << /\(name) 5 0 R >> >>",
    extraObjects: [fontObject] + extraObjects)
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  guard let object = CGPDFContentStreamGetResource(stream, "Font", name),
    let dictionary = CGPDFReading.dictionary(from: object)
  else {
    Issue.record("폰트 리소스를 못 꺼냄")
    return (nil, nil)
  }
  return PDFFontDecoder.font(from: dictionary)
}

@Test func type1WinAnsiDecodesLatin() {
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
    + "/Encoding /WinAnsiEncoding >>"
  let (pdfFont, unsupported) = fontFromResource(name: "F0", fontObject: font)
  #expect(unsupported == nil)
  #expect(pdfFont?.baseFont == "Helvetica")
  // WinAnsi: 0x41='A', 0xE9='é'(CP1252)
  #expect(pdfFont?.decode([0x41, 0x42, 0x43]) == "ABC")
  #expect(pdfFont?.decode([0xE9]) == "é")
}

@Test func toUnicodeWinsOverEncoding() {
  let cmap = """
  1 beginbfchar
  <0041> <0042>
  endbfchar
  endcmap
  """
  let cmapStream =
    "<< /Length \(cmap.utf8.count) >> stream\n\(cmap)\nendstream"
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
    + "/Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>"
  let (pdfFont, _) = fontFromResource(
    name: "F0", fontObject: font, extraObjects: [cmapStream])
  // ToUnicode 우선: 0x41 → 'B'(0x42)
  #expect(pdfFont?.decode([0x41]) == "B")
}

@Test func type0WithoutToUnicodeReports() {
  let font =
    "<< /Type /Font /Subtype /Type0 /BaseFont /SomeCID-Identity-H "
    + "/Encoding /Identity-H >>"
  let (pdfFont, unsupported) = fontFromResource(name: "F0", fontObject: font)
  #expect(pdfFont == nil)
  #expect(unsupported != nil)
}

@Test func type0WithToUnicodeUsesTwoByteCodes() {
  let cmap = """
  1 beginbfchar
  <0041> <0058>
  endbfchar
  endcmap
  """
  let cmapStream = "<< /Length \(cmap.utf8.count) >> stream\n\(cmap)\nendstream"
  let font =
    "<< /Type /Font /Subtype /Type0 /BaseFont /CID-Identity "
    + "/Encoding /Identity-H /ToUnicode 6 0 R >>"
  let (pdfFont, _) = fontFromResource(
    name: "F0", fontObject: font, extraObjects: [cmapStream])
  #expect(pdfFont?.codeBytes == 2)
  // 2바이트 코드 0x0041 → 'X'(0x58)
  #expect(pdfFont?.decode([0x00, 0x41]) == "X")
}

@Test func differencesEncodingReports() {
  let font =
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
    + "/Encoding << /BaseEncoding /WinAnsiEncoding "
    + "/Differences [65 /bullet] >> >>"
  let (pdfFont, unsupported) = fontFromResource(name: "F0", fontObject: font)
  // Differences는 무시하되 리포트 — 폰트는 BaseEncoding으로 동작
  #expect(pdfFont != nil)
  #expect(unsupported != nil)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`PDFFont`/`PDFFontDecoder` 없음)

- [ ] **Step 3: 구현** — `ImportAI/PDFFontDecoder.swift`

```swift
import CoreGraphics
import Foundation

/// 폰트의 바이트 코드 → 문자열 디코더 (스펙 §5).
struct PDFFont {
  /// 코드 바이트 폭 (Type0=2, simple=1).
  let codeBytes: Int
  /// /ToUnicode (있으면 우선).
  let toUnicode: ToUnicodeCMap?
  /// 표준 인코딩 폴백 (ToUnicode 없을 때).
  let stringEncoding: String.Encoding
  /// 원본 폰트명 (/BaseFont).
  let baseFont: String

  /// 바이트 → 문자열. ToUnicode 우선, 없으면 표준 인코딩.
  func decode(_ bytes: [UInt8]) -> String {
    if let toUnicode {
      return toUnicode.decode(bytes, codeBytes: codeBytes)
    }
    return String(bytes: bytes, encoding: stringEncoding) ?? ""
  }
}

/// 폰트 dict → PDFFont (스펙 §5). Type0는 ToUnicode 필수, 미지원 사유 반환.
enum PDFFontDecoder {
  static func font(
    from dictionary: CGPDFDictionaryRef
  ) -> (font: PDFFont?, unsupported: String?) {
    let subtype = CGPDFReading.name(dictionary, "Subtype") ?? ""
    let baseFont = CGPDFReading.name(dictionary, "BaseFont") ?? "Unknown"
    let isType0 = subtype == "Type0"
    let codeBytes = isType0 ? 2 : 1

    var unsupported: String?
    let toUnicode = toUnicodeCMap(from: dictionary)

    // Type0(복합)는 ToUnicode 없으면 디코드 불가.
    if isType0, toUnicode == nil {
      return (nil, "복합 폰트 \(baseFont) (ToUnicode 없음 — 미지원)")
    }

    // 인코딩: name 또는 dict(Differences 동반).
    let encoding = stringEncoding(from: dictionary, reportDifferences: &unsupported)

    let font = PDFFont(
      codeBytes: codeBytes, toUnicode: toUnicode,
      stringEncoding: encoding, baseFont: baseFont)
    return (font, unsupported)
  }

  private static func toUnicodeCMap(from dictionary: CGPDFDictionaryRef) -> ToUnicodeCMap? {
    guard let object = CGPDFReading.object(dictionary, "ToUnicode"),
      let stream = CGPDFReading.stream(from: object),
      let data = CGPDFStreamCopyData(stream, nil) as Data?,
      let text = String(data: data, encoding: .ascii) ?? String(data: data, encoding: .utf8)
    else { return nil }
    return ToUnicodeCMap.parse(text)
  }

  /// /Encoding name 또는 dict의 BaseEncoding → String.Encoding.
  /// Differences가 있으면 리포트(무시).
  private static func stringEncoding(
    from dictionary: CGPDFDictionaryRef, reportDifferences: inout String?
  ) -> String.Encoding {
    // name 형태
    if let name = CGPDFReading.name(dictionary, "Encoding") {
      return mapEncodingName(name)
    }
    // dict 형태 (BaseEncoding + Differences)
    if let encodingObject = CGPDFReading.object(dictionary, "Encoding"),
      let encodingDict = CGPDFReading.dictionary(from: encodingObject)
    {
      if CGPDFReading.object(encodingDict, "Differences") != nil {
        reportDifferences = "폰트 Differences 인코딩 (무시 — 기본 인코딩 사용)"
      }
      if let base = CGPDFReading.name(encodingDict, "BaseEncoding") {
        return mapEncodingName(base)
      }
    }
    return .windowsCP1252  // 기본
  }

  private static func mapEncodingName(_ name: String) -> String.Encoding {
    switch name {
    case "WinAnsiEncoding": return .windowsCP1252
    case "MacRomanEncoding": return .macOSRoman
    case "StandardEncoding", "PDFDocEncoding": return .isoLatin1
    default: return .windowsCP1252
    }
  }
}
```

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (339개 = 334 + 5). 인코딩 근사로 픽셀/문자 기대가 다르면(예: MacRoman é) 실제 디코드를 확인해 고정하되, ToUnicode 우선·Type0 리포트 계약은 유지.

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF 폰트 디코더 — ToUnicode·표준 인코딩 바이트→문자열"
```

---

### Task 3: 텍스트 상태 머신 + ContentStreamParser 텍스트 연산자 → TextNode

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser+Text.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserTextTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private let helveticaFont =
  "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"

private func parseText(
  content: String, mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200)
) -> (nodes: [Node], report: ImportReport) {
  parseFixture(
    content: content, mediaBox: mediaBox,
    resources: "<< /Font << /F0 5 0 R >> >>",
    extraObjects: [helveticaFont])
}

@Test func simpleTextBecomesTextNode() {
  let (nodes, report) = parseText(content: "BT /F0 24 Tf 50 100 Td (Hello) Tj ET")
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  #expect(textNode.string == "Hello")
  #expect(textNode.fontName == "Helvetica")
  #expect(textNode.fontSize == 24)
  // Td 50 100 → text 원점 PDF (50,100) → 모델 y 100 (mediaBox 200)
  #expect(abs(textNode.position.x - 50) < 0.0001)
  #expect(abs(textNode.position.y - 100) < 0.0001)
}

@Test func textMatrixSetsPosition() {
  let (nodes, _) = parseText(content: "BT /F0 12 Tf 1 0 0 1 30 40 Tm (Tm) Tj ET")
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  // Tm 원점 PDF (30,40) → 모델 (30, 160)
  #expect(abs(textNode.position.x - 30) < 0.0001)
  #expect(abs(textNode.position.y - 160) < 0.0001)
}

@Test func textFillColorCaptured() {
  let (nodes, _) = parseText(content: "BT 1 0 0 rg /F0 12 Tf 0 0 Td (Red) Tj ET")
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  #expect(textNode.fill == .color(RGBA(red: 1, green: 0, blue: 0)))
}

@Test func multipleTjProduceMultipleNodes() {
  let (nodes, _) = parseText(
    content: "BT /F0 12 Tf 0 100 Td (A) Tj 0 -20 Td (B) Tj ET")
  let textNodes = nodes.compactMap { node -> TextNode? in
    if case .text(let t) = node { return t }
    return nil
  }
  #expect(textNodes.count == 2)
  #expect(textNodes[0].string == "A")
  #expect(textNodes[1].string == "B")
  // T* 류 줄바꿈으로 둘째가 아래
  #expect(textNodes[1].position.y > textNodes[0].position.y)
}

@Test func tjArrayConcatenatesStrings() {
  let (nodes, _) = parseText(content: "BT /F0 12 Tf 0 0 Td [(Hel) -100 (lo)] TJ ET")
  guard case .text(let textNode) = nodes[0] else {
    Issue.record("텍스트 노드가 아님")
    return
  }
  #expect(textNode.string == "Hello")
}

@Test func missingFontReportsAndSkips() {
  // Tf로 없는 폰트 참조 → 리포트, 텍스트 노드 없음
  let (nodes, report) = parseFixture(
    content: "BT /Missing 12 Tf 0 0 Td (X) Tj ET",
    resources: "<< /Font << >> >>")
  #expect(nodes.isEmpty)
  #expect(report.issues.contains { $0.kind == .unsupportedText })
}

@Test func textRespectsClip() {
  let (nodes, _) = parseText(
    content: "10 10 50 50 re W n BT /F0 12 Tf 0 0 Td (Clip) Tj ET")
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0], case .text = group.children.first else {
    Issue.record("클립 그룹 안에 텍스트가 아님")
    return
  }
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (텍스트가 아직 리포트만)

- [ ] **Step 3: ContentStreamParser 텍스트 상태 필드·연산자 등록** — `ContentStreamParser.swift`

상태 필드 추가 (`didReportText` 근처):

```swift
  /// BT~ET 사이의 텍스트 상태 (밖에서는 nil).
  fileprivate var textState: TextState?
```

`registerOperators`의 `BT` 콜백을 교체하고 텍스트 연산자 추가:

```swift
    CGPDFOperatorTableSetCallback(table, "BT") { _, info in parserFrom(info).beginText() }
    CGPDFOperatorTableSetCallback(table, "ET") { _, info in parserFrom(info).endText() }
    CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
      parserFrom(info).setFont(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
      parserFrom(info).textMove(scanner, setLeading: false)
    }
    CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
      parserFrom(info).textMove(scanner, setLeading: true)
    }
    CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
      parserFrom(info).setTextMatrix(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "T*") { _, info in parserFrom(info).textNextLine() }
    CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
      parserFrom(info).setLeading(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
      parserFrom(info).showText(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
      parserFrom(info).showTextArray(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
      parserFrom(info).showTextNextLine(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
      parserFrom(info).showTextWithSpacing(scanner)
    }
```

(기존 `reportTextOnce` 메서드와 `didReportText` 필드는 텍스트가 실제 지원되므로 제거 가능 — 미사용 경고 시 삭제. BT 콜백이 reportTextOnce를 더는 안 부른다.)

`popString` 헬퍼 추가 (popNumbers/popName 근처):

```swift
  fileprivate static func popString(_ scanner: CGPDFScannerRef) -> [UInt8]? {
    var pdfString: CGPDFStringRef? = nil
    guard CGPDFScannerPopString(scanner, &pdfString), let pdfString,
      let pointer = CGPDFStringGetBytePtr(pdfString)
    else { return nil }
    let length = CGPDFStringGetLength(pdfString)
    return Array(UnsafeBufferPointer(start: pointer, count: length))
  }
```

`fillColorForText` 접근을 위해 `state.fillColor`는 이미 있음.

- [ ] **Step 4: 텍스트 상태 머신·핸들러 구현** — `ImportAI/ContentStreamParser+Text.swift`

```swift
import CoreGraphics

extension ContentStreamParser {
  /// BT~ET 텍스트 상태 (스펙 §9). 좌표는 PDF 텍스트 공간.
  struct TextState {
    var textMatrix: CGAffineTransform = .identity
    var lineMatrix: CGAffineTransform = .identity
    var font: PDFFont?
    var fontSize: CGFloat = 0
    var leading: CGFloat = 0
  }

  func beginText() {
    textState = TextState()
  }

  func endText() {
    textState = nil
  }

  func setFont(_ scanner: CGPDFScannerRef) {
    guard textState != nil else { return }
    var size: CGPDFReal = 0
    guard CGPDFScannerPopNumber(scanner, &size),
      let name = Self.popName(scanner)
    else { return }
    textState?.fontSize = CGFloat(size)
    // 폰트 리소스 조회
    guard let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "Font", name),
      let dictionary = CGPDFReading.dictionary(from: object)
    else {
      report.add(.unsupportedText, detail: "폰트 \(name)를 찾지 못함")
      textState?.font = nil
      return
    }
    let (font, unsupported) = PDFFontDecoder.font(from: dictionary)
    if let unsupported { report.add(.unsupportedText, detail: unsupported) }
    textState?.font = font
  }

  func textMove(_ scanner: CGPDFScannerRef, setLeading: Bool) {
    guard let values = Self.popNumbers(scanner, count: 2) else { return }
    if setLeading { textState?.leading = -values[1] }
    applyLineTranslation(tx: values[0], ty: values[1])
  }

  func setTextMatrix(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 6) else { return }
    let matrix = CGAffineTransform(
      a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    textState?.textMatrix = matrix
    textState?.lineMatrix = matrix
  }

  func textNextLine() {
    let leading = textState?.leading ?? 0
    applyLineTranslation(tx: 0, ty: -leading)
  }

  func setLeading(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    textState?.leading = values[0]
  }

  func showText(_ scanner: CGPDFScannerRef) {
    guard let bytes = Self.popString(scanner) else { return }
    emitText(bytes: bytes)
  }

  func showTextArray(_ scanner: CGPDFScannerRef) {
    var array: CGPDFArrayRef? = nil
    guard CGPDFScannerPopArray(scanner, &array), let array else { return }
    var bytes: [UInt8] = []
    for index in 0..<CGPDFArrayGetCount(array) {
      var element: CGPDFStringRef? = nil
      if CGPDFArrayGetString(array, index, &element), let element,
        let pointer = CGPDFStringGetBytePtr(element)
      {
        let length = CGPDFStringGetLength(element)
        bytes.append(contentsOf: UnsafeBufferPointer(start: pointer, count: length))
      }
      // 숫자(자간 조정)는 무시 (결정 기록)
    }
    emitText(bytes: bytes)
  }

  func showTextNextLine(_ scanner: CGPDFScannerRef) {
    textNextLine()
    showText(scanner)
  }

  func showTextWithSpacing(_ scanner: CGPDFScannerRef) {
    // " aw ac string — aw/ac 무시(best-effort), string만
    guard let bytes = Self.popString(scanner) else { return }
    _ = Self.popNumbers(scanner, count: 2)  // aw ac 버림
    textNextLine()
    emitText(bytes: bytes)
  }

  // MARK: - 내부

  private func applyLineTranslation(tx: CGFloat, ty: CGFloat) {
    guard var text = textState else { return }
    let translation = CGAffineTransform(translationX: tx, y: ty)
    text.lineMatrix = translation.concatenating(text.lineMatrix)
    text.textMatrix = text.lineMatrix
    textState = text
  }

  /// 디코드한 문자열로 TextNode를 만들고 text matrix를 advance한다.
  private func emitText(bytes: [UInt8]) {
    guard let text = textState, let font = text.font, !bytes.isEmpty else { return }
    let string = font.decode(bytes)
    guard !string.isEmpty else { return }
    // 텍스트 공간 → 사용자 공간 → 모델: textMatrix × CTM × pageFlip.
    let toModel = text.textMatrix.concatenating(state.ctm).concatenating(pageFlip)
    let origin = CGPoint.zero.applying(toModel)
    let node = TextNode(
      string: string, fontName: font.baseFont, fontSize: Double(text.fontSize),
      fill: .color(state.fillColor), position: origin,
      transform: .identity)
    appendNode(.text(node), explicitClip: state.clip)
    // advance: 문자열 폭(텍스트 공간)만큼 text matrix 이동 (CoreText 측정 — Task 4 공용).
    let width = TextRendering.advanceWidth(
      string: string, fontName: font.baseFont, fontSize: text.fontSize)
    textState?.textMatrix =
      CGAffineTransform(translationX: width, y: 0).concatenating(text.textMatrix)
  }
}
```

주의: `TextRendering.advanceWidth`는 Task 4에서 만든다. Task 3 단계에서 먼저 참조하므로, Task 3에서 `TextRendering`의 최소 스텁(advanceWidth만)을 함께 만들거나, advance를 fontSize × string.count 근사로 임시 구현 후 Task 4에서 교체한다. **권장: Task 3에서 advance를 `text.fontSize * CGFloat(string.count) * 0.5` 근사로 두고, Task 4에서 `TextRendering.advanceWidth`로 교체.** (multipleTjProduceMultipleNodes는 줄바꿈으로 y만 검증하므로 advance 근사로 충분.)

위 `emitText`의 advance 줄을 Task 3에서는:

```swift
    // advance 근사 (Task 4에서 CoreText 측정으로 교체)
    let width = text.fontSize * CGFloat(string.count) * 0.5
```

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (346개 = 339 + 7)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: 텍스트 연산자 임포트 — 상태 머신·TextNode·좌표 베이크"
```

---

### Task 4: SceneRenderer 텍스트 렌더(CoreText) + bounds/HitTesting 정밀화

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/Rendering/TextRendering.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Rendering/SceneRenderer.swift`
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser+Text.swift` (advance를 CoreText로 교체)
- Modify: `VectaEngine/Sources/VectaEngine/Geometry/BezierPath+Bounds.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Geometry/HitTesting.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/SceneRendererTextTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func textNode(
  _ string: String, at position: CGPoint, size: Double = 40
) -> TextNode {
  TextNode(
    string: string, fontName: "Helvetica", fontSize: size,
    fill: .color(RGBA(red: 0, green: 0, blue: 0)), position: position,
    transform: .identity)
}

@Test func advanceWidthIsPositiveForNonEmpty() {
  let width = TextRendering.advanceWidth(
    string: "Hello", fontName: "Helvetica", fontSize: 12)
  #expect(width > 0)
  let wider = TextRendering.advanceWidth(
    string: "Hello World", fontName: "Helvetica", fontSize: 12)
  #expect(wider > width)
}

@Test func rendersTextPixels() {
  // 큰 검정 텍스트를 그리면 일부 픽셀이 칠해진다
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 100))
  document.layers[0].nodes = [.text(textNode("HELLO", at: CGPoint(x: 10, y: 50)))]
  let context = renderToBitmap(document, size: CGSize(width: 200, height: 100))
  // 텍스트 영역에 칠해진 픽셀이 하나라도 있어야 한다
  var painted = false
  for x in stride(from: 10, to: 190, by: 5) {
    for y in stride(from: 20, to: 60, by: 5) where pixelColor(x: x, y: y, in: context).alpha > 0 {
      painted = true
    }
  }
  #expect(painted)
}

@Test func textBoundsAreNonZero() {
  let node = Node.text(textNode("Text", at: CGPoint(x: 20, y: 30)))
  let bounds = node.bounds
  #expect(bounds.width > 0)
  #expect(bounds.height > 0)
  // position 근처에 있다
  #expect(abs(bounds.minX - 20) < 30)
}

@Test func textHitTestInsideBounds() {
  var document = VectorDocument.empty(size: CGSize(width: 200, height: 100))
  let node = textNode("Hit", at: CGPoint(x: 50, y: 50))
  document.layers[0].nodes = [.text(node)]
  // 텍스트 바운드 중심 근처 클릭은 히트
  let bounds = Node.text(node).bounds
  let center = CGPoint(x: bounds.midX, y: bounds.midY)
  #expect(
    HitTesting.topmostNodeID(at: center, in: document, tolerance: 2) == node.id)
  // 멀리 떨어진 점은 미스
  #expect(
    HitTesting.topmostNodeID(at: CGPoint(x: 190, y: 95), in: document, tolerance: 2)
      == nil)
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`TextRendering` 없음, text bounds=zero)

- [ ] **Step 3: TextRendering 구현** — `Rendering/TextRendering.swift`

```swift
import CoreGraphics
import CoreText
import Foundation

/// 텍스트 렌더·측정 공용 (CoreText). 폰트명이 시스템에 없으면 폴백.
enum TextRendering {
  /// fontName/fontSize의 폰트 (없으면 시스템 폰트로 폴백 — 원본명은 노드가 보존).
  static func font(named fontName: String, size: CGFloat) -> CTFont {
    let cfName = fontName as CFString
    let font = CTFontCreateWithName(cfName, size, nil)
    return font
  }

  /// 문자열의 CTLine (fill 색 적용).
  static func line(_ string: String, fontName: String, fontSize: CGFloat, color: CGColor) -> CTLine {
    let font = font(named: fontName, size: fontSize)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: color,
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    return CTLineCreateWithAttributedString(attributed)
  }

  /// 텍스트 공간 advance 폭 (text matrix 이동용).
  static func advanceWidth(string: String, fontName: String, fontSize: CGFloat) -> CGFloat {
    guard !string.isEmpty else { return 0 }
    let line = line(string, fontName: fontName, fontSize: fontSize, color: .black)
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
  }

  /// 텍스트 바운드 (position 기준, 모델 좌표 — baseline 위로 ascent, 아래로 descent).
  /// 모델은 top-down이므로 baseline 위쪽(ascent)이 y 작은 방향.
  static func bounds(
    string: String, fontName: String, fontSize: CGFloat, position: CGPoint
  ) -> CGRect {
    guard !string.isEmpty else { return CGRect(origin: position, size: .zero) }
    let line = line(string, fontName: fontName, fontSize: fontSize, color: .black)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    // 모델 top-down: position이 baseline. ascent는 위(y−), descent는 아래(y+).
    return CGRect(
      x: position.x, y: position.y - ascent, width: width, height: ascent + descent)
  }
}
```

- [ ] **Step 4: SceneRenderer 텍스트 렌더** — `SceneRenderer.swift`의 `.text` 분기 교체:

```swift
    case .text(let textNode):
      render(textNode, in: context)
```

`render(_ imageNode:)` 근처에 추가:

```swift
  static func render(_ textNode: TextNode, in context: CGContext) {
    guard !textNode.string.isEmpty, case .color(let rgba) = textNode.fill else { return }
    context.saveGState()
    context.concatenate(textNode.transform.cgAffineTransform)
    let line = TextRendering.line(
      textNode.string, fontName: textNode.fontName,
      fontSize: CGFloat(textNode.fontSize), color: rgba.cgColor)
    // 모델은 top-down(y-down). CoreText는 baseline 기준 y-up으로 그린다 →
    // position에서 상하 플립해 baseline 위로 글자가 올라가게 한다.
    context.translateBy(x: textNode.position.x, y: textNode.position.y)
    context.scaleBy(x: 1, y: -1)
    context.textPosition = .zero
    CTLineDraw(line, context)
    context.restoreGState()
  }
```

(주의: 텍스트 방향·baseline은 CoreText/모델 좌표 상호작용이 미묘하다. `rendersTextPixels` 테스트가 "칠해진 픽셀 존재"를 확인하고, 시각 정립은 수동 체크리스트로 확정한다. 글자가 뒤집히거나 안 보이면 플립/translate를 조정한다.)

- [ ] **Step 5: ContentStreamParser+Text advance 교체** — Task 3의 근사 advance를 CoreText로:

```swift
    let width = TextRendering.advanceWidth(
      string: string, fontName: font.baseFont, fontSize: text.fontSize)
```

- [ ] **Step 6: Node.bounds·HitTesting 정밀화**

`BezierPath+Bounds.swift`의 text 분기 교체:

```swift
    case .text(let text):
      let local = TextRendering.bounds(
        string: text.string, fontName: text.fontName,
        fontSize: CGFloat(text.fontSize), position: text.position)
      return local.applying(text.transform.cgAffineTransform)
```

`HitTesting.swift`의 `hits(_ node:)` text 분기 교체 (현재 `case .text: return false`):

```swift
    case .text(let text):
      guard let inverse = text.transform.invertedOrNil else { return false }
      let local = point.applying(inverse)
      let textBounds = TextRendering.bounds(
        string: text.string, fontName: text.fontName,
        fontSize: CGFloat(text.fontSize), position: text.position)
      return textBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(local)
```

(마퀴 교차 판정 `topLevelNodeIDs(intersecting:)`은 `node.bounds`를 쓰므로 자동 반영. `topmostPathNodeID`의 `.text` continue는 직접 선택용이라 그대로.)

- [ ] **Step 7: 통과 확인** — `swift test` → 전체 PASS (350개 = 346 + 4). 텍스트 advance가 CoreText로 바뀌며 Task 3의 `multipleTjProduceMultipleNodes`·`tjArrayConcatenatesStrings`가 여전히 그린인지 확인.

- [ ] **Step 8: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: CoreText 텍스트 렌더·advance·바운드·히트테스트"
```

---

### Task 5: 통합 회귀 + README + 스펙 갱신 + PR

- [ ] **Step 1: 전체 회귀**

```bash
cd VectaEngine && swift build && swift test   # 350 PASS
cd ../VectaApp && xcodegen generate && \
xcodebuild -project Vecta.xcodeproj -scheme Vecta -configuration Debug \
  -derivedDataPath build build                # BUILD SUCCEEDED
```

스모크: `open VectaApp/build/Build/Products/Debug/Vecta.app` → 3s → `pgrep -x Vecta` → `pkill -x Vecta`.

- [ ] **Step 2: 수동 검증 체크리스트** (사용자 수행)

1. 텍스트가 든 PDF(문서·라벨) 열기 → 텍스트가 정립으로 올바른 위치에 표시
2. 색 있는 텍스트 → 색 반영
3. CID/복합 폰트(ToUnicode 없음) PDF → "N개 객체를 가져오지 못했습니다" 배너
4. 가져온 텍스트 문서를 .ai로 저장 → 재열기 100% 라운드트립 (문자열·폰트명·위치)
5. 저장한 .ai를 외부(미리보기)에서 열기 → PDF 본문에 텍스트 그려져 보임
6. 텍스트 클릭 → 선택(바운드 히트), 마퀴로 텍스트 포함
7. 기존 M3·M4a·M4b-1·M4b-2 회귀 (그라디언트·이미지·패스 무영향)

- [ ] **Step 3: README + 스펙 갱신**

README의 M4b-3 줄:

```markdown
- [x] M4b-3 외부 .ai 임포트: 텍스트
```

스펙 §11의 "정밀 텍스트 바운드는 M5에서" 줄을 갱신 (M4b-3에서 CTLine 측정으로 달성):

```
- **Model**: ... (텍스트 바운드는 M4b-3에서 CTLine 측정으로 구현)
```

(`BezierPath+Bounds.swift`·`HitTesting.swift`의 "M5에서" 주석도 갱신.)

- [ ] **Step 4: 이슈 코멘트 + PR**

```bash
gh issue comment 14 --body "M4b-3 구현 노트:
- 바이트→문자열: ToUnicode CMap 우선, 없으면 표준 인코딩(WinAnsi→CP1252 등) 근사
- /Differences는 무시+리포트 (Adobe 글리프명 매핑 비목표)
- Type0/CID는 ToUnicode 있으면 2바이트 코드로 처리, 없으면 리포트
- 각 Tj/TJ가 TextNode 1개, TJ 자간 조정 무시, advance는 CoreText 측정
- 텍스트 bounds·HitTesting을 CTLine 측정으로 정밀화 (스펙 §11 'M5' 항목 달성)
- 수직 쓰기·텍스트 렌더 모드(Tr clip 등) 비목표
- 후속(M5+): Differences 글리프 매핑, CID CMap 인코딩, 텍스트 편집 도구"

git push -u origin m4b3-text-import
gh pr create --base main --title "feat: M4b-3 외부 .ai 임포트 — 텍스트" \
  --body "$(cat <<'EOF'
## Summary
- 엔진: ToUnicode CMap 파서, PDF 폰트 디코더(ToUnicode·표준 인코딩), 텍스트 상태 머신(BT~ET / Tf / Td TD Tm T* / Tj TJ ' "), CoreText 렌더링, 텍스트 bounds·HitTesting 정밀화
- 각 텍스트 표시 연산 → TextNode(문자열·폰트명·크기·색·위치 베이크). SceneRenderer 공유로 PDF export 포함
- 미지원(CID 폰트 ToUnicode 없음·Differences·수직 쓰기)은 ImportReport 배너
- M4b 임포트 3개 도메인(그라디언트·이미지·텍스트) 완료

## Test Plan
- [x] 엔진 swift test 전체 통과 (베이스 327 + 신규 23 = 350)
- [x] xcodebuild BUILD SUCCEEDED + 스모크
- [ ] 수동 체크리스트 7항목 (plan Task 5 Step 2)

Closes #14

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 완료 기준 (M4b-3 Definition of Done)

- 엔진 테스트 전체 그린 (베이스 327 + 신규 ~23)
- 외부 PDF의 텍스트가 캔버스·PDF 출력에 올바른 위치·색으로 표시
- 미지원(CID·Differences·수직)은 배너로 보고 — 조용한 데이터 손실 없음
- 텍스트 위치 모델 베이크 정확, bounds·HitTesting CTLine 측정으로 정밀화
- 가져온 텍스트 문서 저장→재열기 100% 라운드트립
- 기존 M3·M4a·M4b-1·M4b-2 회귀 0
- PR이 이슈 #14를 닫음 → M4b 임포트 도메인 전체 완료

## M5 예고 (이슈 #6)

텍스트 도구(인라인 입력)·이미지 배치·패스파인더·정렬 — 임포트가 아닌 생성/편집 도구. M4b-3의 TextNode/ImageNode 모델·렌더를 도구로 만든다.

## Self-Review 메모

- 스펙 §5 텍스트 행(BT~TJ → TextNode, 표준 인코딩+ToUnicode) 커버. SceneRenderer 렌더로 export 자동.
- ToUnicode CMap·표준 인코딩 근사·Type0 리포트는 결정 기록에 명시. 글리프명(Differences)·CID CMap 인코딩은 비목표.
- 텍스트 좌표(baseline·CoreText y-up vs 모델 top-down)는 미묘 — `rendersTextPixels`가 "칠해짐"을 확인하고 시각 정립은 수동 체크. 글자 뒤집힘 시 렌더 플립 조정(픽셀이 사양).
- `ContentStreamParser+Text.swift` extension 분리로 본체 800줄 캡 유지.
- bounds/HitTesting 정밀화로 스펙 §11의 M5 항목을 앞당겨 달성 — 스펙·주석 갱신.
