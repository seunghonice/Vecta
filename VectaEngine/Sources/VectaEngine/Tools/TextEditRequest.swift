import CoreGraphics

/// 텍스트 편집 요청 — 새로 생성(빈 영역 클릭)하거나 기존 노드를 편집한다.
public enum TextEditRequest: Equatable, Sendable {
  case create(at: CGPoint)
  case edit(NodeID)
}
