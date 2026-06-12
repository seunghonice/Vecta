import CoreGraphics
import Testing

@testable import VectaEngine

/// 픽스처 PDF의 첫 페이지 /Resources/Shading/<name> 객체를 PDFShading으로 파싱한다.
private func parseShadingResource(
  name: String, shadingObject: String,
  mediaBox: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200)
) -> (gradient: Gradient, isRadial: Bool, lossyRadial: Bool)? {
  // sh 한 줄로 셰이딩 리소스를 참조하는 최소 콘텐츠.
  let data = makeTestPDF(
    content: "/\(name) sh",
    mediaBox: mediaBox,
    resources: "<< /Shading << /\(name) 5 0 R >> >>",
    extraObjects: [shadingObject])
  let provider = CGDataProvider(data: data as CFData)!
  let page = CGPDFDocument(provider)!.page(at: 1)!
  let stream = CGPDFContentStreamCreateWithPage(page)
  defer { CGPDFContentStreamRelease(stream) }
  guard let object = CGPDFContentStreamGetResource(stream, "Shading", name) else { return nil }
  return PDFShading.parse(object)
}

private let exponentialFunction =
  "<< /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>"

@Test func parsesAxialShadingToLinearGradient() {
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceRGB "
    + "/Coords [10 20 90 20] /Function \(exponentialFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(!parsed.isRadial)
  #expect(!parsed.lossyRadial)
  #expect(parsed.gradient.start == CGPoint(x: 10, y: 20))
  #expect(parsed.gradient.end == CGPoint(x: 90, y: 20))
  #expect(parsed.gradient.stops.count == 9)  // 9등분 샘플
  #expect(parsed.gradient.stops.first?.color == RGBA(red: 1, green: 0, blue: 0))
  #expect(parsed.gradient.stops.last?.color == RGBA(red: 0, green: 0, blue: 1))
}

@Test func parsesRadialShadingWithEndCircle() {
  // 동심원(c0==c1, r0=0) — 손실 없음
  let shading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB "
    + "/Coords [50 50 0 50 50 40] /Function \(exponentialFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.isRadial)
  #expect(!parsed.lossyRadial)
  #expect(parsed.gradient.start == CGPoint(x: 50, y: 50))  // 끝 원 중심
  #expect(parsed.gradient.end == CGPoint(x: 90, y: 50))  // 중심 + 반지름 40
}

@Test func radialWithNonZeroStartRadiusReportsLossy() {
  let shading =
    "<< /ShadingType 3 /ColorSpace /DeviceRGB "
    + "/Coords [50 50 10 50 50 40] /Function \(exponentialFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.lossyRadial)  // r0=10 ≠ 0 → 근사 손실
}

@Test func stitchingFunctionShadingSamples() {
  let stitch =
    "<< /FunctionType 3 /Domain [0 1] /Bounds [0.5] /Encode [0 1 0 1] "
    + "/Functions [\(exponentialFunction) "
    + "<< /FunctionType 2 /Domain [0 1] /C0 [0 1 0] /C1 [1 1 1] /N 1 >>] >>"
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] /Function \(stitch) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.gradient.stops.count == 9)
}

@Test func unsupportedShadingTypeReturnsNil() {
  // type 1(function-based) 미지원
  let shading =
    "<< /ShadingType 1 /ColorSpace /DeviceRGB /Function \(exponentialFunction) >>"
  #expect(parseShadingResource(name: "Sh0", shadingObject: shading) == nil)
}

@Test func unsupportedFunctionTypeReturnsNil() {
  // function type 0(샘플) 미지원 → shading 파싱도 nil
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 100 0] "
    + "/Function << /FunctionType 0 /Domain [0 1] >> >>"
  #expect(parseShadingResource(name: "Sh0", shadingObject: shading) == nil)
}

@Test func grayColorSpaceShadingConverts() {
  let grayFunction = "<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >>"
  let shading =
    "<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function \(grayFunction) >>"
  guard let parsed = parseShadingResource(name: "Sh0", shadingObject: shading) else {
    Issue.record("파싱 실패")
    return
  }
  #expect(parsed.gradient.stops.first?.color == RGBA(red: 0, green: 0, blue: 0))
  #expect(parsed.gradient.stops.last?.color == RGBA(red: 1, green: 1, blue: 1))
}
