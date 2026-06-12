import CoreGraphics

extension ContentStreamParser {
  /// BT~ET 텍스트 상태 (스펙 §9). 좌표는 PDF 텍스트 공간.
  struct TextState {
    var textMatrix: CGAffineTransform = .identity
    var lineMatrix: CGAffineTransform = .identity
    var font: PDFFont?
    var fontSize: CGFloat = 0
    var leading: CGFloat = 0
  }

  func beginText() {
    textState = TextState()
  }

  func endText() {
    textState = nil
  }

  func setFont(_ scanner: CGPDFScannerRef) {
    guard textState != nil else { return }
    var size: CGPDFReal = 0
    guard CGPDFScannerPopNumber(scanner, &size),
      let name = Self.popName(scanner)
    else { return }
    textState?.fontSize = CGFloat(size)
    // 폰트 리소스 조회
    guard let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "Font", name),
      let dictionary = CGPDFReading.dictionary(from: object)
    else {
      report.add(.unsupportedText, detail: "폰트 \(name)를 찾지 못함")
      textState?.font = nil
      return
    }
    let (font, unsupported) = PDFFontDecoder.font(from: dictionary)
    if let unsupported { report.add(.unsupportedText, detail: unsupported) }
    textState?.font = font
  }

  func textMove(_ scanner: CGPDFScannerRef, setLeading: Bool) {
    guard let values = Self.popNumbers(scanner, count: 2) else { return }
    if setLeading { textState?.leading = -values[1] }
    applyLineTranslation(tx: values[0], ty: values[1])
  }

  func setTextMatrix(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 6) else { return }
    let matrix = CGAffineTransform(
      a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    textState?.textMatrix = matrix
    textState?.lineMatrix = matrix
  }

  func textNextLine() {
    let leading = textState?.leading ?? 0
    applyLineTranslation(tx: 0, ty: -leading)
  }

  func setLeading(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    textState?.leading = values[0]
  }

  func showText(_ scanner: CGPDFScannerRef) {
    guard let bytes = Self.popString(scanner) else { return }
    emitText(bytes: bytes)
  }

  func showTextArray(_ scanner: CGPDFScannerRef) {
    var array: CGPDFArrayRef? = nil
    guard CGPDFScannerPopArray(scanner, &array), let array else { return }
    var bytes: [UInt8] = []
    for index in 0..<CGPDFArrayGetCount(array) {
      var element: CGPDFStringRef? = nil
      if CGPDFArrayGetString(array, index, &element), let element,
        let pointer = CGPDFStringGetBytePtr(element)
      {
        let length = CGPDFStringGetLength(element)
        bytes.append(contentsOf: UnsafeBufferPointer(start: pointer, count: length))
      }
      // 숫자(자간 조정)는 무시 (결정 기록)
    }
    emitText(bytes: bytes)
  }

  func showTextNextLine(_ scanner: CGPDFScannerRef) {
    textNextLine()
    showText(scanner)
  }

  func showTextWithSpacing(_ scanner: CGPDFScannerRef) {
    // " aw ac string — aw/ac 무시(best-effort), string만
    guard let bytes = Self.popString(scanner) else { return }
    _ = Self.popNumbers(scanner, count: 2)  // aw ac 버림
    textNextLine()
    emitText(bytes: bytes)
  }

  // MARK: - 내부

  private func applyLineTranslation(tx: CGFloat, ty: CGFloat) {
    guard var text = textState else { return }
    let translation = CGAffineTransform(translationX: tx, y: ty)
    text.lineMatrix = translation.concatenating(text.lineMatrix)
    text.textMatrix = text.lineMatrix
    textState = text
  }

  /// 디코드한 문자열로 TextNode를 만들고 text matrix를 advance한다.
  private func emitText(bytes: [UInt8]) {
    guard let text = textState, let font = text.font, !bytes.isEmpty else { return }
    let string = font.decode(bytes)
    guard !string.isEmpty else { return }
    // 회전·기울임 텍스트는 정립으로 근사한다 (transform=identity). b·c가 0이
    // 아니면 회전/전단 — 손실을 리포트한다 (pageFlip은 b=c=0이라 무관).
    let textToUser = text.textMatrix.concatenating(state.ctm)
    if textToUser.b != 0 || textToUser.c != 0 {
      report.add(.unsupportedText, detail: "회전·기울임 텍스트 — 정립 근사")
    }
    // 텍스트 공간 → 사용자 공간 → 모델: textMatrix × CTM × pageFlip.
    let toModel = textToUser.concatenating(pageFlip)
    let origin = CGPoint.zero.applying(toModel)
    let node = TextNode(
      string: string, fontName: font.baseFont, fontSize: Double(text.fontSize),
      fill: .color(state.fillColor), position: origin,
      transform: .identity)
    appendNode(.text(node), explicitClip: state.clip)
    // advance 근사 (Task 4에서 CoreText 측정으로 교체)
    let width = text.fontSize * CGFloat(string.count) * 0.5
    textState?.textMatrix =
      CGAffineTransform(translationX: width, y: 0).concatenating(text.textMatrix)
  }
}
