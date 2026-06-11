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
    var updated = document
    change(&updated)
    guard updated != document else { return }
    registerUndo(restoring: document, actionName: actionName)
    document = updated
    selection = selection.intersection(updated.topLevelNodeIDs)
  }

  /// 파일 열기 등 undo 대상이 아닌 전체 교체.
  public func load(_ newDocument: VectorDocument) {
    document = newDocument
    selection = []
    undoManagerProvider()?.removeAllActions()
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

  /// undo 등록 없이 문서를 갱신·발행한다. begin 없이 호출하면 무시.
  public func updateTransient(_ change: (inout VectorDocument) -> Void) {
    guard var base = transientBase else {
      assertionFailure("beginTransient 없이 updateTransient 호출")
      return
    }
    change(&base)
    document = base
  }

  /// 제스처 종료 — 베이스 대비 변경이 있으면 undo 1단계 등록.
  public func commitTransient(actionName: String) {
    guard let base = transientBase else { return }
    transientBase = nil
    guard document != base else { return }
    registerUndo(restoring: base, actionName: actionName)
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
