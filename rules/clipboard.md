---
updatedAt: 2026-06-13 20:37 KST
---

# 클립보드 (복사/잘라내기/붙여넣기/복제)

선택 노드를 복사·잘라내기·붙여넣기·복제한다 (스펙 §8, ⌘C/⌘X/⌘V/⌘D).

- 직렬화: `NodeClipboard.encode([Node]) -> Data?` / `decode(Data) -> [Node]?`
- 식별자: `NodeClipboard.pasteboardType = "dev.vecta.nodes"`
- ID 재발급: `Node.withFreshIDs()`
- 스토어: `copyableSelection()`, `pasteNodes(_:offset:)`, `duplicateSelection()`
- 위치: `VectaEngine/.../Model/NodeClipboard.swift`,
  `State/DocumentStore+Clipboard.swift`; 앱은 `VectaApp/.../Document/VectaDocument.swift`

## 레이어 책임 분리 (반드시 유지)

엔진은 **AppKit 비의존**이다. 엔진은 `[Node] ↔ Data`(Codable JSON) 직렬화와
노드 추가만 담당하고, **NSPasteboard I/O는 앱**(`VectaDocument`)이 커스텀 타입으로
읽고 쓴다. 엔진에 `NSPasteboard`를 들이지 말 것.

## ID·오프셋·선택

- `withFreshIDs()`는 **모든 NodeID를 새로 발급**(그룹 자식까지 재귀)하고
  지오메트리·스타일·transform은 보존한다 — 붙여넣기/복제 시 원본 ID 충돌 방지.
- `pasteNodes`/`duplicateSelection`은 **+10,+10 오프셋**으로 추가하고 새 노드를 선택.
- `copyableSelection()`은 선택을 **문서 z-순서**로 반환(선택 순서 무관).

## 불변식

- **활성 레이어가 숨김/잠금이면 paste/duplicate는 조용히 무시**(생성 경로와 동일 규칙).
- **빈 입력은 no-op**.
- **단일 undo 단계** — `duplicateSelection`은 `apply` 1회 안에서 추가하고, 새 선택
  ID를 `DocumentStore.pendingSelection`(apply 클로저 내부→외부 전달용 버퍼)로 넘긴다.
  이 버퍼는 단일 동기 `apply` 호출 내에서만 유효하다(클로저 안 재진입 금지).

## 앱 액션 셀렉터 (중요)

- `copy:`/`cut:`/`paste:`는 **표준 셀렉터 이름 유지** — 텍스트필드 포커스 시 응답
  체인이 NSText로 먼저 라우팅돼 텍스트 ⌘C/⌘V가 동작한다. 개명 금지.
- 복제 액션은 `duplicate(_:)`가 아니라 **`duplicateSelection(_:)`** — `NSDocument`의
  문서 복제 셀렉터와 충돌(#selector 모호·타이틀바 동작 하이재킹)을 피한다.
- 일반 AppKit 규칙은 전역 `~/.claude/rules/swift/appkit.md` 참고.

## 현재 제약 (후속 백로그)

- `cut`은 `deleteSelection`을 거치는데 잠긴/숨김 레이어 노드도 제거된다(paste/duplicate와
  비대칭). 선택 정책 정리 시 함께 처리.
- 다중 레이어 선택 paste/duplicate는 전부 활성 레이어로 모이며 원본 레이어/z-위치는
  보존되지 않는다.
- 클립보드 페이로드에 버전 봉투가 없다 — Node Codable에 **필수 필드 추가 금지**,
  신규 필드는 `decodeIfPresent`+기본값으로 추가해 하위 호환 유지.
