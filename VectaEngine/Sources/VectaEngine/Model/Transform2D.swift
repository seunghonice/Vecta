import CoreGraphics

/// Codable 가능한 2D 아핀 변환. 필드명 a/b/c/d/tx/ty는 PDF·CoreGraphics
/// 아핀 행렬의 표준 표기를 따른다.
public struct Transform2D: Equatable, Codable, Sendable {
  public var a: Double
  public var b: Double
  public var c: Double
  public var d: Double
  public var tx: Double
  public var ty: Double

  public static let identity = Transform2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

  public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
    self.tx = tx
    self.ty = ty
  }

  public init(_ transform: CGAffineTransform) {
    self.init(
      a: transform.a, b: transform.b, c: transform.c,
      d: transform.d, tx: transform.tx, ty: transform.ty)
  }

  public var cgAffineTransform: CGAffineTransform {
    CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty)
  }

  /// 행렬식 (ad − bc). 0에 가까우면 특이 행렬.
  public var determinant: Double {
    a * d - b * c
  }

  /// 특이 행렬(행렬식 ≈ 0)이면 nil — `inverted()`가 원본을 반환하는 함정 방어.
  public var invertedOrNil: CGAffineTransform? {
    guard abs(determinant) > 1e-10 else { return nil }
    return cgAffineTransform.inverted()
  }
}
