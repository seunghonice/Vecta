import Foundation

/// 노드 클립보드 직렬화 (스펙 §8). 엔진은 AppKit 비의존이므로 NSPasteboard
/// I/O는 앱이 담당하고, 여기서는 `[Node]` ↔ `Data`(JSON)만 다룬다.
public enum NodeClipboard {
  /// 앱이 NSPasteboard 커스텀 타입을 만들 때 쓰는 식별자.
  public static let pasteboardType = "dev.vecta.nodes"

  public static func encode(_ nodes: [Node]) -> Data? {
    try? JSONEncoder().encode(nodes)
  }

  public static func decode(_ data: Data) -> [Node]? {
    try? JSONDecoder().decode([Node].self, from: data)
  }
}

extension Node {
  /// 모든 NodeID를 새로 발급한 복제본 (그룹 자식까지 재귀). 붙여넣기·복제에서
  /// 원본과의 ID 충돌을 막는다. 지오메트리·스타일·transform은 그대로 유지.
  public func withFreshIDs() -> Node {
    switch self {
    case .path(let node):
      return .path(
        PathNode(
          path: node.path, style: node.style,
          transform: node.transform, fillRule: node.fillRule))
    case .group(let node):
      return .group(
        GroupNode(
          children: node.children.map { $0.withFreshIDs() },
          clipPath: node.clipPath, transform: node.transform))
    case .text(let node):
      return .text(
        TextNode(
          string: node.string, fontName: node.fontName, fontSize: node.fontSize,
          fill: node.fill, position: node.position, transform: node.transform))
    case .image(let node):
      return .image(
        ImageNode(
          imageData: node.imageData, frame: node.frame, transform: node.transform))
    }
  }
}
