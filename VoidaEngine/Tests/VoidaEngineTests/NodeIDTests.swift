import Foundation
import Testing

@testable import VoidaEngine

@Test func nodeIDCodableRoundTrip() throws {
  let original = NodeID()
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(NodeID.self, from: data)
  #expect(decoded == original)
}
