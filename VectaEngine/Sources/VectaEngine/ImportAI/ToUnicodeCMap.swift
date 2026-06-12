import Foundation

/// PDF /ToUnicode CMap (스펙 §5) — 폰트 코드 바이트 → 유니코드 문자열.
/// beginbfchar/beginbfrange 블록만 파싱한다(codespacerange는 코드 폭 추정에
/// 쓰지 않고 폰트 Subtype으로 결정 — 결정 기록).
struct ToUnicodeCMap: Equatable {
  private var singles: [UInt32: String] = [:]
  private var ranges: [(lo: UInt32, hi: UInt32, destinations: [String])] = []

  static func == (lhs: ToUnicodeCMap, rhs: ToUnicodeCMap) -> Bool {
    lhs.singles == rhs.singles
      && lhs.ranges.count == rhs.ranges.count
      && zip(lhs.ranges, rhs.ranges).allSatisfy {
        $0.lo == $1.lo && $0.hi == $1.hi && $0.destinations == $1.destinations
      }
  }

  /// 코드 → 문자열 (없으면 nil).
  func string(forCode code: UInt32) -> String? {
    if let single = singles[code] { return single }
    for range in ranges where code >= range.lo && code <= range.hi {
      let offset = Int(code - range.lo)
      if range.destinations.count == 1 {
        // 단일 시작 dst + 오프셋 (스칼라 증가)
        guard let base = range.destinations.first?.unicodeScalars.first else { return nil }
        return Unicode.Scalar(base.value + UInt32(offset)).map(String.init)
      }
      guard offset < range.destinations.count else { return nil }
      return range.destinations[offset]
    }
    return nil
  }

  /// 바이트 시퀀스를 codeBytes 폭 코드로 끊어 문자열로 디코드.
  /// 매핑 없는 코드는 건너뛴다(또는 대체문자 — 여기선 건너뜀).
  func decode(_ bytes: [UInt8], codeBytes: Int) -> String {
    var result = ""
    var index = 0
    while index + codeBytes <= bytes.count {
      var code: UInt32 = 0
      for offset in 0..<codeBytes {
        code = (code << 8) | UInt32(bytes[index + offset])
      }
      if let mapped = string(forCode: code) { result += mapped }
      index += codeBytes
    }
    return result
  }

  /// CMap 텍스트를 파싱한다.
  static func parse(_ text: String) -> ToUnicodeCMap {
    var cmap = ToUnicodeCMap()
    let tokens = tokenize(text)
    var index = 0
    while index < tokens.count {
      switch tokens[index] {
      case "beginbfchar":
        index += 1
        while index < tokens.count, tokens[index] != "endbfchar" {
          if let src = hexValue(tokens[index]),
            index + 1 < tokens.count, let dst = hexString(tokens[index + 1])
          {
            cmap.singles[src] = dst
            index += 2
          } else {
            index += 1
          }
        }
      case "beginbfrange":
        index += 1
        while index < tokens.count, tokens[index] != "endbfrange" {
          guard let lo = hexValue(tokens[index]), index + 2 < tokens.count,
            let hi = hexValue(tokens[index + 1])
          else {
            index += 1
            continue
          }
          let third = tokens[index + 2]
          if third == "[" {
            // 배열형: [<dst0> <dst1> ...]
            var destinations: [String] = []
            var cursor = index + 3
            while cursor < tokens.count, tokens[cursor] != "]" {
              if let dst = hexString(tokens[cursor]) { destinations.append(dst) }
              cursor += 1
            }
            cmap.ranges.append((lo, hi, destinations))
            index = cursor + 1
          } else if let dst = hexString(third) {
            cmap.ranges.append((lo, hi, [dst]))
            index += 3
          } else {
            index += 1
          }
        }
      default:
        index += 1
      }
    }
    return cmap
  }

  // MARK: - 토큰화

  /// `<hex>` · `[` · `]` · 키워드를 토큰으로 분리.
  private static func tokenize(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var index = text.startIndex
    while index < text.endIndex {
      let character = text[index]
      switch character {
      case "<":
        flush(&current, into: &tokens)
        var hex = "<"
        index = text.index(after: index)
        while index < text.endIndex, text[index] != ">" {
          hex.append(text[index])
          index = text.index(after: index)
        }
        hex.append(">")
        tokens.append(hex)
      case "[", "]":
        flush(&current, into: &tokens)
        tokens.append(String(character))
      case " ", "\n", "\r", "\t":
        flush(&current, into: &tokens)
      default:
        current.append(character)
      }
      if index < text.endIndex { index = text.index(after: index) }
    }
    flush(&current, into: &tokens)
    return tokens
  }

  private static func flush(_ current: inout String, into tokens: inout [String]) {
    if !current.isEmpty {
      tokens.append(current)
      current = ""
    }
  }

  /// `<0041>` → 0x41 (UInt32).
  private static func hexValue(_ token: String) -> UInt32? {
    guard token.hasPrefix("<"), token.hasSuffix(">") else { return nil }
    let hex = token.dropFirst().dropLast()
    return UInt32(hex, radix: 16)
  }

  /// `<0041>` → "A", `<00660069>` → "fi" (UTF-16BE 코드유닛 시퀀스).
  private static func hexString(_ token: String) -> String? {
    guard token.hasPrefix("<"), token.hasSuffix(">") else { return nil }
    let hex = token.dropFirst().dropLast()
    guard hex.count % 4 == 0 else {
      // 4자리(2바이트=UTF16 1유닛) 배수가 아니면 단일 스칼라로 시도
      guard let value = UInt32(hex, radix: 16),
        let scalar = Unicode.Scalar(value)
      else { return nil }
      return String(scalar)
    }
    var units: [UInt16] = []
    var cursor = hex.startIndex
    while cursor < hex.endIndex {
      let next = hex.index(cursor, offsetBy: 4)
      guard let unit = UInt16(hex[cursor..<next], radix: 16) else { return nil }
      units.append(unit)
      cursor = next
    }
    return String(decoding: units, as: UTF16.self)
  }
}
