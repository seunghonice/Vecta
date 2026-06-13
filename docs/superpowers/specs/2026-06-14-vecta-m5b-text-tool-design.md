# M5b — 텍스트 도구 (인라인 입력) 설계

- 날짜: 2026-06-14
- 상태: 승인됨
- 선행: M4b-3(텍스트 임포트 — `TextNode` 모델·렌더·히트테스트·변환 존재)

## 1. 목적

캔버스에 **점 텍스트**를 인라인으로 입력·편집하는 도구를 추가한다. 사용자는
text 도구로 캔버스를 클릭해 그 자리에서 바로 타이핑하고(생성), 기존 텍스트를
더블클릭해 문자열을 수정한다(편집). 폰트 패밀리·크기·색은 인스펙터에서 조절한다.

### 성공 기준

1. text 도구로 빈 곳을 클릭하면 그 자리에 캐럿이 서고, 한글/영문을 IME로
   입력해 여러 줄(Enter=줄바꿈) 텍스트를 만든다. 확정 시 캔버스에 그대로 렌더된다.
2. 기존 텍스트 노드를 (text 도구 클릭 또는 SelectTool 더블클릭으로) 다시 열어
   문자열을 수정할 수 있다.
3. 인스펙터에서 선택된 텍스트의 폰트 패밀리·크기·색을 바꾼다.
4. 생성·편집·서식 변경이 각각 undo 1단계로 묶인다.
5. 만든 텍스트가 네이티브 .ai 저장 → 재열기에서 100% 보존된다(멀티라인 포함).

## 2. 범위

### 포함

- **점 텍스트**(`TextNode.position` 기준) — 영역/래핑 텍스트 아님.
- **여러 줄** — Enter=줄바꿈. 렌더러를 다중 CTLine으로 업그레이드.
- **생성 + 재편집** — 빈 곳 클릭=생성, 기존 텍스트 클릭/더블클릭=편집.
- **서식 인스펙터** — 폰트 패밀리(설치 폰트) + 크기 + 색(단색).
- **한글 IME** — 네이티브 입력(조합·캐럿·선택·텍스트 내 복붙).

### 제외 (M5b 범위 외)

- 영역 텍스트(드래그 박스·래핑), 패스 위 텍스트.
- 문자/문단 단위 부분 서식(텍스트 노드 전체가 단일 서식).
- 회전/스케일된 텍스트의 *변형 반영* 인라인 편집 — 문자열만 축정렬 오버레이로
  수정(아래 §6 한계).

## 3. 아키텍처 경계 (엔진 ↔ 앱)

원칙: **배치 결정은 엔진, 문자 입력은 AppKit.** 엔진 `TextTool`은 클릭이 생성인지
편집인지만 판정하고, AppKit이 실제 `NSTextView`를 띄운다. 통신은 기존
`ToolContext.invalidateOverlay`와 동일한 앱-주입 클로저 패턴을 쓴다.

```
엔진:  enum TextEditRequest { case create(at: CGPoint); case edit(NodeID) }
       ToolContext.requestTextEditing: (TextEditRequest) -> Void   // 기본 no-op
       TextTool.mouseDown → 히트테스트로 request 산출 → context.requestTextEditing(request)
앱:    CanvasView가 requestTextEditing 클로저에서 NSTextView 편집 세션을 띄움
```

엔진은 AppKit-free 유지(값 + 클로저), 도구 디스패치도 다른 도구와 균일하다.

거부된 대안:
- **순수 엔진 키 라우팅**(CanvasKey에 문자 적재, 엔진이 버퍼·캐럿 직접 관리) —
  텍스트 편집 재구현 → 한글 IME·조합 불가, 시스템 캐럿/선택 없음. 기각.
- **모달 다이얼로그 입력** — 마일스톤이 명시한 "인라인"이 아니고 WYSIWYG 아님. 기각.

## 4. 엔진 변경 (전부 `swift test` 단위검증)

1. **`TextEditRequest`** 값 타입 + **`TextTool: CanvasTool`** — `mouseDown`에서
   **최상위 노드** 히트테스트 → 그것이 TextNode면 `.edit(id)`, 아니면(노드 없음 또는
   비텍스트 노드) `.create(at: point)`. 즉 패스가 텍스트 위를 덮고 있으면 텍스트
   대신 생성으로 처리해 결정적이다. 드래그/오버레이 없음(점 텍스트). 커서 `.iBeam`.
2. **`CursorKind.iBeam`** + **`ToolKind.text`** 케이스 — `makeTool()` 망라 switch가
   팩토리/툴바/단축키 동기화를 컴파일 타임에 강제.
3. **`VectorDocument+Editing.updateTextNode(id:_:)`** (`updatePathNode` 미러) +
   **`DocumentStore`** 명령:
   - 생성: 기존 `appendNodeToActiveLayer(.text(…))` 재사용.
   - 문자열 확정: `commitTextEdit(id:string:)` — snapshot 1회 = undo 1단계.
   - 서식: `updateSelectedTextNodes(...)` transient/commit (`updateSelectionStyles` 미러).
4. **멀티라인 렌더** — `TextRendering`을 `\n` 분할 다중 CTLine으로 업그레이드:
   `lines()` / `bounds()`(폭 = 최대 줄폭, 높이 = Σ 줄높이) / 줄별 baseline 배치.
   CTFramesetter 대신 수동 줄 레이아웃(점 텍스트는 래핑 없음 → 결정적·테스트 용이).
   `SceneRenderer.render(TextNode)`도 줄별 그리기로 변경.
5. **`SceneRenderer.render(_:in:excluding:)`** — 편집 중 노드를 렌더에서 제외하는
   옵셔널 `Set<NodeID>` 파라미터(기본 빈 셋).

## 5. 앱 변경

1. **`TextEditingSession`** (`Canvas/TextEditingSession.swift`) — `NSTextView`를
   CanvasView 서브뷰로 노드 위치에 올린다. 폰트/크기/색 동기화, 멀티라인
   (Enter=줄바꿈), 한글 IME·캐럿·선택 네이티브. 스크롤뷰 magnification에 서브뷰가
   함께 스케일 → WYSIWYG.
2. **`Panels/TextSection.swift`** — 단일 텍스트 선택 시 표시: 폰트 패밀리
   Picker(`NSFontManager.availableFontFamilies`) + 크기 필드 + 색 well.
   `store.updateSelectedTextNodes` transient/commit로 undo 1단계. `InspectorView`가
   `selectionPathStyle`(패스) vs 텍스트 선택을 분기.
3. **`ToolKind.text` 와이어링** — koreanName "텍스트", symbol `textformat`, 단축키
   `t`, 툴바 버튼(`allCases` 자동), `iBeam` 커서 매핑.
4. **CanvasView 통합** — `TextEditingSession?` 보유, `requestTextEditing` 클로저 제공,
   세션 활성 중 mouseDown은 먼저 확정 후 처리, 도구 전환/창 비활성 시 확정,
   `draw`에서 편집 노드 `excluding`. **SelectTool 더블클릭**(clickCount==2)도 편집 진입.

## 6. 편집 라이프사이클 & undo

- **생성**: text 도구 → 빈 곳 클릭 → 빈 NSTextView. 입력 후 확정 → 비어있지 않으면
  `appendNodeToActiveLayer` 1단계 + 새 노드 선택. 비어있으면 노드 미생성.
- **편집**: text 도구로 기존 텍스트 클릭 또는 SelectTool 더블클릭 → 시드된 세션,
  모델 노드 숨김(`excluding`). 확정 → `commitTextEdit` 1단계. 노드 다시 표시.
- **확정 트리거**: Esc / 바깥 클릭 / 도구 전환 / 창 비활성.

### 확정된 동작 결정

- (a) **Esc = 현재 텍스트 확정**(Illustrator식). 별도 "취소=원복"은 없음 — 되돌리기는 undo.
- (b) **확정 시 빈 문자열** → 생성이면 미생성, 편집이면 **노드 삭제**(빈 텍스트 잔존 방지).
- (c) **SelectTool 더블클릭**으로도 텍스트 편집 진입.

### 좌표·렌더·변형 한계

- flipped 뷰(모델=뷰 좌표). NSTextView 프레임 origin은 노드 baseline → top 보정
  (첫 줄 ascent만큼 위로). magnification은 서브뷰가 자동 스케일.
- 신규 텍스트는 transform=identity. 회전/스케일된(임포트) 텍스트는 오버레이를
  축정렬 위치에 띄워 **문자열만** 수정(완전 변형 편집은 범위 외).

## 7. 테스트 전략

**엔진** (`swift test`, AppKit-free):
- `TextTool` 생성/편집 판정 — `ToolContext`에 캡처 클로저 주입, 텍스트 위 클릭=
  `.edit(id)`, 빈 곳=`.create(at:)`.
- `updateTextNode` / `commitTextEdit` — 문자열 치환, undo 1단계, 빈 문자열 동작(b).
- `updateSelectedTextNodes` — 폰트/크기/색 변경, transient→commit undo 1단계.
- 멀티라인 `TextRendering.bounds` — `\n` 분할(폭=최대, 높이=합), 빈/0크기 가드,
  단일 줄 회귀.
- 네이티브 .ai 저장 Codable 라운드트립에서 멀티라인 문자열 보존.

**앱** (앱 타깃 테스트 하니스 없음 → 빌드 + 수동 GUI 체크):
- 생성·편집·멀티라인·인스펙터(폰트/크기/색)·undo·저장 후 재열기.

## 8. 파일 영향 요약

**엔진 — 신규**: `Tools/TextTool.swift`, `Tools/TextEditRequest.swift`
**엔진 — 수정**: `Tools/CanvasEvent.swift`(CursorKind.iBeam, ToolKind.text),
`Tools/CanvasTool.swift`(ToolContext.requestTextEditing), `Tools/ToolKind+Factory.swift`,
`Rendering/TextRendering.swift`(멀티라인), `Rendering/SceneRenderer.swift`(멀티라인·excluding),
`Model/VectorDocument+Editing.swift`(updateTextNode), `State/DocumentStore*.swift`(commitTextEdit·updateSelectedTextNodes)
**앱 — 신규**: `Canvas/TextEditingSession.swift`, `Panels/TextSection.swift`
**앱 — 수정**: `Canvas/CanvasView.swift`, `Canvas/ToolState.swift`,
`Panels/InspectorView.swift`, `README.md`(상태 체크박스)

> MainMenuBuilder는 변경 없음 — 텍스트는 명령이 아니라 도구이므로 툴바·단축키(`t`)로만
> 노출한다(다른 도구와 동일).
