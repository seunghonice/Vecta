import CoreGraphics

/// 인스펙터 스타일 명령 (스펙 §8). 그룹 선택은 패스 자손 전체에 적용된다.
extension DocumentStore {
  /// 인스펙터 표시용 대표 스타일 — 선택의 최전면 패스 노드 기준.
  public var selectionPathStyle: Style? {
    document.frontmostPathNode(in: selection)?.style
  }

  /// 선택된 패스 노드의 스타일을 일괄 변경한다 (apply 1회 = undo 1단계).
  /// 클로저의 localBounds는 각 노드의 로컬 패스 바운드 — 그라디언트 기본
  /// 선분 계산용 (그라디언트 좌표는 객체 로컬 — 스펙 §4).
  public func updateSelectionStyles(
    actionName: String, _ change: @escaping (inout Style, _ localBounds: CGRect) -> Void
  ) {
    let ids = selection
    guard !ids.isEmpty else { return }
    apply(actionName: actionName) { document in
      document.updatePathNodes(ids: ids) { pathNode in
        change(&pathNode.style, pathNode.path.bounds)
      }
    }
  }

  /// 드래그 제스처용 미리보기 — begin/commitTransient 사이에서 undo 등록
  /// 없이 스타일을 갱신한다 (불투명도·스톱 위치 슬라이더).
  public func updateSelectionStylesTransient(
    _ change: @escaping (inout Style, _ localBounds: CGRect) -> Void
  ) {
    let ids = selection
    guard !ids.isEmpty else { return }
    updateTransient { document in
      document.updatePathNodes(ids: ids) { pathNode in
        change(&pathNode.style, pathNode.path.bounds)
      }
    }
  }
}
