import CoreGraphics
import CoreText
import Foundation

/// 텍스트 렌더·측정 공용 (CoreText). 폰트명이 시스템에 없으면 폴백.
enum TextRendering {
  /// fontName/fontSize의 폰트 (없으면 시스템 폰트로 폴백 — 원본명은 노드가 보존).
  ///
  /// 주의: CTFontCreateWithName(size: 0)은 0크기가 아니라 기본 크기로 폴백한다
  /// — 호출부가 fontSize>0을 보장해야 한다.
  static func font(named fontName: String, size: CGFloat) -> CTFont {
    let cfName = fontName as CFString
    return CTFontCreateWithName(cfName, size, nil)
  }

  /// 문자열의 CTLine (fill 색 적용).
  static func line(
    _ string: String, fontName: String, fontSize: CGFloat, color: CGColor
  ) -> CTLine {
    let ctFont = font(named: fontName, size: fontSize)
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: ctFont,
      kCTForegroundColorAttributeName: color,
    ]
    let attributed = CFAttributedStringCreate(
      nil, string as CFString, attributes as CFDictionary)!
    return CTLineCreateWithAttributedString(attributed)
  }

  /// 텍스트 공간 advance 폭 (text matrix 이동용).
  static func advanceWidth(string: String, fontName: String, fontSize: CGFloat) -> CGFloat {
    guard fontSize > 0, !string.isEmpty else { return 0 }
    let ctLine = line(string, fontName: fontName, fontSize: fontSize, color: .black)
    return CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
  }

  /// 텍스트 바운드 (position 기준, 모델 좌표 — baseline 위로 ascent, 아래로 descent).
  /// 모델은 top-down이므로 baseline 위쪽(ascent)이 y 작은 방향.
  static func bounds(
    string: String, fontName: String, fontSize: CGFloat, position: CGPoint
  ) -> CGRect {
    guard fontSize > 0, !string.isEmpty else { return CGRect(origin: position, size: .zero) }
    let ctLine = line(string, fontName: fontName, fontSize: fontSize, color: .black)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, nil))
    // 모델 top-down: position이 baseline. ascent는 위(y−), descent는 아래(y+).
    return CGRect(
      x: position.x, y: position.y - ascent, width: width, height: ascent + descent)
  }
}
