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

  /// 폰트의 균일 줄 메트릭. 모든 줄에 같은 높이를 써서 빈 줄도 한 줄을 차지하고
  /// (개행만으로 만든 빈 줄이 붕괴하지 않음) 측정·렌더가 단일 규칙을 공유한다.
  static func lineMetrics(fontName: String, fontSize: CGFloat) -> (ascent: CGFloat, height: CGFloat)
  {
    let ctFont = font(named: fontName, size: fontSize)
    let ascent = CTFontGetAscent(ctFont)
    return (ascent, ascent + CTFontGetDescent(ctFont))
  }

  /// 텍스트 바운드 (position 기준, 모델 좌표 — baseline 위로 ascent, 아래로 descent).
  /// 모델은 top-down이므로 baseline 위쪽(ascent)이 y 작은 방향.
  /// 멀티라인: 폭=각 줄 advance 최대값, 높이=균일 줄높이 × 줄 수. position은 첫 줄 baseline.
  static func bounds(
    string: String, fontName: String, fontSize: CGFloat, position: CGPoint
  ) -> CGRect {
    guard fontSize > 0, !string.isEmpty else { return CGRect(origin: position, size: .zero) }
    let lineStrings = string.components(separatedBy: "\n")
    let metrics = lineMetrics(fontName: fontName, fontSize: fontSize)
    let maxWidth =
      lineStrings.map {
        advanceWidth(string: $0, fontName: fontName, fontSize: fontSize)
      }.max() ?? 0
    let totalHeight = metrics.height * CGFloat(lineStrings.count)
    return CGRect(
      x: position.x, y: position.y - metrics.ascent, width: maxWidth, height: totalHeight)
  }

  /// 줄별 CTLine + 첫 줄 baseline 기준 y오프셋 목록.
  /// dy는 top-down 모델 기준 — 첫 줄 0, 이후 줄은 균일 줄높이 누적(아래 방향).
  static func lines(
    string: String, fontName: String, fontSize: CGFloat, color: CGColor
  ) -> [(ctLine: CTLine, dy: CGFloat)] {
    guard fontSize > 0, !string.isEmpty else { return [] }
    let lineHeight = lineMetrics(fontName: fontName, fontSize: fontSize).height
    return string.components(separatedBy: "\n").enumerated().map { index, lineString in
      (
        line(lineString, fontName: fontName, fontSize: fontSize, color: color),
        CGFloat(index) * lineHeight
      )
    }
  }
}
