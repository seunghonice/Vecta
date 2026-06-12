import CoreGraphics
import Foundation

/// info 포인터 → 파서 (C 콜백은 캡처 불가 — 파일 전역 함수로 복원).
private func parserFrom(_ info: UnsafeMutableRawPointer?) -> ContentStreamParser {
  Unmanaged<ContentStreamParser>.fromOpaque(info!).takeUnretainedValue()
}

/// PDF 콘텐츠 스트림 → [Node] (스펙 §5). CGPDFScanner 연산자 콜백으로
/// 그래픽 상태를 유지하며 페인팅 연산자마다 PathNode를 만든다.
/// CTM·페이지 플립은 좌표에 베이크 — 산출 노드의 transform은 identity.
final class ContentStreamParser {
  /// PDF 그래픽 상태 (q/Q 스택 단위).
  struct GraphicsState: Equatable {
    var ctm: CGAffineTransform = .identity
    var fillColorSpace: PDFColorSpace = .deviceGray
    var strokeColorSpace: PDFColorSpace = .deviceGray
    var fillColor: RGBA = .black
    var strokeColor: RGBA = .black
    var lineWidth: CGFloat = 1
    var lineCap: LineCap = .butt
    var lineJoin: LineJoin = .miter
    var dash: [CGFloat] = []
    var fillAlpha: Double = 1
    /// 누적 클립 (모델 좌표, winding 정규화 완료).
    var clip: BezierPath?
  }

  private struct ClippedNode {
    var clip: BezierPath?
    var node: Node
  }

  fileprivate enum PendingClip {
    case winding, evenOdd
  }

  static let maxFormDepth = 8

  private var state = GraphicsState()
  private var stateStack: [GraphicsState] = []
  private var pathBuilder = PDFPathBuilder()
  fileprivate var pendingClip: PendingClip?
  private var sinkStack: [[ClippedNode]] = [[]]
  private var contentStreamStack: [CGPDFContentStreamRef] = []
  private var formDepth = 0
  private var didReportText = false
  private var didReportInlineImage = false
  private(set) var report = ImportReport()
  /// PDF 사용자 공간(bottom-left) → 모델(top-left) 변환.
  private let pageFlip: CGAffineTransform

  init(mediaBox: CGRect) {
    pageFlip = CGAffineTransform(
      a: 1, b: 0, c: 0, d: -1, tx: -mediaBox.minX, ty: mediaBox.maxY)
  }

  /// 페이지를 파싱해 노드와 리포트를 반환한다.
  static func parse(page: CGPDFPage) -> (nodes: [Node], report: ImportReport) {
    let parser = ContentStreamParser(mediaBox: page.getBoxRect(.mediaBox))
    let contentStream = CGPDFContentStreamCreateWithPage(page)
    parser.scan(contentStream: contentStream)
    CGPDFContentStreamRelease(contentStream)
    return (parser.finalizedNodes(), parser.report)
  }

  // MARK: - 스캐너

  private func scan(contentStream: CGPDFContentStreamRef) {
    contentStreamStack.append(contentStream)
    defer { contentStreamStack.removeLast() }
    let table = CGPDFOperatorTableCreate()!
    Self.registerOperators(in: table)
    let scanner = CGPDFScannerCreate(
      contentStream, table, Unmanaged.passUnretained(self).toOpaque())
    CGPDFScannerScan(scanner)
    CGPDFScannerRelease(scanner)
    CGPDFOperatorTableRelease(table)
  }

  private static func registerOperators(in table: CGPDFOperatorTableRef) {
    // 상태
    CGPDFOperatorTableSetCallback(table, "q") { _, info in parserFrom(info).saveState() }
    CGPDFOperatorTableSetCallback(table, "Q") { _, info in parserFrom(info).restoreState() }
    CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
      parserFrom(info).concatenateMatrix(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "w") { scanner, info in
      parserFrom(info).setLineWidth(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "J") { scanner, info in
      parserFrom(info).setLineCap(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "j") { scanner, info in
      parserFrom(info).setLineJoin(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "d") { scanner, info in
      parserFrom(info).setDash(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "gs") { scanner, info in
      parserFrom(info).setExtGState(scanner)
    }
    // 색상
    CGPDFOperatorTableSetCallback(table, "g") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceGray, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "G") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceGray, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "rg") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceRGB, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "RG") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceRGB, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "k") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceCMYK, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "K") { scanner, info in
      parserFrom(info).setColor(scanner, space: .deviceCMYK, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "cs") { scanner, info in
      parserFrom(info).setColorSpace(scanner, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "CS") { scanner, info in
      parserFrom(info).setColorSpace(scanner, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "sc") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "scn") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: false)
    }
    CGPDFOperatorTableSetCallback(table, "SC") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: true)
    }
    CGPDFOperatorTableSetCallback(table, "SCN") { scanner, info in
      parserFrom(info).setColorComponents(scanner, isStroke: true)
    }
    // 패스 구성
    CGPDFOperatorTableSetCallback(table, "m") { scanner, info in
      parserFrom(info).pathMove(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "l") { scanner, info in
      parserFrom(info).pathLine(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "c") { scanner, info in
      parserFrom(info).pathCurve(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "v") { scanner, info in
      parserFrom(info).pathCurveV(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "y") { scanner, info in
      parserFrom(info).pathCurveY(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "h") { _, info in
      parserFrom(info).pathClose()
    }
    CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
      parserFrom(info).pathRect(scanner)
    }
    // 페인팅
    CGPDFOperatorTableSetCallback(table, "f") { _, info in
      parserFrom(info).paint(fill: true, stroke: false, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "F") { _, info in
      parserFrom(info).paint(fill: true, stroke: false, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "f*") { _, info in
      parserFrom(info).paint(fill: true, stroke: false, close: false, evenOdd: true)
    }
    CGPDFOperatorTableSetCallback(table, "B") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "B*") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: false, evenOdd: true)
    }
    CGPDFOperatorTableSetCallback(table, "b") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: true, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "b*") { _, info in
      parserFrom(info).paint(fill: true, stroke: true, close: true, evenOdd: true)
    }
    CGPDFOperatorTableSetCallback(table, "S") { _, info in
      parserFrom(info).paint(fill: false, stroke: true, close: false, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "s") { _, info in
      parserFrom(info).paint(fill: false, stroke: true, close: true, evenOdd: false)
    }
    CGPDFOperatorTableSetCallback(table, "n") { _, info in
      parserFrom(info).paint(fill: false, stroke: false, close: false, evenOdd: false)
    }
    // 클리핑 — 다음 페인팅 연산자에서 확정된다
    CGPDFOperatorTableSetCallback(table, "W") { _, info in
      parserFrom(info).pendingClip = .winding
    }
    CGPDFOperatorTableSetCallback(table, "W*") { _, info in
      parserFrom(info).pendingClip = .evenOdd
    }
    // XObject
    CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
      parserFrom(info).invokeXObject(scanner)
    }
    // 미지원 리포트는 Task 10에서 등록 추가
  }

  // MARK: - 피연산자 팝

  fileprivate static func popNumbers(_ scanner: CGPDFScannerRef, count: Int) -> [CGFloat]? {
    var values: [CGFloat] = []
    for _ in 0..<count {
      var value: CGPDFReal = 0
      guard CGPDFScannerPopNumber(scanner, &value) else { return nil }
      values.append(CGFloat(value))
    }
    return Array(values.reversed())  // 피연산자 스택은 역순으로 팝된다
  }

  fileprivate static func popName(_ scanner: CGPDFScannerRef) -> String? {
    var pointer: UnsafePointer<CChar>? = nil
    guard CGPDFScannerPopName(scanner, &pointer), let pointer else { return nil }
    return String(cString: pointer)
  }

  // MARK: - 상태 연산자

  private func saveState() {
    stateStack.append(state)
  }

  private func restoreState() {
    if let restored = stateStack.popLast() {
      state = restored
    }
  }

  private func concatenateMatrix(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 6) else { return }
    let matrix = CGAffineTransform(
      a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    state.ctm = matrix.concatenating(state.ctm)
  }

  private func setLineWidth(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    state.lineWidth = values[0]
  }

  private func setLineCap(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    switch Int(values[0]) {
    case 1: state.lineCap = .round
    case 2: state.lineCap = .square
    default: state.lineCap = .butt
    }
  }

  private func setLineJoin(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 1) else { return }
    switch Int(values[0]) {
    case 1: state.lineJoin = .round
    case 2: state.lineJoin = .bevel
    default: state.lineJoin = .miter
    }
  }

  private func setDash(_ scanner: CGPDFScannerRef) {
    // phase는 모델에 없어 무시한다 (결정 기록).
    var phase: CGPDFReal = 0
    _ = CGPDFScannerPopNumber(scanner, &phase)
    var array: CGPDFArrayRef? = nil
    guard CGPDFScannerPopArray(scanner, &array), let array else { return }
    var dash: [CGFloat] = []
    for index in 0..<CGPDFArrayGetCount(array) {
      var value: CGPDFReal = 0
      if CGPDFArrayGetNumber(array, index, &value) {
        dash.append(CGFloat(value))
      }
    }
    state.dash = dash
  }

  private func setExtGState(_ scanner: CGPDFScannerRef) {
    guard let name = Self.popName(scanner),
      let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "ExtGState", name)
    else { return }
    var dictionary: CGPDFDictionaryRef? = nil
    guard CGPDFObjectGetValue(object, .dictionary, &dictionary), let dictionary
    else { return }
    var alpha: CGPDFReal = 1
    if CGPDFDictionaryGetNumber(dictionary, "ca", &alpha) {
      state.fillAlpha = Double(alpha)
    }
  }

  // MARK: - 색상 연산자

  private func setColor(
    _ scanner: CGPDFScannerRef, space: PDFColorSpace, isStroke: Bool
  ) {
    guard let values = Self.popNumbers(scanner, count: space.componentCount),
      let color = space.color(from: values)
    else { return }
    if isStroke {
      state.strokeColorSpace = space
      state.strokeColor = color
    } else {
      state.fillColorSpace = space
      state.fillColor = color
    }
  }

  private func setColorSpace(_ scanner: CGPDFScannerRef, isStroke: Bool) {
    guard let name = Self.popName(scanner) else {
      // 배열형(ICCBased 등) 색공간 — 리포트 후 기존 공간 유지
      report.add(.unsupportedColorSpace, detail: "비단순 색공간")
      return
    }
    let space = PDFColorSpace.named(name)
    if case .unsupported(let unsupportedName) = space {
      report.add(.unsupportedColorSpace, detail: "색공간 \(unsupportedName)")
      return
    }
    if isStroke {
      state.strokeColorSpace = space
    } else {
      state.fillColorSpace = space
    }
  }

  private func setColorComponents(_ scanner: CGPDFScannerRef, isStroke: Bool) {
    let space = isStroke ? state.strokeColorSpace : state.fillColorSpace
    if space == .pattern {
      // scn /P1 — shading 패턴 채움은 M4b. 직전 색 유지, 리포트만.
      report.add(.unsupportedShading, detail: "패턴 채움 (M4b에서 지원 예정)")
      return
    }
    guard space.componentCount > 0,
      let values = Self.popNumbers(scanner, count: space.componentCount),
      let color = space.color(from: values)
    else { return }
    if isStroke {
      state.strokeColor = color
    } else {
      state.fillColor = color
    }
  }

  // MARK: - 패스 구성 연산자

  private func pathMove(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 2) else { return }
    pathBuilder.move(to: CGPoint(x: values[0], y: values[1]))
  }

  private func pathLine(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 2) else { return }
    pathBuilder.line(to: CGPoint(x: values[0], y: values[1]))
  }

  private func pathCurve(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 6) else { return }
    pathBuilder.curve(
      to: CGPoint(x: values[4], y: values[5]),
      control1: CGPoint(x: values[0], y: values[1]),
      control2: CGPoint(x: values[2], y: values[3]))
  }

  private func pathCurveV(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 4) else { return }
    pathBuilder.curveV(
      to: CGPoint(x: values[2], y: values[3]),
      control2: CGPoint(x: values[0], y: values[1]))
  }

  private func pathCurveY(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 4) else { return }
    pathBuilder.curveY(
      to: CGPoint(x: values[2], y: values[3]),
      control1: CGPoint(x: values[0], y: values[1]))
  }

  private func pathClose() {
    pathBuilder.close()
  }

  private func pathRect(_ scanner: CGPDFScannerRef) {
    guard let values = Self.popNumbers(scanner, count: 4) else { return }
    pathBuilder.rect(
      CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
  }

  // MARK: - 페인팅

  private func paint(fill: Bool, stroke: Bool, close: Bool, evenOdd: Bool) {
    if close {
      pathBuilder.close()
    }
    let userPath = pathBuilder.finish()
    // 같은 연산자의 클립+페인트(W f 등)는 이전 클립 아래에서 칠한다 (§8.5.4) —
    // 새 클립은 이 페인팅이 끝난 뒤부터.
    let clipForThisPaint = state.clip
    applyPendingClip(with: userPath)
    guard fill || stroke, !userPath.subpaths.isEmpty else { return }
    // CTM은 페인팅 시점에 일괄 적용한다. 패스 구성 중 cm(스펙 §8.5.2.1 금지
    // 패턴)은 구성 시점 CTM과 달라질 수 있으나 실제 생성기에는 없어 허용.
    let toModel = state.ctm.concatenating(pageFlip)
    let modelPath = userPath.applying(toModel)
    var style = Style(opacity: state.fillAlpha)
    if fill {
      style.fill = .color(state.fillColor)
    }
    if stroke {
      // PDF 선폭은 사용자 공간 정의 — CTM의 √|det| 근사 스케일 (결정 기록).
      let widthScale = CGFloat(sqrt(abs(Transform2D(state.ctm).determinant)))
      style.stroke = Stroke(
        paint: state.strokeColor, width: state.lineWidth * widthScale,
        cap: state.lineCap, join: state.lineJoin,
        dash: state.dash.map { $0 * widthScale })
    }
    appendNode(
      .path(
        PathNode(path: modelPath, style: style, fillRule: evenOdd ? .evenOdd : .winding)),
      explicitClip: clipForThisPaint)
  }

  /// 현재 상태의 클립으로 노드를 수집한다.
  private func appendNode(_ node: Node) {
    sinkStack[sinkStack.count - 1].append(ClippedNode(clip: state.clip, node: node))
  }

  /// - Parameter explicitClip: 전달값을 그대로 사용한다 (nil = 클립 없음).
  ///   W+페인트 결합 연산자처럼 이전 클립을 명시해야 할 때 쓴다 (§8.5.4).
  private func appendNode(_ node: Node, explicitClip: BezierPath?) {
    sinkStack[sinkStack.count - 1].append(ClippedNode(clip: explicitClip, node: node))
  }

  /// W/W* 보류 클립을 현재 패스로 확정한다.
  private func applyPendingClip(with userPath: BezierPath) {
    guard let pending = pendingClip else { return }
    pendingClip = nil
    guard !userPath.subpaths.isEmpty else { return }
    let toModel = state.ctm.concatenating(pageFlip)
    let rule: CGPathFillRule = pending == .evenOdd ? .evenOdd : .winding
    let normalized = userPath.applying(toModel).cgPath.normalized(using: rule)
    if let existing = state.clip {
      state.clip = BezierPath(cgPath: existing.cgPath.intersection(normalized))
    } else {
      state.clip = BezierPath(cgPath: normalized)
    }
  }

  // MARK: - XObject

  private func invokeXObject(_ scanner: CGPDFScannerRef) {
    guard let name = Self.popName(scanner),
      let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "XObject", name)
    else { return }
    var xobjectStream: CGPDFStreamRef? = nil
    guard CGPDFObjectGetValue(object, .stream, &xobjectStream), let xobjectStream,
      let dictionary = CGPDFStreamGetDictionary(xobjectStream)
    else { return }
    var subtypePointer: UnsafePointer<CChar>? = nil
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypePointer),
      let subtypePointer
    else { return }
    switch String(cString: subtypePointer) {
    case "Form":
      invokeForm(xobjectStream, dictionary: dictionary)
    case "Image":
      report.add(.unsupportedImage, detail: "이미지 XObject \(name) (M4b에서 지원 예정)")
    default:
      break
    }
  }

  private func invokeForm(_ formStream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef) {
    guard formDepth < Self.maxFormDepth else {
      report.add(.formRecursionLimit, detail: "폼 중첩 \(Self.maxFormDepth) 초과")
      return
    }
    formDepth += 1
    saveState()
    if let matrix = Self.matrix(from: dictionary, key: "Matrix") {
      state.ctm = matrix.concatenating(state.ctm)
    }
    // /BBox는 폼 콘텐츠의 클립 (PDF 의미론 — 결정 기록).
    if let bbox = Self.rect(from: dictionary, key: "BBox") {
      var bboxBuilder = PDFPathBuilder()
      bboxBuilder.rect(bbox)
      pendingClip = .winding
      applyPendingClip(with: bboxBuilder.finish())
    }
    sinkStack.append([])
    // CGPDFContentStreamCreateWithStream の第3引数は cg_nullable だが Swift では
    // non-optional にマッピングされるため、force-unwrap で渡す（スタックは scan が
    // push した直後なので必ず非 nil）。
    let childStream = CGPDFContentStreamCreateWithStream(
      formStream, dictionary, contentStreamStack.last!)
    scan(contentStream: childStream)
    CGPDFContentStreamRelease(childStream)
    let formNodes = Self.grouped(sinkStack.removeLast())
    restoreState()
    formDepth -= 1
    if !formNodes.isEmpty {
      appendNode(.group(GroupNode(children: formNodes)))
    }
  }

  private static func matrix(
    from dictionary: CGPDFDictionaryRef, key: String
  ) -> CGAffineTransform? {
    guard let values = numbers(from: dictionary, key: key, count: 6) else { return nil }
    return CGAffineTransform(
      a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
  }

  private static func rect(from dictionary: CGPDFDictionaryRef, key: String) -> CGRect? {
    guard let values = numbers(from: dictionary, key: key, count: 4) else { return nil }
    return CGRect(
      x: values[0], y: values[1], width: values[2] - values[0],
      height: values[3] - values[1])
  }

  private static func numbers(
    from dictionary: CGPDFDictionaryRef, key: String, count: Int
  ) -> [CGFloat]? {
    var array: CGPDFArrayRef? = nil
    guard CGPDFDictionaryGetArray(dictionary, key, &array), let array,
      CGPDFArrayGetCount(array) >= count
    else { return nil }
    var values: [CGFloat] = []
    for index in 0..<count {
      var value: CGPDFReal = 0
      guard CGPDFArrayGetNumber(array, index, &value) else { return nil }
      values.append(CGFloat(value))
    }
    return values
  }

  // MARK: - 결과 조립

  /// 같은 클립의 연속 노드를 GroupNode(clipPath:)로 묶는다.
  func finalizedNodes() -> [Node] {
    Self.grouped(sinkStack[0])
  }

  private static func grouped(_ entries: [ClippedNode]) -> [Node] {
    var result: [Node] = []
    var pendingClipped: (clip: BezierPath, nodes: [Node])?

    func flushClipped() {
      if let pending = pendingClipped {
        result.append(.group(GroupNode(children: pending.nodes, clipPath: pending.clip)))
        pendingClipped = nil
      }
    }

    for entry in entries {
      if let clip = entry.clip {
        if pendingClipped?.clip == clip {
          pendingClipped?.nodes.append(entry.node)
        } else {
          flushClipped()
          pendingClipped = (clip, [entry.node])
        }
      } else {
        flushClipped()
        result.append(entry.node)
      }
    }
    flushClipped()
    return result
  }
}
