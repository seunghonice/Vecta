# M5b 텍스트 도구 (인라인 입력) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: harness-tdd-loop / harness-tdd-iterate 로 태스크 단위 구현. 체크박스(`- [ ]`)로 추적. 상세 설계는 spec 참조(중복 금지): `docs/superpowers/specs/2026-06-14-vecta-m5b-text-tool-design.md`.

**Goal:** 캔버스에 점 텍스트를 인라인으로 생성·편집한다(여러 줄, 한글 IME). text 도구로 빈 곳 클릭=생성, 기존 텍스트 클릭/SelectTool 더블클릭=편집. 폰트 패밀리·크기·색은 인스펙터에서 조절. 생성·편집·서식은 각각 undo 1단계.

**Architecture:** "배치 결정은 엔진, 문자 입력은 AppKit." 엔진 `TextTool`은 클릭이 생성/편집인지만 판정해 `ToolContext.requestTextEditing`(앱-주입 클로저)로 요청. 앱 `CanvasView`가 `NSTextView` 편집 세션을 띄워 IME·캐럿·멀티라인을 네이티브 처리하고, 확정 시 엔진 명령(`appendNodeToActiveLayer`/`commitTextEdit`) 1회로 모델에 반영(=undo 1단계). 서식은 인스펙터 `TextSection`이 `updateSelectedTextNodes`로 적용. 엔진은 AppKit 비의존 유지.

**Tech Stack:** Swift 6, Swift Testing, CoreText(다중 CTLine 측정/렌더), AppKit(NSTextView·NSFontManager·NSCursor), SwiftUI(인스펙터).

---

## File Structure

**엔진 — 신규**
- `VectaEngine/Sources/VectaEngine/Tools/TextEditRequest.swift` — `enum TextEditRequest { case create(at: CGPoint); case edit(NodeID) }`
- `VectaEngine/Sources/VectaEngine/Tools/TextTool.swift` — `TextTool: CanvasTool`

**엔진 — 수정**
- `Tools/CanvasEvent.swift` — `CursorKind.iBeam`, `ToolKind.text`
- `Tools/CanvasTool.swift` — `ToolContext.requestTextEditing: (TextEditRequest) -> Void`(기본 no-op)
- `Tools/ToolKind+Factory.swift` — `.text → TextTool()`
- `Tools/SelectTool.swift` — 더블클릭(clickCount≥2) 텍스트 노드 위 → `requestTextEditing(.edit(id))`
- `Rendering/TextRendering.swift` — `\n` 분할 다중 CTLine: `lines`/`bounds`(폭=최대 줄폭, 높이=Σ 줄높이)
- `Rendering/SceneRenderer.swift` — `render(TextNode)` 줄별 그리기 + `render(_:in:excluding:)` 옵셔널 제외 셋
- `Model/VectorDocument+Editing.swift` — `updateTextNode(id:_:)`
- `State/DocumentStore+Styling.swift`(또는 신규 `+Text.swift`) — `commitTextEdit(id:string:)`, `updateSelectedTextNodes` transient/commit, `selectionTextNode` 헬퍼

**엔진 테스트 — 신규**
- `Tests/VectaEngineTests/TextRenderingTests.swift`
- `Tests/VectaEngineTests/TextToolTests.swift`
- `Tests/VectaEngineTests/TextEditingTests.swift`(updateTextNode·commitTextEdit·updateSelectedTextNodes)

**앱 — 신규**
- `VectaApp/Sources/Canvas/TextEditingSession.swift`
- `VectaApp/Sources/Panels/TextSection.swift`

**앱 — 수정**
- `Canvas/CanvasView.swift` — `requestTextEditing` 클로저, 세션 보유, 확정 트리거, `draw` excluding, iBeam 커서
- `Canvas/ToolState.swift` — `.text` koreanName/symbolName
- `Panels/InspectorView.swift` — 텍스트 선택 시 `TextSection` 분기
- `README.md` — 상태 체크박스

엔진 태스크(T1~T4)는 TDD(RED→GREEN→검증→커밋). 앱 태스크(T5~T7)는 앱 타깃 테스트 하니스 없음 → 빌드 성공 + 수동 GUI 체크. 순서: 순수 측정/로직(T1) → 도구·명령(T2~T4) → UI(T5~T7) → 마감(T8).

---

### Task 1: 멀티라인 텍스트 측정/렌더 (엔진, TDD)
- **action**: `TextRendering.swift` 수정 — `\n` 분할 다중 CTLine; `lines(...)`(줄별 CTLine+오프셋), `bounds(...)` 멀티라인. `SceneRenderer.render(TextNode)` 줄별 그리기. `SceneRenderer.render(_:in:excluding:)` 옵셔널 제외 셋(기본 빈) 추가.
- **계약**: `bounds`는 폭=최대 줄폭, 높이=Σ(ascent+descent+leading), position=첫 줄 baseline. 단일 줄·빈 문자열은 기존 동작 보존.
- **수용기준**: 멀티라인 문자열 bounds가 줄 수에 비례해 커지고 폭은 최장 줄 기준. 단일 줄 회귀 0.
- **테스트 의도**: `"A\nBB\nCCC"` bounds 폭/높이, 단일 줄 회귀, 빈/0크기 가드. (excluding·draw는 빌드+수동.)

### Task 2: 텍스트 도구 + 편집 요청 (엔진, TDD)
- **action**: `TextEditRequest.swift`·`TextTool.swift` 신규; `CanvasEvent.swift`(CursorKind.iBeam·ToolKind.text); `CanvasTool.swift`(ToolContext.requestTextEditing); `ToolKind+Factory.swift`(.text); `SelectTool.swift`(더블클릭 편집 진입).
- **계약**: `TextTool.mouseDown` — 최상위 노드가 TextNode면 `.edit(id)`, 아니면 `.create(at: point)`. `SelectTool.mouseDown` — clickCount≥2 & 텍스트 위면 `.edit(id)`. 둘 다 `context.requestTextEditing` 호출.
- **수용기준**: 텍스트 위 클릭→`.edit`, 빈 곳/비텍스트 위→`.create`. 팩토리 망라 switch 컴파일 통과.
- **테스트 의도**: ToolContext에 캡처 클로저 주입 — TextTool create/edit 분기, SelectTool 더블클릭 edit.

### Task 3: 텍스트 편집 명령 (엔진, TDD)
- **action**: `VectorDocument+Editing.updateTextNode(id:_:)`(`updatePathNode` 미러); `DocumentStore.commitTextEdit(id:string:)`.
- **계약**: `commitTextEdit` — 문자열 치환 후 snapshot 1회(undo 1단계). 빈 문자열이면 해당 노드 삭제(spec §6-b).
- **수용기준**: 문자열 치환 반영, undo 1회로 원복, 빈 문자열 확정 시 노드 제거.
- **테스트 의도**: 치환·undo 단일성·빈 문자열 삭제.

### Task 4: 텍스트 서식 명령 (엔진, TDD)
- **action**: `DocumentStore.updateSelectedTextNodes`(transient/commit, `updateSelectionStyles` 미러) + `selectionTextNode`(단일 텍스트 선택 헬퍼).
- **계약**: 선택된 텍스트 노드의 fontName/fontSize/fill 변경. transient→commit = undo 1단계. `selectionTextNode`는 선택이 단일 TextNode일 때만 반환.
- **수용기준**: 폰트/크기/색 변경 반영, 슬라이더 드래그류는 transient→commit으로 undo 1단계.
- **테스트 의도**: fontName/fontSize/fill 각 변경, transient→commit undo 단일성, 혼합 선택 시 selectionTextNode=nil.

### Task 5: text 도구 앱 와이어링 (앱, 빌드+수동)
- **action**: `ToolState.swift`(.text koreanName "텍스트"·symbol `textformat`); `CanvasView.swift` 단축키 `t`·iBeam 커서 매핑·`requestTextEditing` 클로저(세션은 T6, 우선 스텁/세션 호출).
- **수용기준**: 빌드 성공. 툴바에 텍스트 버튼 노출(allCases 자동), `t` 단축키·iBeam 커서.
- **테스트 의도**: 빌드(`make build`) + 수동 — 도구 전환·커서.

### Task 6: NSTextView 편집 세션 (앱, 빌드+수동)
- **action**: `TextEditingSession.swift` 신규 — `requestTextEditing`에서 생성/편집 세션. NSTextView를 노드 위치(baseline→top 보정)에 서브뷰로, 폰트/크기/색 동기화, 멀티라인. 확정 트리거(Esc/바깥 클릭/도구 전환/창 비활성)→엔진 명령(create=`appendNodeToActiveLayer`, edit=`commitTextEdit`). 편집 중 노드 `excluding`. `CanvasView` 통합.
- **수용기준**: 빌드 성공. 클릭→인라인 입력→확정→렌더, 더블클릭→재편집, 멀티라인, 한글 IME, undo 1단계.
- **테스트 의도**: 빌드 + 수동 GUI 체크리스트.

### Task 7: 텍스트 인스펙터 섹션 (앱, 빌드+수동)
- **action**: `TextSection.swift` 신규 — 폰트 패밀리 Picker(`NSFontManager.availableFontFamilies`)·크기 필드·색 well, `updateSelectedTextNodes` 연결. `InspectorView.swift` 텍스트 선택 분기.
- **수용기준**: 빌드 성공. 텍스트 선택 시 섹션 표시, 폰트/크기/색 변경 반영·undo.
- **테스트 의도**: 빌드 + 수동 — 서식 변경·undo·혼합 선택 시 미표시.

### Task 8: 마감 (문서 + 저장 라운드트립 검증)
- **action**: `README.md` M5b 체크박스. 저장→재열기 멀티라인 보존 수동 검증.
- **수용기준**: `swift test` 전체 통과, `make build` 성공, 저장 후 재열기에서 멀티라인 텍스트 100% 보존.
- **테스트 의도**: 전체 회귀 + 수동 라운드트립.
