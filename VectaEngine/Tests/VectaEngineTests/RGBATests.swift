import Foundation
import Testing

@testable import VectaEngine

@Test func rgbaCodableRoundTrip() throws {
  let original = RGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(RGBA.self, from: data)
  #expect(decoded == original)
}

@Test func rgbaDefaultAlphaIsOpaque() {
  #expect(RGBA(red: 1, green: 0, blue: 0).alpha == 1)
}

@Test func rgbaPresetColors() {
  #expect(RGBA.black == RGBA(red: 0, green: 0, blue: 0))
  #expect(RGBA.white == RGBA(red: 1, green: 1, blue: 1))
}
