import CoreGraphics
import Foundation

/// PDF image XObject → PNG 데이터 (스펙 §5). 압축 이미지(DCT/JPX)는 ImageIO에
/// 위임하고, raw는 DeviceRGB/Gray 8bpc만 직접 구성한다. 그 외는 미지원 사유 반환.
enum PDFImageDecoder {
  /// (png, unsupported) — png가 nil이고 unsupported가 사유면 리포트 대상.
  static func decode(
    _ stream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef
  ) -> (png: Data?, unsupported: String?) {
    if let bit = CGPDFReading.boolean(dictionary, "ImageMask"), bit {
      return (nil, "이미지 마스크 (알파 — 미지원)")
    }
    if CGPDFReading.object(dictionary, "SMask") != nil {
      return (nil, "소프트 마스크 (알파 — 미지원)")
    }
    var format = CGPDFDataFormat.raw
    guard let data = CGPDFStreamCopyData(stream, &format) as Data? else {
      return (nil, "이미지 스트림 디코드 실패")
    }
    switch format {
    case .jpegEncoded, .JPEG2000:
      guard let cgImage = CGImageCoding.cgImage(fromData: data),
        let png = CGImageCoding.pngData(from: cgImage)
      else { return (nil, "압축 이미지 디코드 실패") }
      return (png, nil)
    case .raw:
      return decodeRaw(data, dictionary: dictionary)
    @unknown default:
      return (nil, "알 수 없는 이미지 포맷")
    }
  }

  private static func decodeRaw(
    _ data: Data, dictionary: CGPDFDictionaryRef
  ) -> (png: Data?, unsupported: String?) {
    guard let width = CGPDFReading.integer(dictionary, "Width"),
      let height = CGPDFReading.integer(dictionary, "Height"),
      width > 0, height > 0
    else { return (nil, "이미지 크기 누락") }
    let bitsPerComponent = CGPDFReading.integer(dictionary, "BitsPerComponent") ?? 8
    guard bitsPerComponent == 8 else {
      return (nil, "비트 깊이 \(bitsPerComponent) (8bpc만 지원)")
    }
    // /ColorSpace는 name(Device*)만. 배열형(Indexed/ICC 등)은 미지원.
    guard let spaceName = CGPDFReading.name(dictionary, "ColorSpace") else {
      return (nil, "비단순 이미지 색공간")
    }
    let componentCount: Int
    let cgSpace: CGColorSpace
    switch spaceName {
    case "DeviceRGB":
      componentCount = 3
      cgSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    case "DeviceGray":
      componentCount = 1
      cgSpace = CGColorSpaceCreateDeviceGray()
    default:
      return (nil, "이미지 색공간 \(spaceName) (RGB·Gray만)")
    }
    let bytesPerRow = width * componentCount
    guard data.count >= bytesPerRow * height else {
      return (nil, "이미지 데이터 길이 부족")
    }
    // 두 색공간 모두 알파 없음 (raw 픽셀은 알파 채널 미포함).
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    guard let provider = CGDataProvider(data: data as CFData),
      let cgImage = CGImage(
        width: width, height: height, bitsPerComponent: 8,
        bitsPerPixel: 8 * componentCount, bytesPerRow: bytesPerRow,
        space: cgSpace, bitmapInfo: bitmapInfo, provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return (nil, "이미지 비트맵 구성 실패") }
    guard let png = CGImageCoding.pngData(from: cgImage) else {
      return (nil, "PNG 정규화 실패")
    }
    return (png, nil)
  }
}
