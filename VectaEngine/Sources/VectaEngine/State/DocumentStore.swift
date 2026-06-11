import Combine
import CoreGraphics
import Foundation

/// 모든 모델 변경의 단일 경로. @MainActor로 강제된다 (스펙 9절).
///
/// undo는 스냅샷 방식: apply 1회 = undo 1단계. 드래그 중에는 호출하지 말고
/// 제스처가 끝나는 시점(mouseUp)에 1회 호출한다.
@MainActor
public final class DocumentStore: ObservableObject {
  @Published public private(set) var document: VectorDocument
  @Published public private(set) var selection: Set<NodeID> = []
  /// 새 노드가 추가되는 레이어 (레이어 패널에서 선택). ID 기반이라 순서
  /// 변경·삭제에도 안정적이며, 사라지면 첫 레이어(0)로 폴백한다.
  @Published public private(set) var activeLayerID: NodeID?

  private let undoManagerProvider: () -> UndoManager?
  private var transientBase: VectorDocument?

  public init(
    document: VectorDocument,
    undoManagerProvider: @escaping () -> UndoManager? = { nil }
  ) {
    self.document = document
    self.undoManagerProvider = undoManagerProvider
  }

  public func apply(actionName: String, _ change: (inout VectorDocument) -> Void) {
    // 드래그 중 외부 개입(undo·삭제 등) 방어: 진행 중 제스처를 취소하고 적용한다.
    if transientBase != nil {
      cancelTransient()
    }
    var updated = document
    change(&updated)
    guard updated != document else { return }
    registerUndo(restoring: document, actionName: actionName)
    document = updated
    selection = selection.intersection(updated.topLevelNodeIDs)
  }

  /// 파일 열기 등 undo 대상이 아닌 전체 교체.
  public func load(_ newDocument: VectorDocument) {
    transientBase = nil
    document = newDocument
    selection = []
    activeLayerID = nil
    undoManagerProvider()?.removeAllActions()
  }

  // MARK: - 활성 레이어

  public var activeLayerIndex: Int {
    guard let activeLayerID,
      let index = document.layers.firstIndex(where: { $0.id == activeLayerID })
    else { return 0 }
    return index
  }

  public func setActiveLayer(id: NodeID) {
    guard document.layers.contains(where: { $0.id == id }) else { return }
    activeLayerID = id
  }

  /// 도구 생성 경로 — 활성 레이어에 노드를 추가한다.
  /// 활성 레이어가 잠겨 있거나 숨겨져 있으면 조용히 무시한다 (Illustrator 동작).
  public func appendNodeToActiveLayer(_ node: Node, actionName: String) {
    let index = activeLayerIndex
    guard document.layers.indices.contains(index) else { return }
    let layer = document.layers[index]
    guard layer.isVisible, !layer.isLocked else { return }
    apply(actionName: actionName) { $0.layers[index].nodes.append(node) }
  }

  // MARK: - 선택

  public func select(_ ids: Set<NodeID>) {
    selection = ids.intersection(document.topLevelNodeIDs)
  }

  public func toggleSelection(_ id: NodeID) {
    guard document.topLevelNodeIDs.contains(id) else { return }
    if selection.contains(id) {
      selection.remove(id)
    } else {
      selection.insert(id)
    }
  }

  public func clearSelection() {
    selection = []
  }

  /// 선택된 최상위 노드 바운드의 합집합 (선택 없으면 nil).
  /// `selection`과 `document` 양쪽에 의존하는 계산 프로퍼티 — 변화 감지는
  /// 두 @Published를 구독한다.
  public var selectionBounds: CGRect? {
    let rects = selection.compactMap { document.topLevelNode(id: $0)?.bounds }
    guard let first = rects.first else { return nil }
    return rects.dropFirst().reduce(first) { $0.union($1) }
  }

  public func deleteSelection() {
    guard !selection.isEmpty else { return }
    let ids = selection
    apply(actionName: "삭제") { $0.removeTopLevelNodes(ids: ids) }
  }

  // MARK: - Transient 변경 (드래그 제스처 미리보기)

  /// 드래그 시작. 이후 updateTransient는 이 시점 문서를 베이스로 한 절대
  /// 변경을 적용한다 (호출마다 누적되지 않음).
  public func beginTransient() {
    assert(transientBase == nil, "이미 transient 변경이 진행 중")
    transientBase = document
  }

  /// undo 등록 없이 문서를 갱신·발행한다.
  /// 세션이 없으면 무시한다 — 제스처 중 외부 개입(undo·load 등)으로 세션이
  /// 파기된 뒤 도구가 계속 드래그 이벤트를 보내는 정상 경로다.
  public func updateTransient(_ change: (inout VectorDocument) -> Void) {
    guard var base = transientBase else { return }
    change(&base)
    document = base
  }

  /// 제스처 종료 — 베이스 대비 변경이 있으면 undo 1단계 등록.
  public func commitTransient(actionName: String) {
    guard let base = transientBase else { return }
    transientBase = nil
    guard document != base else { return }
    registerUndo(restoring: base, actionName: actionName)
    // transient 변경이 노드 추가/삭제를 포함해도 안전하도록 정리.
    selection = selection.intersection(document.topLevelNodeIDs)
  }

  /// 제스처 취소 — 베이스로 복원.
  public func cancelTransient() {
    guard let base = transientBase else { return }
    transientBase = nil
    document = base
  }

  private func registerUndo(restoring snapshot: VectorDocument, actionName: String) {
    guard let undoManager = undoManagerProvider() else { return }
    undoManager.registerUndo(withTarget: self) { store in
      // undo 실행은 항상 메인 런루프에서 일어난다.
      // apply를 재사용하므로 undo 실행이 redo 등록까지 처리한다.
      MainActor.assumeIsolated {
        store.apply(actionName: actionName) { $0 = snapshot }
      }
    }
    undoManager.setActionName(actionName)
  }
}
