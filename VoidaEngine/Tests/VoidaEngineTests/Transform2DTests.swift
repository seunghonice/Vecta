import CoreGraphics
import Foundation
import Testing

@testable import VoidaEngine

@Test func transform2DIdentity() {
  #expect(Transform2D.identity.cgAffineTransform == .identity)
}

@Test func transform2DCGConversionRoundTrip() {
  let cg = CGAffineTransform(translationX: 10, y: 20).rotated(by: .pi / 4)
  let roundTripped = Transform2D(cg).cgAffineTransform
  #expect(abs(roundTripped.a - cg.a) < 1e-12)
  #expect(abs(roundTripped.b - cg.b) < 1e-12)
  #expect(abs(roundTripped.c - cg.c) < 1e-12)
  #expect(abs(roundTripped.d - cg.d) < 1e-12)
  #expect(abs(roundTripped.tx - cg.tx) < 1e-12)
  #expect(abs(roundTripped.ty - cg.ty) < 1e-12)
}

@Test func transform2DCodableRoundTrip() throws {
  let original = Transform2D(CGAffineTransform(scaleX: 2, y: 3))
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(Transform2D.self, from: data)
  #expect(decoded == original)
}
