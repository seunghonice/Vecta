import Testing

@testable import VectaEngine

@Test @MainActor func everyToolKindMakesMatchingTool() {
  // 망라 switch라 케이스 추가 시 컴파일 에러로 강제되지만,
  // 런타임 타입 매핑도 회귀 방지로 고정한다.
  #expect(ToolKind.select.makeTool() is SelectTool)
  #expect(ToolKind.directSelect.makeTool() is DirectSelectTool)
  #expect(ToolKind.pen.makeTool() is PenTool)
  #expect(ToolKind.rectangle.makeTool() is ShapeTool)
  #expect(ToolKind.ellipse.makeTool() is ShapeTool)
  #expect(ToolKind.allCases.count == 5)
}
