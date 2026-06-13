/// ToolKind ↔ 도구 구현의 동기화를 망라 switch로 컴파일 타임에 강제한다
/// (케이스 추가 시 여기서 컴파일 에러 — M2a 리뷰의 강제 언래핑 지적 해소).
extension ToolKind {
  /// 호출마다 새 인스턴스를 만든다 — 호출자는 1회 생성 후 캐시할 것
  /// (도구는 제스처 상태를 보유한다).
  @MainActor
  public func makeTool() -> CanvasTool {
    switch self {
    case .select: return SelectTool()
    case .directSelect: return DirectSelectTool()
    case .pen: return PenTool()
    case .rectangle: return ShapeTool(shape: .rectangle)
    case .ellipse: return ShapeTool(shape: .ellipse)
    case .text: return TextTool()
    }
  }
}
