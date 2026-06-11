import CoreGraphics

/// 캔버스 도구 상태 머신. 모든 좌표는 모델 좌표 (스펙 §7).
@MainActor
public protocol CanvasTool: AnyObject {
  var cursorKind: CursorKind { get }
  func mouseDown(_ event: CanvasEvent, context: ToolContext)
  func mouseDragged(_ event: CanvasEvent, context: ToolContext)
  func mouseUp(_ event: CanvasEvent, context: ToolContext)
  /// 처리했으면 true (미처리 키는 캔버스가 다음 응답자로 넘긴다).
  func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool
  /// 버튼 누르지 않은 이동 (펜 러버밴드 등). 기본 구현은 no-op.
  func mouseMoved(_ event: CanvasEvent, context: ToolContext)
  /// 모델 좌표 컨텍스트에 오버레이를 그린다. scale은 화면 확대 배율 —
  /// 핸들 등 화면 고정 크기 요소는 (상수 ÷ scale)로 그린다.
  func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext)
  /// 도구가 비활성화될 때(다른 도구로 전환) 미완 작업을 정리한다.
  /// 기본 구현은 no-op.
  func deactivate(context: ToolContext)
}

extension CanvasTool {
  public func keyDown(_ key: CanvasKey, context: ToolContext) -> Bool { false }
  public func mouseMoved(_ event: CanvasEvent, context: ToolContext) {}
  public func drawOverlay(in cgContext: CGContext, scale: CGFloat, context: ToolContext) {}
  public func deactivate(context: ToolContext) {}
}

/// 도구가 문서·선택에 접근하고 오버레이 리드로우를 요청하는 통로.
@MainActor
public final class ToolContext {
  public let store: DocumentStore
  /// 모델 변경 없이 오버레이만 바뀌었을 때 호출 (모델 변경은 store가 발행).
  public var invalidateOverlay: () -> Void

  public init(store: DocumentStore, invalidateOverlay: @escaping () -> Void = {}) {
    self.store = store
    self.invalidateOverlay = invalidateOverlay
  }
}
