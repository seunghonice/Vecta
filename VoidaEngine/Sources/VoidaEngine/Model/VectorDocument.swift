import CoreGraphics

public struct Artboard: Equatable, Codable, Sendable {
  public var size: CGSize

  public init(size: CGSize) {
    self.size = size
  }
}

public struct VectorDocument: Equatable, Codable, Sendable {
  public var artboard: Artboard
  public var layers: [Layer]

  public init(artboard: Artboard, layers: [Layer]) {
    self.artboard = artboard
    self.layers = layers
  }

  /// 기본 크기는 A4 (포인트 단위).
  public static func empty(size: CGSize = CGSize(width: 595, height: 842)) -> VectorDocument {
    VectorDocument(
      artboard: Artboard(size: size),
      layers: [Layer(name: "레이어 1")])
  }
}
