import CoreGraphics
import Testing

@testable import VectaEngine

@Test func colorSpaceNamesMap() {
  #expect(PDFColorSpace.named("DeviceRGB") == .deviceRGB)
  #expect(PDFColorSpace.named("CalRGB") == .deviceRGB)
  #expect(PDFColorSpace.named("DeviceGray") == .deviceGray)
  #expect(PDFColorSpace.named("CalGray") == .deviceGray)
  #expect(PDFColorSpace.named("DeviceCMYK") == .deviceCMYK)
  #expect(PDFColorSpace.named("Pattern") == .pattern)
  #expect(PDFColorSpace.named("ICCBased") == .unsupported(name: "ICCBased"))
}

@Test func grayConvertsToEqualChannels() {
  #expect(
    PDFColorSpace.deviceGray.color(from: [0.5])
      == RGBA(red: 0.5, green: 0.5, blue: 0.5))
}

@Test func rgbPassesThrough() {
  #expect(
    PDFColorSpace.deviceRGB.color(from: [0.1, 0.2, 0.3])
      == RGBA(red: 0.1, green: 0.2, blue: 0.3))
}

@Test func cmykConvertsNaively() {
  // r = (1−c)(1−k): 시안(1,0,0,0) → (0,1,1), 검정(0,0,0,1) → (0,0,0)
  #expect(
    PDFColorSpace.deviceCMYK.color(from: [1, 0, 0, 0]) == RGBA(red: 0, green: 1, blue: 1))
  #expect(
    PDFColorSpace.deviceCMYK.color(from: [0, 0, 0, 1]) == RGBA(red: 0, green: 0, blue: 0))
}

@Test func insufficientComponentsReturnNil() {
  #expect(PDFColorSpace.deviceRGB.color(from: [0.5]) == nil)
  #expect(PDFColorSpace.pattern.color(from: []) == nil)
}
