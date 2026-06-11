# Vecta — macOS 벡터 그래픽 에디터 설계

- 날짜: 2026-06-11
- 상태: 승인됨
- 플랫폼: macOS 14+ (Apple Silicon/Intel), Swift, Xcode

## 1. 목적

Adobe Illustrator의 최소·핵심 기능을 가진 macOS 네이티브 벡터 그래픽 에디터.
.ai 파일을 **만들고, 열고, 편집**할 수 있다. 개인 도구이며, 사용자는 Adobe
Illustrator를 보유하지 않는다 — 즉 "Illustrator 없이 .ai 파일을 다루는 것"이
핵심 가치다.

### 성공 기준

1. 실제 Adobe Illustrator로 만든 .ai 파일(PDF 호환 저장본)을 열어 객체 단위로
   편집할 수 있다 (Illustrator 파일 호환 최대화).
2. 우리 앱에서 만든 .ai 파일은 다시 열었을 때 100% 보존된다.
3. 우리 앱이 저장한 .ai는 유효한 PDF여서 미리보기(Preview.app) 등 타 앱에서
   정상 렌더링된다.

### .ai 포맷에 대한 전제

- Illustrator 9+ 의 .ai는 PDF 컨테이너다. "PDF 호환" 옵션(기본 켜짐)으로
  저장된 파일은 표준 PDF로 읽을 수 있다.
- Adobe 네이티브 편집 데이터(PGF, `/AIPrivateData`)는 비공개·비문서화 포맷으로
  파싱 대상이 아니다. 읽기는 PDF 부분을 파싱한다 (Affinity/Sketch/Inkscape와
  같은 전략).
- 쓰기는 표준 PDF를 생성해 `.ai` 확장자로 저장한다.

## 2. 범위

### 포함 (MVP)

- 도구: 선택(이동/리사이즈/회전), 직접 선택(앵커포인트), 펜(베지어),
  도형(사각형/타원/선/다각형), 텍스트(포인트 텍스트), 핸드/줌
- 스타일: 면·선 색상, 선 두께/캡/조인/대시, 불투명도, 선형/원형 그라디언트
- 구조: 레이어(표시/잠금/이름/순서), 그룹/해제, 앞뒤 순서
- 연산: 패스파인더(합치기/빼기/교집합/제외), 정렬(좌/중/우/상/중/하)
- 이미지 배치(PNG/JPG 임베드)
- 파일: .ai 열기/저장, .pdf 열기, 새 문서(아트보드 크기 지정)
- 실행취소/재실행, 복사/붙여넣기/복제, 표준 단축키

### 제외 (명시적 비목표)

- Adobe 네이티브 데이터(PGF) 읽기/쓰기
- 영역 텍스트, 텍스트 흘리기, 패스 위 텍스트
- 메시 그라디언트, 패턴 채움, 브러시, 심볼, 블렌드, 효과(그림자/블러)
- 다중 아트보드 (1페이지만 로드, 초과 시 경고)
- 스냅핑/스마트 가이드 (추후 확장)
- 배포/서명/앱스토어 (개인 도구)

## 3. 아키텍처

AppKit 캔버스 + SwiftUI 패널 하이브리드. 엔진은 SPM 패키지로 분리.

```
vecta/
├── VectaEngine/            # SPM 패키지 — AppKit 의존성 없음, swift test 가능
│   ├── Sources/VectaEngine/
│   │   ├── Model/          # 씬그래프: VectorDocument, Layer, Node…
│   │   ├── Geometry/       # BezierPath, 변환, 바운드, 히트테스트, 패스파인더
│   │   ├── ImportAI/       # CGPDFScanner 기반 .ai/PDF → 씬그래프 파서
│   │   └── ExportAI/       # 씬그래프 → PDF(.ai) 작성기 + 네이티브 JSON 임베드
│   └── Tests/VectaEngineTests/
└── VectaApp/               # Xcode 앱 타깃 (macOS 14+)
    ├── Document/           # NSDocument 서브클래스 (읽기/쓰기/undo 연결)
    ├── Canvas/             # CanvasView(NSView), Tool 프로토콜과 구현들
    └── Panels/             # SwiftUI: 툴바, 인스펙터, 레이어 패널
```

- VectaEngine은 CoreGraphics/CoreText/ImageIO/PDFKit까지만 의존 (헤드리스
  테스트 가능). AppKit/SwiftUI 의존 금지.
- 의존성은 생성자 주입. 서드파티 패키지 없음.

## 4. 문서 모델 (VectaEngine/Model)

값 타입 씬그래프. 전부 `struct`/`enum`, `Codable`, `Equatable`.

```swift
struct VectorDocument { var artboard: Artboard; var layers: [Layer] }
struct Artboard      { var size: CGSize }                  // pt 단위
struct Layer         { let id: NodeID; var name: String
                       var isVisible: Bool; var isLocked: Bool
                       var nodes: [Node] }

enum Node { case path(PathNode), group(GroupNode), text(TextNode), image(ImageNode) }

struct PathNode  { let id: NodeID; var path: BezierPath
                   var style: Style; var transform: CGAffineTransform }
struct GroupNode { let id: NodeID; var children: [Node]
                   var clipPath: BezierPath?; var transform: CGAffineTransform }
struct TextNode  { let id: NodeID; var string: String
                   var fontName: String; var fontSize: CGFloat
                   var fill: Paint; var position: CGPoint
                   var transform: CGAffineTransform }
struct ImageNode { let id: NodeID; var imageData: Data    // PNG로 정규화
                   var frame: CGRect; var transform: CGAffineTransform }

struct Style  { var fill: Paint?; var stroke: Stroke?; var opacity: Double }
enum Paint    { case color(RGBA), linearGradient(Gradient), radialGradient(Gradient) }
struct Stroke { var paint: RGBA; var width: CGFloat
                var cap: LineCap; var join: LineJoin; var dash: [CGFloat] }
struct Gradient { var stops: [GradientStop]    // 위치 0…1 + RGBA
                  var start: CGPoint; var end: CGPoint }  // 객체 로컬 좌표

struct BezierPath { var subpaths: [Subpath] }
struct Subpath    { var segments: [PathSegment]; var isClosed: Bool }
enum PathSegment  { case move(to:), line(to:), curve(to:control1:control2:) }
```

- `NodeID = UUID`. 선택 상태는 모델 밖(앱 레이어)에서 `Set<NodeID>`로 관리.
- 좌표계: 모델은 top-left 원점(UI 친화). PDF I/O 경계에서만 bottom-left로 변환.
- 텍스트 폰트가 시스템에 없으면 폴백 폰트로 렌더하되 `fontName`은 원본 보존.

## 5. .ai 읽기 — ImportAI

`CGPDFDocument` → 1페이지 → `CGPDFContentStream` + `CGPDFScanner` 연산자 순회.
그래픽 상태 스택(CTM, fill/stroke 색, 클립, 폰트)을 유지하며 Node를 생성한다.

### 지원 연산자

| 분류 | 연산자 | 매핑 |
|---|---|---|
| 패스 구성 | `m l c v y h re` | BezierPath |
| 페인팅 | `f f* F B B* b S s n` | PathNode (fill/stroke/짝홀 규칙) |
| 상태 | `q Q cm gs w J j d` | 상태 스택, Stroke 속성 |
| 색상 | `rg RG k K g G cs CS sc scn SC SCN` | RGBA (CMYK/Gray→RGB 변환) |
| 클리핑 | `W W* … n` | GroupNode.clipPath |
| 그라디언트 | `sh`, 패턴 컬러스페이스의 shading 패턴 (type 2/3) | linear/radialGradient |
| 이미지 | `Do` (image XObject) | ImageNode (PNG로 디코드) |
| 폼 | `Do` (form XObject) | 재귀 파싱 → GroupNode |
| 텍스트 | `BT ET Tf Td TD Tm T* Tj TJ ' "` | TextNode |

### 텍스트 인코딩

- 심플 폰트 + 표준 인코딩(WinAnsi/MacRoman/Standard) 우선 지원.
- `ToUnicode` CMap 있으면 사용. 그 외 복합 인코딩은 best effort, 실패 시
  ImportReport에 기록.

### ImportReport — 조용한 데이터 손실 금지

미지원 요소(메시 그라디언트, 투명도 그룹, 미지원 패턴 등)는 건너뛰되 반드시
`ImportReport`에 항목별로 수집한다. 앱은 비모달 배너로
"N개 객체를 가져오지 못했습니다 (자세히)"를 표시한다.

- 파일 자체가 안 열림(`CGPDFDocument` 생성 실패, 암호화) → 명확한 에러 메시지.
- 다중 페이지 → 1페이지만 로드 + 경고 항목 추가.

## 6. .ai 쓰기 — ExportAI

1. `CGContext`(PDF)로 1페이지 생성. mediaBox = 아트보드 크기.
2. 씬그래프 순회하며 그리기:
   - 패스: CGPath 변환 후 fill/stroke
   - 그라디언트: 패스를 클립 → `CGGradient`(axial/radial) 드로우
     (M3 결정: CGShading+CGFunction은 스톱 보간 수동 구현이 필요해
     CGGradient 채택 — PDF에는 동일하게 shading으로 기록됨)
   - 텍스트: CoreText(`CTLine`)로 그려 **PDF에 실제 텍스트로 보존**
   - 이미지: `CGImage` 임베드
3. **네이티브 라운드트립** (2026-06-11 스파이크로 검증 완료): 생성된 PDF
   바이트의 마지막 `startxref` 직전에 씬그래프 JSON(Codable)을 base64로 감싼
   PDF 주석 블록으로 삽입한다.

   ```
   %VectaSceneJSON-BEGIN
   %<base64(JSON)>
   %VectaSceneJSON-END
   ```

   - 주석 블록은 xref 오프셋에 영향을 주지 않아 파일이 유효한 PDF로 유지됨
     (CGPDFDocument·PDFKit 모두 정상 인식, 1MB 페이로드 검증 완료).
   - 열기 시 마커를 스캔해 JSON이 있으면 그대로 디코드 (100% 보존).
   - 없으면(외부 파일) 5절의 콘텐츠 스트림 파싱으로 폴백.
   - 기각된 대안: PDFKit Info 커스텀 키(문자열 키로 잘못 직렬화돼 재독 불가),
     CGContext auxiliaryInfo(미지원 키 무시), Keywords 키(~5배 부풀림 +
     메타데이터 오염), 숨김 주석(~10배 부풀림).
4. 문서 타입: `.ai`(`com.adobe.illustrator`) 읽기/쓰기, `.pdf` 읽기.

## 7. 캔버스와 도구 (VectaApp)

### 캔버스

- `NSScrollView` + `CanvasView`(NSView). 줌 = magnification(⌘+/⌘−/핀치,
  1%~6400%), 스페이스바 = 일시적 핸드 툴.
- 렌더링: `draw(_:)`에서 CoreGraphics로 씬그래프 순회. dirty rect와 노드
  바운드로 컬링. 선택 핸들·마퀴·펜 미리보기는 오버레이로 마지막에 그림.
- **GPU/Metal 비채택 (의도적 결정, 2026-06-11)**: 캔버스는 CoreGraphics(CPU)로
  그린다. ① 캔버스와 PDF 출력이 SceneRenderer 하나를 공유해 화면=파일 일치가
  구조적으로 보장되고, ② MVP 규모(수백~수천 패스)는 Apple Silicon에서 CG로
  충분하며, ③ Metal 벡터 래스터화(stencil-and-cover/테셀레이션)는 에디터
  본체보다 큰 복잡도이기 때문. 줌 제스처 중에는 NSScrollView가 캐시된 비트맵을
  스케일링하므로 매 프레임 재렌더가 아니다.
- 성능이 실측으로 부족해지면 단계적 에스컬레이션: dirty-rect 컬링(기본 포함)
  → CGLayer/타일 캐싱 → 최후에 캔버스 전용 Metal 렌더러를 SceneRenderer 계약
  뒤에 추가(파일 출력은 계속 CG 유지).

### 도구 — 상태 머신

```swift
protocol CanvasTool {
    func mouseDown(_ event: CanvasEvent, context: ToolContext)
    func mouseDragged(_ event: CanvasEvent, context: ToolContext)
    func mouseUp(_ event: CanvasEvent, context: ToolContext)
    func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool
    var cursorKind: CursorKind { get }  // NSCursor 매핑은 앱 레이어
    func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext)
}
```

- `CanvasEvent`는 NSEvent를 모델 좌표로 변환한 합성 가능한 값 타입 →
  툴 로직을 AppKit 없이 단위 테스트 가능.
- `ToolContext`는 문서 변경(`apply`)·선택 상태·스냅샷 트랜잭션 진입점.
- 도구 로직(SelectTool/ShapeTool)은 VectaEngine/Tools/ 에 위치해
  `swift test`로 헤드리스 테스트된다 (AppKit 비의존).

| 도구 | 키 | 동작 |
|---|---|---|
| 선택 | V | 클릭(topmost 히트)/Shift 추가/마퀴, 이동, 8핸들 리사이즈(Shift=비율 유지), 모서리 바깥 회전 |
| 직접 선택 | A | 앵커포인트·컨트롤 핸들 드래그 편집 |
| 펜 | P | 클릭=코너, 드래그=스무스, 시작점 클릭=닫기, Esc/Enter=종료 |
| 사각형/타원/선/다각형 | M/L/\\ | 드래그 생성, Shift=정비율/45° |
| 텍스트 | T | 클릭 → 인라인 입력(NSTextField 오버레이), 포인트 텍스트만 |
| 핸드/줌 | Space(H)/Z | 팬 / 클릭 줌인·Option 클릭 줌아웃 |

### 히트테스트

- fill 있는 패스: 내부 포함 판정. stroke만 있는 패스: 선 두께+여유로 판정.
- 잠긴 레이어/숨김 레이어 제외. 그룹은 통째로 선택(선택 도구),
  직접 선택은 내부 진입.

## 8. 패널과 메뉴

- **좌측**: 도구 버튼 세로 스트립 (SwiftUI)
- **우측 인스펙터** (SwiftUI): 면/선 컬러웰, 그라디언트 타입·각도·스톱 에디터,
  선 두께/캡/조인, 불투명도, X/Y/W/H/회전 수치 입력,
  패스파인더 4버튼, 정렬 6버튼
- **우측 하단 레이어 패널** (SwiftUI): 레이어 목록 + 노드 트리, 눈/자물쇠 토글,
  이름 더블클릭 편집, 드래그 순서 변경, 클릭 선택(캔버스 선택과 동기화)
- 패스파인더: 선택된 2+ 패스에 `CGPath.union/subtracting/intersection/
  symmetricDifference`(macOS 13+) 적용 → 결과 PathNode 1개로 치환
  (스타일은 최하단 객체 기준)
- 메뉴/단축키: File(New ⌘N/Open ⌘O/Save ⌘S/Save As ⇧⌘S/Place Image…),
  Edit(Undo ⌘Z/Redo ⇧⌘Z/Cut/Copy/Paste/Duplicate ⌘D/Delete/Select All ⌘A),
  Object(Group ⌘G/Ungroup ⇧⌘G/Bring Forward ⌘]/Send Backward ⌘[ + 패스파인더),
  View(Zoom In/Out/Fit/100%)

## 9. Undo와 상태 관리

- 모든 모델 변경은 `DocumentStore.apply(_:)` 단일 경로를 통과한다.
- 스냅샷 undo: 제스처(또는 명령) 단위로 변경 전 `VectorDocument` 값을
  `NSUndoManager`에 등록. 드래그 중에는 등록하지 않고 mouseUp에 1회.
- 상태 전파: `DocumentStore`는 `ChangeNotifier` 역할(ObservableObject) —
  캔버스는 무효화, SwiftUI 패널은 구독으로 갱신. 서드파티 상태 라이브러리 없음.

## 10. 에러 처리

| 상황 | 처리 |
|---|---|
| 열기: PDF 아님/암호화/손상 | NSError로 명확한 사유 표시 ("지원하지 않는 파일입니다") |
| 열기: 일부 객체 미지원 | ImportReport 수집 → 비모달 배너 + 상세 보기 |
| 저장: 쓰기 실패 | NSDocument 표준 에러 경로 |
| 이미지 배치: 디코드 실패 | 알림 + 작업 취소 |
| 폰트 미설치 | 폴백 폰트 렌더 + 원본 폰트명 보존, 인스펙터에 표시 |

빈 catch 블록 금지. 엔진 레벨 에러는 구체적 타입
(`ImportError`, `ExportError`)으로 던진다.

## 11. 테스트 전략

TDD (Red → Green → Refactor). 로직 대부분을 VectaEngine에 두어 헤드리스로
테스트한다.

- **Model**: Codable 라운드트립, Equatable, 노드 트리 조작(삽입/삭제/이동)
- **Geometry**: 바운드 계산, 변환 합성, 히트테스트, BezierPath↔CGPath 변환,
  패스파인더 결과
- **ImportAI**: ① 자체 익스포터 산출물 파싱, ② 테스트 리소스의 수제 미니멀
  PDF(연산자 케이스별) 파싱 → 기대 씬그래프 단언
- **ExportAI**: 산출 PDF를 CGPDF로 재파싱해 구조 단언;
  핵심 속성 `import(export(doc))` 안정성 검증
- **앱 레이어**: 툴 로직은 `CanvasEvent` 합성 이벤트로 단위 테스트
  (AppKit 불필요). NSDocument/뷰는 얇게 유지.

## 12. 마일스톤

각 마일스톤은 동작하는 상태로 끝난다.

1. **최소 루프**: 엔진 모델 + 도형 그리기(사각형/타원) + .ai 저장 + 자체 파일
   열기. *(JSON 임베드 방식 스파이크는 완료 — 6절)*
2. **편집**: 선택/이동/리사이즈/회전, 직접 선택, 펜 도구
3. **스타일·구조**: 색/선/그라디언트 인스펙터, 레이어 패널, undo 전면 적용
4. **외부 .ai 임포트**: 패스/스타일 → 클립·폼 → 그라디언트 → 이미지 → 텍스트
   순으로 파서 확장 + ImportReport UI
5. **나머지 도구**: 텍스트 도구, 이미지 배치, 패스파인더, 정렬, 복사/붙여넣기
6. **마감**: 단축키 정비, 줌/팬 폴리시, 다중 페이지 경고, 에러 메시지 정비

## 13. 미해결 리스크

| 리스크 | 대응 |
|---|---|
| ~~PDFKit 커스텀 Info 키 미보존~~ | 해소됨 — 스파이크 결과 startxref 직전 주석 블록 방식으로 확정 (6절) |
| 실제 .ai 파일의 PDF 다양성 (생성기마다 연산자 패턴 상이) | 샘플 .ai 코퍼스 확보 후 케이스 추가, ImportReport로 가시화 |
| 텍스트 인코딩 복잡도 (CID/복합 폰트) | MVP는 심플 폰트 우선, 실패는 리포트로 표면화 |
| CGPath 불리언 결과 품질 (자기교차 등 엣지) | `normalized()` 전처리, 테스트 케이스 확보 |
