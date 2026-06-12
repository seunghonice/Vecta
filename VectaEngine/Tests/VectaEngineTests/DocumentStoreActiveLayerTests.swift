import CoreGraphics
import Foundation
import Testing

@testable import VectaEngine

@MainActor
private func makeTwoLayerStore() -> DocumentStore {
  var document = VectorDocument.empty(size: CGSize(width: 300, height: 300))
  document.layers.append(Layer(name: "레이어 2"))
  return DocumentStore(document: document)
}

private func redRect() -> Node {
  .path(
    PathNode(
      path: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)),
      style: Style(fill: .color(.black))))
}

@Test @MainActor func defaultActiveLayerIndexIsZero() {
  let store = makeTwoLayerStore()
  #expect(store.activeLayerIndex == 0)
}

@Test @MainActor func setActiveLayerByID() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  #expect(store.activeLayerIndex == 1)
}

@Test @MainActor func setActiveLayerIgnoresUnknownID() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: NodeID())
  #expect(store.activeLayerIndex == 0)
}

@Test @MainActor func activeLayerFallsBackWhenLayerRemoved() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  store.apply(actionName: "레이어 삭제") { $0.layers.remove(at: 1) }
  #expect(store.activeLayerIndex == 0)
}

@Test @MainActor func appendNodeGoesToActiveLayer() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  store.appendNodeToActiveLayer(redRect(), actionName: "도형 추가")
  #expect(store.document.layers[0].nodes.isEmpty)
  #expect(store.document.layers[1].nodes.count == 1)
}

@Test @MainActor func appendNodeIgnoredOnLockedLayer() {
  let store = makeTwoLayerStore()
  store.apply(actionName: "잠금") { $0.layers[0].isLocked = true }
  store.appendNodeToActiveLayer(redRect(), actionName: "도형 추가")
  #expect(store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func appendNodeIgnoredOnHiddenLayer() {
  let store = makeTwoLayerStore()
  store.apply(actionName: "숨김") { $0.layers[0].isVisible = false }
  store.appendNodeToActiveLayer(redRect(), actionName: "도형 추가")
  #expect(store.document.layers[0].nodes.isEmpty)
}

@Test @MainActor func loadResetsActiveLayer() {
  let store = makeTwoLayerStore()
  store.setActiveLayer(id: store.document.layers[1].id)
  store.load(.empty())
  #expect(store.activeLayerIndex == 0)
}
