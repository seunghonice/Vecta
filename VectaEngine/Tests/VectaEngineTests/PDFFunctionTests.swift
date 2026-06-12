import CoreGraphics
import Testing

@testable import VectaEngine

private func expectClose(
  _ values: [CGFloat], _ expected: [CGFloat],
  sourceLocation: SourceLocation = #_sourceLocation
) {
  #expect(values.count == expected.count, sourceLocation: sourceLocation)
  for (actual, want) in zip(values, expected) {
    #expect(abs(actual - want) < 0.0001, sourceLocation: sourceLocation)
  }
}

@Test func exponentialLinearInterpolates() {
  let function = PDFFunction.exponential(
    c0: [0], c1: [1], exponent: 1, domain: 0...1)
  expectClose(function.evaluate(0), [0])
  expectClose(function.evaluate(0.5), [0.5])
  expectClose(function.evaluate(1), [1])
}

@Test func exponentialNonLinearUsesExponent() {
  let function = PDFFunction.exponential(
    c0: [0], c1: [1], exponent: 2, domain: 0...1)
  expectClose(function.evaluate(0.5), [0.25])
}

@Test func exponentialMultiComponentRGB() {
  let function = PDFFunction.exponential(
    c0: [1, 0, 0], c1: [0, 0, 1], exponent: 1, domain: 0...1)
  expectClose(function.evaluate(0.5), [0.5, 0, 0.5])
}

@Test func evaluateClampsToDomain() {
  let function = PDFFunction.exponential(
    c0: [0.2], c1: [0.8], exponent: 1, domain: 0...1)
  expectClose(function.evaluate(-1), [0.2])
  expectClose(function.evaluate(2), [0.8])
}

@Test func stitchingRoutesToSubinterval() {
  // 두 구간 [0,0.5)→f0, [0.5,1]→f1. 각 encode 0…1.
  let f0 = PDFFunction.exponential(c0: [0], c1: [1], exponent: 1, domain: 0...1)
  let f1 = PDFFunction.exponential(c0: [0], c1: [2], exponent: 1, domain: 0...1)
  let stitch = PDFFunction.stitching(
    functions: [f0, f1], bounds: [0.5],
    encode: [(0, 1), (0, 1)], domain: 0...1)
  // t=0.25 → f0의 입력 0.5 → 0.5
  expectClose(stitch.evaluate(0.25), [0.5])
  // t=0.75 → f1의 입력 0.5 → 1.0
  expectClose(stitch.evaluate(0.75), [1.0])
}

@Test func stitchingReversedEncodeMapsBackwards() {
  let f0 = PDFFunction.exponential(c0: [0], c1: [1], exponent: 1, domain: 0...1)
  let stitch = PDFFunction.stitching(
    functions: [f0], bounds: [], encode: [(1, 0)], domain: 0...1)
  // 단일 구간 [0,1] → encode (1,0): t=0 → 입력 1 → 1.0
  expectClose(stitch.evaluate(0), [1.0])
  expectClose(stitch.evaluate(1), [0.0])
}

@Test func sampleStopsProducesEvenlySpacedStops() {
  let function = PDFFunction.exponential(
    c0: [1, 0, 0], c1: [0, 0, 1], exponent: 1, domain: 0...1)
  let stops = function.sampleStops(count: 3, colorSpace: .deviceRGB, domain: 0...1)
  #expect(stops.count == 3)
  #expect(stops[0].location == 0)
  #expect(stops[1].location == 0.5)
  #expect(stops[2].location == 1)
  #expect(stops[0].color == RGBA(red: 1, green: 0, blue: 0))
  #expect(stops[2].color == RGBA(red: 0, green: 0, blue: 1))
}

@Test func sampleStopsSkipsComponentMismatch() {
  // RGB 색공간(3성분)인데 함수가 1성분 → 색 변환 실패로 모든 스톱 제외
  let function = PDFFunction.exponential(c0: [0], c1: [1], exponent: 1, domain: 0...1)
  let stops = function.sampleStops(count: 3, colorSpace: .deviceRGB, domain: 0...1)
  #expect(stops.isEmpty)
}

@Test func exponentialNegativeDomainFractionalExponentStaysFinite() {
  // 음수 도메인 + 분수 지수 — NaN 없이 유한값 (base 0 클램프)
  let function = PDFFunction.exponential(
    c0: [0], c1: [1], exponent: 2.5, domain: -1...1)
  let value = function.evaluate(-0.5)
  #expect(value.count == 1)
  #expect(value[0].isFinite)
  #expect(value[0] == 0)  // pow(max(-0.5,0)=0, 2.5)=0 → c0
}
