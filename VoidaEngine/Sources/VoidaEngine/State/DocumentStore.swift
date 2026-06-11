import Combine
import Foundation

/// 모든 모델 변경의 단일 경로. 메인 스레드에서만 사용한다 (스펙 9절).
///
/// undo는 스냅샷 방식: apply 1회 = undo 1단계. 드래그 중에는 호출하지 말고
/// 제스처가 끝나는 시점(mouseUp)에 1회 호출한다.
public final class DocumentStore: ObservableObject {
  @Published public private(set) var document: VectorDocument

  private let undoManagerProvider: () -> UndoManager?

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
  }

  /// 파일 열기 등 undo 대상이 아닌 전체 교체.
  public func load(_ newDocument: VectorDocument) {
    document = newDocument
    undoManagerProvider()?.removeAllActions()
  }

  private func registerUndo(restoring snapshot: VectorDocument, actionName: String) {
    guard let undoManager = undoManagerProvider() else { return }
    undoManager.registerUndo(withTarget: self) { store in
      // apply를 재사용하므로 undo 실행이 redo 등록까지 처리한다.
      store.apply(actionName: actionName) { $0 = snapshot }
    }
    undoManager.setActionName(actionName)
  }
}
