import CoreGraphics
import Foundation
import Testing

@testable import VoidaEngine

@Test func styleCodableRoundTrip() throws {
  let original = Style(
    fill: .linearGradient(
      Gradient(
        stops: [
          GradientStop(location: 0, color: .black),
          GradientStop(location: 1, color: .white),
        ],
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: 100, y: 0))),
    stroke: Stroke(paint: .black, width: 2),
    opacity: 0.5)
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(Style.self, from: data)
  #expect(decoded == original)
}

@Test func strokeDefaults() {
  let stroke = Stroke(paint: .black, width: 1)
  #expect(stroke.cap == .butt)
  #expect(stroke.join == .miter)
  #expect(stroke.dash.isEmpty)
}

@Test func defaultShapeStyleHasFillAndStroke() {
  #expect(Style.defaultShape.fill != nil)
  #expect(Style.defaultShape.stroke != nil)
  #expect(Style.defaultShape.opacity == 1)
}
