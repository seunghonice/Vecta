---
updatedAt: 2026-06-13 20:37 KST
---

# 패스파인더 (Pathfinder)

선택된 최상위 패스들을 불린 연산으로 합쳐 하나의 패스로 치환한다 (스펙 §8).

- 정의: `PathfinderOperation`(`.unite`/`.subtract`/`.intersect`/`.exclude`)
- 엔진: `VectorDocument.combineSelectedPaths(ids:operation:)` → `NodeID?`
- 스토어: `DocumentStore.applyPathfinder(_:)`, UI 활성화 판정용 `combinablePathCount`
- 위치: `VectaEngine/Sources/VectaEngine/Model/Pathfinder.swift`,
  `State/DocumentStore+Pathfinder.swift`

## 좌표·정규화 (반드시 유지)

각 패스를 **자기 transform으로 모델 좌표에 베이크** → **자기 fillRule로
`normalized(using:)` 정규화**(자가교차를 단일 winding 영역으로) → CGPath 불린.
결과는 모델 좌표이므로 새 노드의 `transform = .identity`, `fillRule = .winding`.

## 결과 노드 규칙

- 결과는 **패스 노드 1개**로 치환한다.
- **스타일·z-자리 = 최하단(문서 z-순서 맨 아래) 패스**를 따른다 (의도된 스펙 결정).
  Illustrator는 최전면을 쓰지만 본 프로젝트는 최하단으로 고정 — 바꾸지 말 것.
  비선택 노드가 선택 패스 사이에 끼어 있으면 결과 위에 남는다.
- `subtract`는 `X − A − B = X − (A∪B)` 등가로 `rest.reduce(first) { $0.subtracting($1) }`.
  중간 union을 따로 만들지 말 것(인덱싱 위험·복잡도).

## 불변식

- **패스 2개 미만이면 no-op**, `nil` 반환.
- **비-패스 노드(그룹·텍스트·이미지)는 무시·보존**한다. 삭제 대상은 결합된
  패스만(`ordered`)이며 선택에 섞인 텍스트 등은 지우지 않는다.
- **빈 불린 결과**(겹침 없는 교차·완전 차감)는 보이지 않는 빈 패스 노드를
  남기지 않고 대상 패스를 모두 제거하고 `nil` 반환. 선택은 `apply`가 비운다.
- **단일 undo 단계** — `apply` 1회 안에서 치환+제거.

## 현재 제약 (후속 백로그)

- 잠긴/숨김 레이어에 속한 선택 패스도 결합·삭제될 수 있다(생성/붙여넣기 경로와
  비대칭). 선택 정책 정리 시 함께 처리.
- 다중 레이어 선택 시 결과는 최하단 패스의 레이어로 모인다(`groupTopLevelNodes`와
  동일 규칙).
