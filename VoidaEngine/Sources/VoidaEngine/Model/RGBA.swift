/// sRGB 색상. 각 채널 0…1.
public struct RGBA: Equatable, Codable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public static let black = RGBA(red: 0, green: 0, blue: 0)
  public static let white = RGBA(red: 1, green: 1, blue: 1)
}
