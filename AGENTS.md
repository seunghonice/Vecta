---
updatedAt: 2026-06-13 20:37 KST
---

# Vecta 프로젝트 규칙 인덱스

Vecta(macOS 벡터 드로잉 앱)의 프로젝트 전용 규칙 인덱스. 상세는 모두
`rules/*.md`에 있고, 여기는 **한 줄 요약 + 링크**만 둔다(인덱스 전용).
범용 Swift/AppKit 규칙은 전역 `~/.claude/rules/swift/`에 있으며 여기 링크하지 않는다.

구조: 엔진(`VectaEngine`, AppKit 비의존 순수 모델/상태)에 TDD로 연산·명령을
추가하고, 앱(`VectaApp`)이 인스펙터·메뉴·NSPasteboard로 노출한다. 모든 모델 변경은
`DocumentStore.apply`(스냅샷 = undo 1단계) 단일 경로를 거친다.

## 선택 조작 (M5a)

- **패스파인더** — 선택 패스 불린 연산(합치기·빼기·교차·제외), 결과 1개 치환·스타일/자리=최하단 → [rules/pathfinder.md](rules/pathfinder.md)
- **정렬** — 선택 바운드 기준 6종, y-아래 좌표계 → [rules/alignment.md](rules/alignment.md)
- **클립보드** — 엔진 Codable 직렬화 ↔ 앱 NSPasteboard, `withFreshIDs`·단일 undo → [rules/clipboard.md](rules/clipboard.md)
