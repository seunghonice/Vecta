import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

private func sampleDocument() -> VectorDocument {
  let rect = PathNode(
    path: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 30)),
    style: .defaultShape)
  let group = GroupNode(children: [
    .path(
      PathNode(
        path: .ellipse(in: CGRect(x: 0, y: 0, width: 20, height: 20)),
        style: Style(fill: .color(.black))))
  ])
  let layer = Layer(name: "레이어 1", nodes: [.path(rect), .group(group)])
  return VectorDocument(
    artboard: Artboard(size: CGSize(width: 400, height: 300)),
    layers: [layer])
}

@Test func documentCodableRoundTripPreservesNestedTree() throws {
  let original = sampleDocument()
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(VectorDocument.self, from: data)
  #expect(decoded == original)
}

@Test func nodeExposesUnifiedID() {
  let pathNode = PathNode(
    path: .rectangle(.zero), style: Style())
  #expect(Node.path(pathNode).id == pathNode.id)
}

@Test func emptyDocumentHasOneVisibleUnlockedLayer() {
  let document = VectorDocument.empty(size: CGSize(width: 100, height: 100))
  #expect(document.layers.count == 1)
  #expect(document.layers[0].isVisible)
  #expect(!document.layers[0].isLocked)
  #expect(document.layers[0].nodes.isEmpty)
  #expect(document.artboard.size == CGSize(width: 100, height: 100))
}

@Test func emptyDocumentDefaultSizeIsA4() {
  let document = VectorDocument.empty()
  #expect(document.artboard.size == CGSize(width: 595, height: 842))
}
