import Foundation

/// 씬그래프 노드 식별자. 선택 상태는 모델 밖에서 `Set<NodeID>`로 관리한다.
public struct NodeID: Hashable, Codable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}
