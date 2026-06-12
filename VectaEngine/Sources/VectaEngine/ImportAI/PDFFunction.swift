import CoreGraphics

/// PDF 함수 (PDF §7.10) — 그라디언트 색 보간용. type 2(지수)·3(스티칭)만 모델링.
/// type 0(샘플)·4(포스트스크립트)는 파싱 단계에서 nil (미지원 리포트 — Task 2).
enum PDFFunction: Equatable {
  case exponential(
    c0: [CGFloat], c1: [CGFloat], exponent: CGFloat, domain: ClosedRange<CGFloat>)
  indirect case stitching(
    functions: [PDFFunction], bounds: [CGFloat],
    encode: [(CGFloat, CGFloat)], domain: ClosedRange<CGFloat>)

  static func == (lhs: PDFFunction, rhs: PDFFunction) -> Bool {
    switch (lhs, rhs) {
    case (
      .exponential(let lc0, let lc1, let le, let ld),
      .exponential(let rc0, let rc1, let re, let rd)
    ):
      return lc0 == rc0 && lc1 == rc1 && le == re && ld == rd
    case (
      .stitching(let lf, let lb, let lenc, let ld),
      .stitching(let rf, let rb, let renc, let rd)
    ):
      guard lf == rf, lb == rb, ld == rd, lenc.count == renc.count else { return false }
      return zip(lenc, renc).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
    default:
      return false
    }
  }

  /// 입력 t의 색 성분 배열. domain 밖은 클램프.
  func evaluate(_ t: CGFloat) -> [CGFloat] {
    switch self {
    case .exponential(let c0, let c1, let exponent, let domain):
      let x = min(max(t, domain.lowerBound), domain.upperBound)
      // 음수 base + 분수 지수 = NaN 방어 (도메인이 음수 허용해도 안전).
      let factor = pow(max(x, 0), exponent)
      return zip(c0, c1).map { $0 + factor * ($1 - $0) }
    case .stitching(let functions, let bounds, let encode, let domain):
      guard !functions.isEmpty, encode.count == functions.count else { return [] }
      let x = min(max(t, domain.lowerBound), domain.upperBound)
      // 구간 k: x < bounds[k] 인 첫 k (없으면 마지막).
      var k = 0
      while k < bounds.count, x >= bounds[k] { k += 1 }
      k = min(k, functions.count - 1)
      let lo = k == 0 ? domain.lowerBound : bounds[k - 1]
      let hi = k == bounds.count ? domain.upperBound : bounds[k]
      let (encodeLo, encodeHi) = encode[k]
      let mapped =
        hi == lo
        ? encodeLo
        : encodeLo + (x - lo) * (encodeHi - encodeLo) / (hi - lo)
      return functions[k].evaluate(mapped)
    }
  }

  /// 도메인을 count등분 균등 샘플해 GradientStop 배열을 만든다.
  /// 성분 수가 부족하면 그 스톱을 건너뛴다 (초과 시 color(from:)이 앞부분만 사용).
  func sampleStops(
    count: Int, colorSpace: PDFColorSpace, domain: ClosedRange<CGFloat>
  ) -> [GradientStop] {
    guard count >= 2 else { return [] }
    var stops: [GradientStop] = []
    for index in 0..<count {
      let fraction = CGFloat(index) / CGFloat(count - 1)
      let t = domain.lowerBound + fraction * (domain.upperBound - domain.lowerBound)
      guard let color = colorSpace.color(from: evaluate(t)) else { continue }
      stops.append(GradientStop(location: Double(fraction), color: color))
    }
    return stops
  }
}
