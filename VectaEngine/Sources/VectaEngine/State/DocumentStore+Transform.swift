import CoreGraphics

/// 인스펙터 변환 수치 입력 명령 (스펙 §8 — X/Y/W/H/회전).
extension DocumentStore {
  /// 선택 바운드 원점을 (x, y)로 이동한다. nil 축은 유지.
  public func moveSelection(x: CGFloat? = nil, y: CGFloat? = nil) {
    guard let bounds = selectionBounds else { return }
    let delta = CGVector(
      dx: (x ?? bounds.minX) - bounds.minX,
      dy: (y ?? bounds.minY) - bounds.minY)
    guard delta.dx != 0 || delta.dy != 0 else { return }
    let ids = selection
    apply(actionName: "이동") { document in
      document.updateTopLevelNodes(ids: ids) { NodeTransformer.translated($0, by: delta) }
    }
  }

  /// 선택 바운드 크기를 (width, height)로 — 좌상단 고정. 0 이하 입력은 무시.
  /// 회전된 노드에 비균일 스케일을 적용하면 부모 좌표계 합성으로 전단(shear)이
  /// 생긴다 — 드래그 리사이즈와 동일한 바운드 기준 W/H의 알려진 한계.
  public func resizeSelection(width: CGFloat? = nil, height: CGFloat? = nil) {
    guard let bounds = selectionBounds, bounds.width > 0, bounds.height > 0 else { return }
    if let width, width <= 0 { return }
    if let height, height <= 0 { return }
    let scaleX = (width ?? bounds.width) / bounds.width
    let scaleY = (height ?? bounds.height) / bounds.height
    guard scaleX != 1 || scaleY != 1 else { return }
    let ids = selection
    let anchor = CGPoint(x: bounds.minX, y: bounds.minY)
    apply(actionName: "크기 조절") { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.resized($0, anchor: anchor, scaleX: scaleX, scaleY: scaleY)
      }
    }
  }

  /// 선택 바운드 중심 기준 회전 (도 단위 델타).
  public func rotateSelection(byDegrees degrees: CGFloat) {
    guard degrees != 0, let bounds = selectionBounds else { return }
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let ids = selection
    apply(actionName: "회전") { document in
      document.updateTopLevelNodes(ids: ids) {
        NodeTransformer.rotated($0, around: center, by: degrees * .pi / 180)
      }
    }
  }
}
