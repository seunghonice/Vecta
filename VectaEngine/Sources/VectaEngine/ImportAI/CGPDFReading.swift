import CoreGraphics

/// CGPDF 객체 그래프 읽기 헬퍼 (ImportAI 내부 공용).
enum CGPDFReading {
  /// 객체가 dict면 그대로, stream이면 그 dict를 반환.
  static func dictionary(from object: CGPDFObjectRef) -> CGPDFDictionaryRef? {
    var dict: CGPDFDictionaryRef? = nil
    if CGPDFObjectGetValue(object, .dictionary, &dict) { return dict }
    var stream: CGPDFStreamRef? = nil
    if CGPDFObjectGetValue(object, .stream, &stream), let stream {
      return CGPDFStreamGetDictionary(stream)
    }
    return nil
  }

  static func integer(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Int? {
    var value: CGPDFInteger = 0
    guard CGPDFDictionaryGetInteger(dictionary, key, &value) else { return nil }
    return value
  }

  static func number(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGFloat? {
    var value: CGPDFReal = 0
    guard CGPDFDictionaryGetNumber(dictionary, key, &value) else { return nil }
    return CGFloat(value)
  }

  static func array(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFArrayRef? {
    var array: CGPDFArrayRef? = nil
    guard CGPDFDictionaryGetArray(dictionary, key, &array) else { return nil }
    return array
  }

  /// 배열을 CGFloat 목록으로 (숫자가 아닌 원소가 있으면 nil).
  static func numbers(_ dictionary: CGPDFDictionaryRef, _ key: String) -> [CGFloat]? {
    guard let array = array(dictionary, key) else { return nil }
    var result: [CGFloat] = []
    for index in 0..<CGPDFArrayGetCount(array) {
      var value: CGPDFReal = 0
      guard CGPDFArrayGetNumber(array, index, &value) else { return nil }
      result.append(CGFloat(value))
    }
    return result
  }

  /// [lo hi] 2원소 배열 → ClosedRange (lo ≤ hi 보장 못 하면 nil).
  static func range(_ dictionary: CGPDFDictionaryRef, _ key: String) -> ClosedRange<CGFloat>? {
    guard let values = numbers(dictionary, key), values.count >= 2,
      values[0] <= values[1]
    else { return nil }
    return values[0]...values[1]
  }

  /// dict의 name 값 (DeviceRGB 등).
  static func name(_ dictionary: CGPDFDictionaryRef, _ key: String) -> String? {
    var pointer: UnsafePointer<CChar>? = nil
    guard CGPDFDictionaryGetName(dictionary, key, &pointer), let pointer else { return nil }
    return String(cString: pointer)
  }

  /// dict의 임의 객체 (배열/딕셔너리/스트림 등).
  static func object(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFObjectRef? {
    var object: CGPDFObjectRef? = nil
    guard CGPDFDictionaryGetObject(dictionary, key, &object) else { return nil }
    return object
  }

  /// 객체에서 stream을 꺼낸다.
  static func stream(from object: CGPDFObjectRef) -> CGPDFStreamRef? {
    var stream: CGPDFStreamRef? = nil
    guard CGPDFObjectGetValue(object, .stream, &stream) else { return nil }
    return stream
  }

  /// dict의 boolean 값.
  static func boolean(_ dictionary: CGPDFDictionaryRef, _ key: String) -> Bool? {
    var value: CGPDFBoolean = 0
    guard CGPDFDictionaryGetBoolean(dictionary, key, &value) else { return nil }
    return value != 0
  }
}
