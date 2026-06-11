import CoreGraphics

@testable import VectaEngine

/// sRGB premultipliedLast(RGBA8) 비트맵에 모델 좌표(top-left)로 렌더링한다.
/// CTM 플립 덕분에 "모델 (x, y) = 비트맵 row y" 가 성립한다.
func renderToBitmap(_ document: VectorDocument, size: CGSize) -> CGContext {
  let context = CGContext(
    data: nil,
    width: Int(size.width), height: Int(size.height),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.translateBy(x: 0, y: size.height)
  context.scaleBy(x: 1, y: -1)
  SceneRenderer.render(document, in: context)
  return context
}

func pixelColor(x: Int, y: Int, in context: CGContext) -> (
  red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
) {
  let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
  let offset = y * context.bytesPerRow + x * 4
  return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
}
