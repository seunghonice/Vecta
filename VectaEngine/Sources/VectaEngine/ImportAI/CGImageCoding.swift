import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// CGImage ↔ PNG·일반 이미지 데이터 변환 (이미지 정규화·디코드 공용).
enum CGImageCoding {
  /// 임의 이미지 바이트(PNG·JPEG 등) → CGImage.
  static func cgImage(fromData data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return image
  }

  /// CGImage → PNG 데이터 (ImageNode 정규화 저장용).
  static func pngData(from image: CGImage) -> Data? {
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}
