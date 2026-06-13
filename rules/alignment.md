---
updatedAt: 2026-06-13 20:37 KST
---

# 정렬 (Alignment)

선택된 최상위 노드들을 선택 바운드 기준으로 정렬한다 (스펙 §8).

- 정의: `AlignEdge`(`.left`/`.centerHorizontal`/`.right`/`.top`/`.centerVertical`/`.bottom`)
- 엔진: `VectorDocument.alignTopLevelNodes(ids:edge:within:)`
- 스토어: `DocumentStore.alignSelection(edge:)`
- 위치: `VectaEngine/Sources/VectaEngine/Model/NodeAlignment.swift`,
  `State/DocumentStore+Align.swift`

## 좌표계 (반드시 유지)

모델은 **y-아래 좌표계**다. 따라서 **top = 최소 y**, **bottom = 최대 y**.
정렬 기준 바운드는 `DocumentStore.selectionBounds`(선택 노드 bounds의 union).

## 축 분리

- 가로 기준(`left`/`centerHorizontal`/`right`)은 **x축만** 이동.
- 세로 기준(`top`/`centerVertical`/`bottom`)은 **y축만** 이동.
- 이동은 `NodeTransformer.translated(_:by:)`로 수행.

## 불변식

- **노드 2개 미만이면 no-op** (`ids.count >= 2` 가드).
- **단일 undo 단계** — `apply` 1회.
