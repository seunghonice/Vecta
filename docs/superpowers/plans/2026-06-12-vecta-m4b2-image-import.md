# Vecta M4b-2 — 외부 .ai 임포트: 이미지 (image XObject → ImageNode) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 외부 PDF의 image XObject를 디코드해 `ImageNode`로 임포트하고, `SceneRenderer`에 이미지 렌더링을 추가해 가져온 이미지가 캔버스·PDF 출력에 보이게 한다. 미지원(인덱스/CMYK/저비트 raw, 마스크, 인라인 이미지)은 ImportReport로 수집한다. (GitHub 이슈 #13, PR은 `Closes #13`. 텍스트=#14/M4b-3은 별도 PR)

**Architecture:** 이미지 디코드(`PDFImageDecoder`: CGPDF image stream → CGImage → PNG)와 CGImage↔PNG 코딩(`CGImageCoding`)을 ImportAI에 두고 픽스처로 헤드리스 테스트한다. `SceneRenderer`가 `ImageNode`를 그리도록 확장하면 AIFileWriter(공유)가 PDF 출력에도 이미지를 넣는다. 이미지는 픽셀이라 좌표 변환을 패스처럼 베이크할 수 없으므로 `ImageNode.frame=unit square`, 배치는 `transform`에 베이크한다(다른 임포트 노드와 다른 전략).

**Tech Stack:** Swift 6 (언어 모드 v5), Swift Testing, CoreGraphics(CGPDFStream/CGImage), ImageIO(CGImageSource/Destination), UniformTypeIdentifiers, XcodeGen. 엔진 플랫폼 .v14.

**참조:** 스펙 `docs/superpowers/specs/2026-06-11-vecta-vector-editor-design.md` §4(ImageNode)·§5(ImportAI)·§6(ExportAI 이미지)·§12-M4, 이슈 #13, M4b-1 계획(파서 컨벤션·좌표 베이크·결정 기록), PDF 32000-1 §8.9(Images).

---

## 커밋 규칙 (전역 규칙 — 기존과 동일)

매 커밋 전: ① `cd VectaEngine && swift build`(앱 변경 시 xcodebuild 추가) → ② `swift test` → ③ `swift format --in-place --recursive Sources Tests`(앱은 `VectaApp/Sources`) → ④ commit. 한국어 메시지+접두사, Co-Authored-By 금지. 테스트 실패 시 수정 후 ①부터 재수행.

## 결정 기록 (이 계획에서 확정)

| 결정 | 근거 |
|---|---|
| `ImageNode.frame = unit square (0,0,1,1)`, 배치는 `transform`에 베이크 | 픽셀은 패스처럼 변환할 수 없다. PDF image는 단위 정사각형에 매핑되고 CTM이 배치를 결정 — 그 CTM×pageFlip을 transform에 넣고 frame은 항상 단위 정사각형. `Node.bounds`(image)=`frame.applying(transform)`가 이미 정확히 동작 |
| 디코드 분기: `CGPDFStreamCopyData`의 format — jpeg/jpeg2000 → `CGImageSource`, raw → 직접 CGImage 구성 | CG가 압축 이미지(DCT/JPX)는 인코딩된 바이트로, 그 외(Flate·ASCIIHex 등)는 raw 픽셀로 준다. 압축은 ImageIO 위임, raw는 ColorSpace/BPC로 구성 |
| raw는 DeviceRGB/DeviceGray **8 BitsPerComponent**만 지원 | 실무 대다수. Indexed/Separation/ICC raw, 1·2·4·16 bpc → 미지원 리포트 |
| 정규화는 PNG (`ImageNode.imageData`) | 스펙 §4·§5. JSON 임베드 라운드트립으로 100% 보존(64MB 페이로드 상한 내 — M4a) |
| `ImageMask`·`SMask`(알파 마스크)는 무시하고 불투명 렌더 + 리포트 | M3 ImageNode는 알파 마스크 모델이 없다. 시각 근사 + 손실 리포트 |
| 인라인 이미지(BI/ID/EI)는 리포트 유지 (CGPDFScanner가 내부 소비 — 픽셀 추출 경로 없음) | M4a에서 BI 리포트만 등록. 인라인 이미지는 작고 드묾 |
| SceneRenderer 이미지는 CGImage(bottom-up)를 모델(top-down) frame에 상하 보정해 그림 | 좌표계 계약(모델 top-left, y-down) 유지. 정확한 방향은 비대칭 픽셀 테스트로 확정 |
| 디코드 실패·미지원이면 노드를 만들지 않고 리포트만 (도형은 패스 노드로 이미 보존됨) | 조용한 데이터 손실 금지 (스펙 §5) |

## 파일 구조 (M4b-2 추가/변경분)

```
VectaEngine/Sources/VectaEngine/
├── ImportAI/
│   ├── CGImageCoding.swift        (생성)  # CGImage ↔ PNG (Task 1)
│   └── PDFImageDecoder.swift      (생성)  # image XObject → PNG (Task 2)
├── Rendering/SceneRenderer.swift  (수정)  # ImageNode 렌더 (Task 1)
└── ImportAI/ContentStreamParser.swift (수정)  # invokeXObject Image 분기 (Task 3)

VectaEngine/Tests/VectaEngineTests/
├── SceneRendererImageTests.swift      (생성)  # 이미지 렌더 픽셀 (Task 1)
├── PDFImageDecoderTests.swift         (생성)  # 디코드 (Task 2)
└── ContentStreamParserImageTests.swift (생성)  # invokeXObject Image (Task 3)
```

핵심 계약 (기존 — 신규 코드가 의존):
- `SceneRenderer`는 캔버스와 PDF 익스포트가 공유 — 이미지 렌더만 넣으면 .ai 출력에도 반영된다.
- 파서 산출 노드는 좌표 베이크 (M4b-1까지 transform=identity였으나, 이미지는 예외 — 위 결정 기록).
- `ImageNode { id, imageData: Data, frame: CGRect, transform: Transform2D }` (M1 모델, Codable). `Node.bounds`/`HitTesting`의 image 분기는 frame·transform 기반으로 이미 동작.
- 테스트 베이스라인: 엔진 311개 그린. 브랜치 `m4b2-image-import` (base: `m4b1-gradient-import` — PR #16 미머지 시 스택).
- 픽스처: `makeTestPDF`(M4a). image XObject는 `/Filter /ASCIIHexDecode` + hex 문자열로 stream을 String에 담는다(raw 바이너리 회피). `/Length`는 hex 문자열 바이트 수(종료 `>` 포함).

---

### Task 1: CGImage ↔ PNG 코딩 + SceneRenderer 이미지 렌더링

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/CGImageCoding.swift`
- Modify: `VectaEngine/Sources/VectaEngine/Rendering/SceneRenderer.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/SceneRendererImageTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 상단 빨강 / 하단 파랑 2×2 PNG (top row = 빨강) — 상하 방향 검증용.
private func topRedBottomBluePNG() -> Data {
  let width = 2, height = 2
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  // CG는 y-up: 위쪽(y=1) 행을 먼저 칠하면 이미지 상단이 됨.
  context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
  context.fill(CGRect(x: 0, y: 1, width: 2, height: 1))  // CG 상단 = 이미지 첫 행
  context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))  // CG 하단 = 이미지 마지막 행
  let cgImage = context.makeImage()!
  return CGImageCoding.pngData(from: cgImage)!
}

@Test func pngRoundTripsThroughCGImageCoding() {
  let png = topRedBottomBluePNG()
  let decoded = CGImageCoding.cgImage(fromData: png)
  #expect(decoded != nil)
  #expect(decoded?.width == 2)
  #expect(decoded?.height == 2)
}

@Test func rendersImageUprightInModelSpace() {
  // ImageNode를 모델 (0,0)~(100,100)에 배치 — 모델 상단(y 작음)이 빨강이어야 한다.
  let png = topRedBottomBluePNG()
  // frame=unit square, transform = 모델 (0,0,100,100)으로 매핑
  let node = ImageNode(
    imageData: png, frame: CGRect(x: 0, y: 0, width: 1, height: 1),
    transform: Transform2D(CGAffineTransform(scaleX: 100, y: 100)))
  var document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  document.layers[0].nodes = [.image(node)]
  let context = renderToBitmap(document, size: CGSize(width: 100, height: 100))
  // 모델 상단(y=25)은 빨강, 하단(y=75)은 파랑 (이미지 첫 행이 모델 위)
  let top = pixelColor(x: 50, y: 25, in: context)
  #expect(top.red > 200)
  #expect(top.blue < 60)
  let bottom = pixelColor(x: 50, y: 75, in: context)
  #expect(bottom.blue > 200)
  #expect(bottom.red < 60)
}

@Test func corruptImageDataRendersNothing() {
  let node = ImageNode(
    imageData: Data("not a png".utf8),
    frame: CGRect(x: 0, y: 0, width: 1, height: 1),
    transform: Transform2D(CGAffineTransform(scaleX: 100, y: 100)))
  var document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  document.layers[0].nodes = [.image(node)]
  let context = renderToBitmap(document, size: CGSize(width: 100, height: 100))
  #expect(pixelColor(x: 50, y: 50, in: context).alpha == 0)  // 빈 캔버스
}
```

- [ ] **Step 2: 실패 확인** — `cd VectaEngine && swift test` → FAIL (`CGImageCoding` 없음)

- [ ] **Step 3: CGImageCoding 구현** — `ImportAI/CGImageCoding.swift`

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// CGImage ↔ PNG·일반 이미지 데이터 변환 (이미지 정규화·디코드 공용).
enum CGImageCoding {
  /// 임의 이미지 바이트(PNG·JPEG 등) → CGImage.
  static func cgImage(fromData data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return image
  }

  /// CGImage → PNG 데이터 (ImageNode 정규화 저장용).
  static func pngData(from image: CGImage) -> Data? {
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}
```

- [ ] **Step 4: SceneRenderer 이미지 렌더** — `Rendering/SceneRenderer.swift`의 `render(_ node:)`에서 image 분기 교체:

```swift
    case .image(let imageNode):
      render(imageNode, in: context)
```

(`.text`는 break 유지 — M4b-3에서.)

`render(_ pathNode:)` 근처에 추가:

```swift
  static func render(_ imageNode: ImageNode, in context: CGContext) {
    guard let cgImage = CGImageCoding.cgImage(fromData: imageNode.imageData) else { return }
    context.saveGState()
    context.concatenate(imageNode.transform.cgAffineTransform)
    // CGImage는 bottom-up — 모델(top-down) frame에 정립으로 그리려면 frame 내부에서 상하 플립.
    context.translateBy(x: 0, y: imageNode.frame.maxY + imageNode.frame.minY)
    context.scaleBy(x: 1, y: -1)
    context.draw(cgImage, in: imageNode.frame)
    context.restoreGState()
  }
```

(주의: 플립 수식은 frame 기준 상하 반전이다. `rendersImageUprightInModelSpace` 테스트가 방향을 확정한다 — 만약 상하가 뒤집혀 나오면 플립을 제거하거나 보정한다. 픽셀 테스트가 곧 사양이다.)

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (314개 = 311 + 3)

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: CGImage↔PNG 코딩과 SceneRenderer 이미지 렌더링"
```

---

### Task 2: PDFImageDecoder — image XObject stream → PNG

**Files:**
- Create: `VectaEngine/Sources/VectaEngine/ImportAI/PDFImageDecoder.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/PDFImageDecoderTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성** — 픽스처 image XObject(ASCIIHex raw RGB)를 꺼내 디코드한다.

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 픽스처 PDF의 /Resources/XObject/<name> image stream을 디코드한다.
private func decodeImageResource(
  name: String, imageObject: String
) -> (png: Data?, unsupported: String?) {
  let data = makeTestPDF(
    content: "/\(name) Do",
    resources: "<< /XObject << /\(name) 5 0 R >> >>",
    extraObjects: [imageObject])
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  // CGPDFReading.stream(from:)은 Step 3에서 추가한다.
  guard let object = CGPDFContentStreamGetResource(stream, "XObject", name),
    let xobjectStream = CGPDFReading.stream(from: object),
    let dictionary = CGPDFStreamGetDictionary(xobjectStream)
  else {
    Issue.record("이미지 리소스를 못 꺼냄")
    return (nil, nil)
  }
  return PDFImageDecoder.decode(xobjectStream, dictionary: dictionary)
}

/// 2×2 RGB raw 픽셀의 ASCIIHexDecode 이미지 XObject.
/// 픽셀: (좌상 빨강 FF0000)(우상 초록 00FF00)(좌하 파랑 0000FF)(우하 흰 FFFFFF)
/// PDF image 행 순서 = top-to-bottom: 1행 [빨강 초록], 2행 [파랑 흰].
private let rgbImageObject: String = {
  let hex = "FF000000FF000000FFFFFFFF"  // 12 bytes → 24 hex chars
  let stream = "\(hex)>"  // ASCIIHexDecode 종료 마커
  return
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/Length \(stream.utf8.count) >> stream\n\(stream)\nendstream"
}()

@Test func decodesRawRGBImageToPNG() {
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: rgbImageObject)
  #expect(unsupported == nil)
  guard let png, let cgImage = CGImageCoding.cgImage(fromData: png) else {
    Issue.record("PNG 디코드 실패")
    return
  }
  #expect(cgImage.width == 2)
  #expect(cgImage.height == 2)
}

@Test func unsupportedColorSpaceImageReports() {
  // Indexed 색공간 raw → 미지원
  let hex = "00010203>"
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace [/Indexed /DeviceRGB 1 <000000FFFFFF>] /BitsPerComponent 8 "
    + "/Filter /ASCIIHexDecode /Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(png == nil)
  #expect(unsupported != nil)
}

@Test func unsupportedBitDepthImageReports() {
  // 1 bpc raw → 미지원
  let hex = "FF>"
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceGray /BitsPerComponent 1 "
    + "/Filter /ASCIIHexDecode /Length \(hex.utf8.count) >> stream\n\(hex)\nendstream"
  let (png, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(png == nil)
  #expect(unsupported != nil)
}

@Test func imageMaskReports() {
  let hex = "FF>"
  let image =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /ImageMask true "
    + "/BitsPerComponent 1 /Filter /ASCIIHexDecode /Length \(hex.utf8.count) "
    + ">> stream\n\(hex)\nendstream"
  let (_, unsupported) = decodeImageResource(name: "Im0", imageObject: image)
  #expect(unsupported != nil)
}
```

테스트 지원: `decode`가 `CGPDFStreamRef`를 받으므로 테스트는 `CGPDFReading.stream(from: object)`로 object→stream 변환한다 (이 헬퍼는 Step 3에서 `CGPDFReading`에 추가한다 — 테스트가 먼저 참조하므로 RED 단계에서 컴파일 실패는 정상).

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (`PDFImageDecoder` 없음)

- [ ] **Step 3: CGPDFReading.stream 추가** — `ImportAI/CGPDFReading.swift`에 헬퍼 추가:

```swift
  /// 객체에서 stream을 꺼낸다.
  static func stream(from object: CGPDFObjectRef) -> CGPDFStreamRef? {
    var stream: CGPDFStreamRef? = nil
    guard CGPDFObjectGetValue(object, .stream, &stream) else { return nil }
    return stream
  }
```

- [ ] **Step 4: PDFImageDecoder 구현** — `ImportAI/PDFImageDecoder.swift`

```swift
import CoreGraphics
import Foundation

/// PDF image XObject → PNG 데이터 (스펙 §5). 압축 이미지(DCT/JPX)는 ImageIO에
/// 위임하고, raw는 DeviceRGB/Gray 8bpc만 직접 구성한다. 그 외는 미지원 사유 반환.
enum PDFImageDecoder {
  /// (png, unsupported) — png가 nil이고 unsupported가 사유면 리포트 대상.
  static func decode(
    _ stream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef
  ) -> (png: Data?, unsupported: String?) {
    if let bit = CGPDFReading.boolean(dictionary, "ImageMask"), bit {
      return (nil, "이미지 마스크 (알파 — 미지원)")
    }
    var format = CGPDFDataFormat.raw
    guard let data = CGPDFStreamCopyData(stream, &format) as Data? else {
      return (nil, "이미지 스트림 디코드 실패")
    }
    switch format {
    case .jpegEncoded, .jpeg2000Encoded:
      guard let cgImage = CGImageCoding.cgImage(fromData: data),
        let png = CGImageCoding.pngData(from: cgImage)
      else { return (nil, "압축 이미지 디코드 실패") }
      return (png, nil)
    case .raw:
      return decodeRaw(data, dictionary: dictionary)
    @unknown default:
      return (nil, "알 수 없는 이미지 포맷")
    }
  }

  private static func decodeRaw(
    _ data: Data, dictionary: CGPDFDictionaryRef
  ) -> (png: Data?, unsupported: String?) {
    guard let width = CGPDFReading.integer(dictionary, "Width"),
      let height = CGPDFReading.integer(dictionary, "Height"),
      width > 0, height > 0
    else { return (nil, "이미지 크기 누락") }
    let bitsPerComponent = CGPDFReading.integer(dictionary, "BitsPerComponent") ?? 8
    guard bitsPerComponent == 8 else {
      return (nil, "비트 깊이 \(bitsPerComponent) (8bpc만 지원)")
    }
    // /ColorSpace는 name(Device*)만. 배열형(Indexed/ICC 등)·SMask 동반은 미지원.
    if CGPDFReading.object(dictionary, "SMask") != nil {
      return (nil, "소프트 마스크 (알파 — 미지원)")
    }
    guard let spaceName = CGPDFReading.name(dictionary, "ColorSpace") else {
      return (nil, "비단순 이미지 색공간")
    }
    let componentCount: Int
    let cgSpace: CGColorSpace
    switch spaceName {
    case "DeviceRGB", "RGB", "CalRGB":
      componentCount = 3
      cgSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    case "DeviceGray", "G", "CalGray":
      componentCount = 1
      cgSpace = CGColorSpaceCreateDeviceGray()
    default:
      return (nil, "이미지 색공간 \(spaceName) (RGB·Gray만)")
    }
    let bytesPerRow = width * componentCount
    guard data.count >= bytesPerRow * height else {
      return (nil, "이미지 데이터 길이 부족")
    }
    // 두 색공간 모두 알파 없음 (raw 픽셀은 알파 채널 미포함).
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    guard let provider = CGDataProvider(data: data as CFData),
      let cgImage = CGImage(
        width: width, height: height, bitsPerComponent: 8,
        bitsPerPixel: 8 * componentCount, bytesPerRow: bytesPerRow,
        space: cgSpace, bitmapInfo: bitmapInfo, provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return (nil, "이미지 비트맵 구성 실패") }
    guard let png = CGImageCoding.pngData(from: cgImage) else {
      return (nil, "PNG 정규화 실패")
    }
    return (png, nil)
  }
}
```

`CGPDFReading`에 boolean 헬퍼가 없으면 추가:

```swift
  static func boolean(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Bool? {
    var value: CGPDFBoolean = 0
    guard CGPDFDictionaryGetBoolean(dictionary, key, &value) else { return nil }
    return value != 0
  }
```

- [ ] **Step 5: 통과 확인** — `swift test` → 전체 PASS (318개 = 314 + 4). raw 픽셀 디코드가 CG에서 다르게 동작하면(색공간·bytesPerRow) 픽셀을 출력해 조정하고, 기대를 실제 동작에 맞춰 고정한다(단 미지원 케이스가 nil을 반환하는 계약은 유지).

- [ ] **Step 6: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: PDF 이미지 디코더 — raw RGB/Gray·압축 → PNG 정규화"
```

---

### Task 3: ContentStreamParser invokeXObject Image 분기 → ImageNode

**Files:**
- Modify: `VectaEngine/Sources/VectaEngine/ImportAI/ContentStreamParser.swift`
- Test: `VectaEngine/Tests/VectaEngineTests/ContentStreamParserImageTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

/// 2×2 RGB raw ASCIIHex 이미지 (Task 2와 동일 구조).
private let rgbImageObject: String = {
  let hex = "FF000000FF000000FFFFFFFF"
  let stream = "\(hex)>"
  return
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode "
    + "/Length \(stream.utf8.count) >> stream\n\(stream)\nendstream"
}()

@Test func imageXObjectBecomesImageNodeWithBakedPlacement() {
  // q 80 0 0 60 30 40 cm /Im0 Do Q — unit square가 PDF (30,40)~(110,100)에 배치
  let (nodes, report) = parseFixture(
    content: "q 80 0 0 60 30 40 cm /Im0 Do Q",
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [rgbImageObject])
  #expect(report.isEmpty)
  #expect(nodes.count == 1)
  guard case .image(let imageNode) = nodes[0] else {
    Issue.record("이미지 노드가 아님")
    return
  }
  #expect(imageNode.frame == CGRect(x: 0, y: 0, width: 1, height: 1))
  #expect(!imageNode.imageData.isEmpty)
  // 모델 바운드: PDF (30,40)~(110,100) → 모델 y 100~160 (mediaBox 200)
  let bounds = Node.image(imageNode).bounds
  #expect(abs(bounds.minX - 30) < 0.0001)
  #expect(abs(bounds.width - 80) < 0.0001)
  #expect(abs(bounds.minY - 100) < 0.0001)
  #expect(abs(bounds.height - 60) < 0.0001)
}

@Test func unsupportedImageProducesNoNodeButReports() {
  let badImage =
    "<< /Type /XObject /Subtype /Image /Width 2 /Height 2 "
    + "/ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /ASCIIHexDecode "
    + "/Length 3 >> stream\nFF>\nendstream"
  let (nodes, report) = parseFixture(
    content: "/Im0 Do",
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [badImage])
  #expect(nodes.isEmpty)
  #expect(report.issues.contains { $0.kind == .unsupportedImage })
}

@Test func imageRespectsClip() {
  // 클립 안에서 이미지 — 클립 그룹으로 묶인다
  let (nodes, _) = parseFixture(
    content: "10 10 50 50 re W n q 80 0 0 60 0 0 cm /Im0 Do Q",
    resources: "<< /XObject << /Im0 5 0 R >> >>",
    extraObjects: [rgbImageObject])
  #expect(nodes.count == 1)
  guard case .group(let group) = nodes[0] else {
    Issue.record("클립 그룹이 아님")
    return
  }
  guard case .image = group.children.first else {
    Issue.record("그룹 안에 이미지가 아님")
    return
  }
}
```

- [ ] **Step 2: 실패 확인** — `swift test` → FAIL (Image가 아직 리포트만)

- [ ] **Step 3: invokeXObject Image 분기 교체** — `ContentStreamParser.swift`의 `case "Image":` 블록을 교체:

```swift
    case "Image":
      paintImage(xobjectStream, dictionary: dictionary)
```

핸들러 추가 (XObject 섹션):

```swift
  /// image XObject → ImageNode. frame=unit square, 배치는 transform에 베이크
  /// (CTM × pageFlip). 디코드 실패·미지원이면 노드 없이 리포트만.
  private func paintImage(_ stream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef) {
    let (png, unsupported) = PDFImageDecoder.decode(stream, dictionary: dictionary)
    if let unsupported {
      report.add(.unsupportedImage, detail: unsupported)
      return
    }
    guard let png else {
      report.add(.unsupportedImage, detail: "이미지 디코드 실패")
      return
    }
    let toModel = state.ctm.concatenating(pageFlip)
    let node = ImageNode(
      imageData: png, frame: CGRect(x: 0, y: 0, width: 1, height: 1),
      transform: Transform2D(toModel))
    appendNode(.image(node), explicitClip: state.clip)
  }
```

(`invokeXObject`는 이미 `xobjectStream`/`dictionary`를 추출해 두므로 그 변수를 전달한다 — 현재 `case "Image"`가 `dictionary`만 받는다면 `xobjectStream`도 스코프에 있으니 둘 다 넘긴다.)

- [ ] **Step 4: 통과 확인** — `swift test` → 전체 PASS (321개 = 318 + 3). `imageXObjectBecomesImageNodeWithBakedPlacement`의 바운드가 다르면 좌표 베이크(CTM 합성 순서·pageFlip)를 점검하고 실제 모델 좌표로 고정한다.

- [ ] **Step 5: 포맷 후 커밋**

```bash
cd VectaEngine && swift format --in-place --recursive Sources Tests && cd ..
git add -A && git commit -m "feat: image XObject 임포트 — ImageNode 좌표 베이크·미지원 리포트"
```

---

### Task 4: 통합 회귀 + README + PR

- [ ] **Step 1: 전체 회귀**

```bash
cd VectaEngine && swift build && swift test   # 321 PASS
cd ../VectaApp && xcodegen generate && \
xcodebuild -project Vecta.xcodeproj -scheme Vecta -configuration Debug \
  -derivedDataPath build build                # BUILD SUCCEEDED
```

스모크: `open VectaApp/build/Build/Products/Debug/Vecta.app` → 3s → `pgrep -x Vecta` → `pkill -x Vecta`.

- [ ] **Step 2: 수동 검증 체크리스트** (사용자 수행)

1. 이미지가 든 PDF(사진 배치) 열기 → 이미지가 캔버스에 정립으로 표시 (상하 정상)
2. 회전된 이미지 PDF → 회전 반영
3. CMYK·인덱스 이미지 PDF → "N개 객체를 가져오지 못했습니다" 배너 (도형은 표시)
4. 가져온 이미지 문서를 .ai로 저장 → 재열기 100% 라운드트립 (PNG JSON 임베드)
5. 저장한 .ai를 외부(미리보기 등)에서 열기 → PDF 본문에 이미지가 그려져 보임 (SceneRenderer export)
6. 기존 M3·M4a·M4b-1 회귀 (그라디언트·패스 임포트 무영향)

- [ ] **Step 3: README 갱신** — M4b-2 줄 체크:

```markdown
- [x] M4b-2 외부 .ai 임포트: 이미지
```

- [ ] **Step 4: 이슈 코멘트 + PR** — base 결정: PR #16(M4b-1)이 머지됐으면 `main`, 아니면 `m4b1-gradient-import`(스택). `gh pr view 16 --json state`로 확인.

```bash
gh issue comment 13 --body "M4b-2 구현 노트:
- raw 이미지는 DeviceRGB/Gray 8bpc만 직접 구성, 압축(DCT/JPX)은 ImageIO 위임
- 인덱스/CMYK/저비트 raw·ImageMask·SMask → 미지원 리포트
- 인라인 이미지(BI)는 리포트 유지 (CGPDFScanner 내부 소비)
- ImageNode frame=unit square, 배치는 transform 베이크 (픽셀은 변환 불가 — 다른 노드와 다른 전략)
- 정규화 PNG → JSON 임베드 라운드트립. SceneRenderer 렌더 추가로 export도 이미지 포함
- 후속(텍스트 #14)에서 ContentStreamParser 800줄 근접 시 operator 등록 extension 분리 검토"

git push -u origin m4b2-image-import
gh pr create --base <위에서 결정> --title "feat: M4b-2 외부 .ai 임포트 — 이미지" \
  --body "$(cat <<'EOF'
## Summary
- 엔진: image XObject 디코드(raw RGB/Gray 8bpc·압축 DCT/JPX → PNG 정규화), SceneRenderer 이미지 렌더링(상하 보정), ImageNode 좌표 베이크(frame=unit square, transform=CTM×pageFlip)
- 미지원(인덱스/CMYK/저비트 raw·ImageMask·SMask·인라인 이미지)은 ImportReport 배너 — 조용한 데이터 손실 없음
- SceneRenderer 공유로 PDF export에도 이미지 반영. 앱 변경 없음

## Test Plan
- [x] 엔진 swift test 전체 통과 (베이스 311 + 신규 10 = 321)
- [x] xcodebuild BUILD SUCCEEDED + 스모크
- [ ] 수동 체크리스트 6항목 (plan Task 4 Step 2)

Closes #13

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 완료 기준 (M4b-2 Definition of Done)

- 엔진 테스트 전체 그린 (베이스 311 + 신규 ~10)
- 외부 PDF의 RGB/Gray 이미지가 캔버스·PDF 출력에 정립으로 표시
- 미지원(인덱스/CMYK/저비트/마스크/인라인)은 배너로 보고 — 조용한 데이터 손실 없음
- 이미지 좌표가 모델로 정확히 베이크 (회전 포함)
- 가져온 이미지 문서 저장→재열기 100% 라운드트립 (PNG JSON 임베드)
- 기존 M3·M4a·M4b-1 회귀 0
- PR이 이슈 #13을 닫음

## M4b-3 예고 (이슈 #14)

텍스트 — 텍스트 상태 머신(BT~TJ), 표준 인코딩+ToUnicode → TextNode, SceneRenderer 텍스트 렌더(CoreText), Node.bounds·HitTesting 정밀화. 가장 큰 도메인. 이 이미지 PR과 독립.

## Self-Review 메모

- 스펙 §5 이미지 행("Do (image XObject) → ImageNode(PNG로 디코드)") + §6("CGImage 임베드") 커버. SceneRenderer 렌더로 export 자동.
- frame=unit square + transform 베이크는 다른 임포트 노드(transform=identity)와 다른 전략 — 픽셀 변환 불가가 근거. 결정 기록에 명시. Node.bounds/HitTesting의 image 분기가 이미 frame·transform 기반이라 호환.
- 상하 플립은 픽셀 테스트(`rendersImageUprightInModelSpace`)가 사양 — 구현자가 방향을 테스트로 확정.
- CGPDFStreamCopyData/raw CGImage 구성은 CG 동작에 의존 — 구현자가 픽셀로 검증·조정(미지원 nil 계약은 유지).
