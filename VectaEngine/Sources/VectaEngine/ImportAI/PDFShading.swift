import CoreGraphics

/// CGPDF shading 객체 → M3 Gradient (스펙 §5). ShadingType 2(axial)/3(radial)만.
/// type 1·4–7(mesh)·미지원 함수·비단순 색공간은 nil (호출부가 리포트).
/// 좌표는 셰이딩 좌표계 그대로 — 호출부가 모델 좌표로 베이크한다.
enum PDFShading {
  /// 함수를 균등 샘플하는 GradientStop 개수.
  static let sampleCount = 9

  static func parse(
    _ object: CGPDFObjectRef
  ) -> (gradient: Gradient, isRadial: Bool, lossyRadial: Bool)? {
    guard let dictionary = CGPDFReading.dictionary(from: object),
      let shadingType = CGPDFReading.integer(dictionary, "ShadingType"),
      shadingType == 2 || shadingType == 3,
      let colorSpace = colorSpace(dictionary),
      let functionObject = functionObject(dictionary),
      let function = PDFFunction.parse(functionObject),
      let coords = CGPDFReading.numbers(dictionary, "Coords")
    else { return nil }
    let domain = CGPDFReading.range(dictionary, "Domain") ?? (0...1)
    let stops = function.sampleStops(
      count: sampleCount, colorSpace: colorSpace, domain: domain)
    guard stops.count >= 2 else { return nil }

    if shadingType == 2 {
      guard coords.count >= 4 else { return nil }
      let gradient = Gradient(
        stops: stops,
        start: CGPoint(x: coords[0], y: coords[1]),
        end: CGPoint(x: coords[2], y: coords[3]))
      return (gradient, false, false)
    } else {
      guard coords.count >= 6 else { return nil }
      // M3 단일원 근사: 끝 원(c1, r1) 사용, 시작 원(r0, c0) 무시.
      let startRadius = coords[2]
      let endCenter = CGPoint(x: coords[3], y: coords[4])
      let endRadius = coords[5]
      let lossy =
        startRadius != 0 || coords[0] != coords[3] || coords[1] != coords[4]
      let gradient = Gradient(
        stops: stops, start: endCenter,
        end: CGPoint(x: endCenter.x + endRadius, y: endCenter.y))
      return (gradient, true, lossy)
    }
  }

  /// /ColorSpace name(DeviceGray/RGB/CMYK)만 — 배열형(ICCBased 등)은 nil.
  private static func colorSpace(_ dictionary: CGPDFDictionaryRef) -> PDFColorSpace? {
    guard let name = CGPDFReading.name(dictionary, "ColorSpace") else { return nil }
    let space = PDFColorSpace.named(name)
    if case .unsupported = space { return nil }
    if space == .pattern { return nil }
    return space
  }

  /// /Function — 단일 함수 또는 배열(배열이면 첫 요소만, best-effort).
  private static func functionObject(_ dictionary: CGPDFDictionaryRef) -> CGPDFObjectRef? {
    guard let object = CGPDFReading.object(dictionary, "Function") else { return nil }
    // 배열이면 첫 요소 (성분별 분리 함수 — 근사).
    var array: CGPDFArrayRef? = nil
    if CGPDFObjectGetValue(object, .array, &array), let array,
      CGPDFArrayGetCount(array) > 0
    {
      var first: CGPDFObjectRef? = nil
      if CGPDFArrayGetObject(array, 0, &first) { return first }
    }
    return object
  }
}
