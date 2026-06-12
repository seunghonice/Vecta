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
    /// scn으로 지정된 fill 패턴 이름 (Pattern 색공간일 때).
    var fillPattern: String?
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
  /// 클립 없는 sh의 폴백 패스 (모델 좌표 mediaBox 사각형).
  private let mediaBoxPath: BezierPath

  init(mediaBox: CGRect) {
    pageFlip = CGAffineTransform(
      a: 1, b: 0, c: 0, d: -1, tx: -mediaBox.minX, ty: mediaBox.maxY)
    var builder = PDFPathBuilder()
    builder.rect(CGRect(origin: .zero, size: mediaBox.size))
    mediaBoxPath = builder.finish()
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
    // 셰이딩 (M4b-1)
    CGPDFOperatorTableSetCallback(table, "sh") { scanner, info in
      parserFrom(info).paintShading(scanner)
    }
    CGPDFOperatorTableSetCallback(table, "BT") { _, info in
      parserFrom(info).reportTextOnce()
    }
    // ID/EI는 의도적으로 미등록 — CGPDFScanner가 인라인 이미지 페이로드를
    // 내부에서 소비하므로 BI만 받아도 스캐너가 어긋나지 않는다.
    CGPDFOperatorTableSetCallback(table, "BI") { _, info in
      parserFrom(info).reportInlineImageOnce()
    }
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
      state.fillPattern = nil
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
      // 모든 fill cs는 패턴을 초기화 — 정당한 /Pattern cs /P1 scn은 scn이 다시 설정.
      state.fillPattern = nil
    }
  }

  private func setColorComponents(_ scanner: CGPDFScannerRef, isStroke: Bool) {
    let space = isStroke ? state.strokeColorSpace : state.fillColorSpace
    if space == .pattern {
      let name = Self.popName(scanner)
      if isStroke {
        report.add(.unsupportedShading, detail: "패턴 스트로크 — 미지원")
      } else if let name {
        // scn /P1 — 패턴 이름 기록 (해석은 페인팅 시점).
        state.fillPattern = name
      }
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
      if let patternName = state.fillPattern {
        style.fill = resolveShadingPatternFill(patternName)  // nil이면 채움 없음
      } else {
        style.fill = .color(state.fillColor)
      }
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
      paintImage(xobjectStream, dictionary: dictionary)
    default:
      break
    }
  }

  /// image XObject → ImageNode. frame=unit square, 배치는 transform에 베이크
  /// (CTM × pageFlip). 디코드 실패·미지원이면 노드 없이 리포트만.
  private func paintImage(_ stream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef) {
    let (png, unsupported) = PDFImageDecoder.decode(stream, dictionary: dictionary)
    if let unsupported {
      report.add(.unsupportedImage, detail: unsupported)
      return
    }
    guard let png else {
      report.add(.unsupportedImage, detail: "이미지 디코드 실패")
      return
    }
    let toModel = state.ctm.concatenating(pageFlip)
    let node = ImageNode(
      imageData: png, frame: CGRect(x: 0, y: 0, width: 1, height: 1),
      transform: Transform2D(toModel))
    appendNode(.image(node), explicitClip: state.clip)
  }

  private func invokeForm(_ formStream: CGPDFStreamRef, dictionary: CGPDFDictionaryRef) {
    guard formDepth < Self.maxFormDepth else {
      report.add(.formRecursionLimit, detail: "폼 중첩 \(Self.maxFormDepth) 초과")
      return
    }
    formDepth += 1
    saveState()
    // 부모의 미완 패스가 폼 경계를 넘지 않게 격리한다 (스펙상 path 중 Do는
    // 금지지만 부정형 입력 방어 — saveState 패턴과 대칭).
    let parentPathBuilder = pathBuilder
    pathBuilder = PDFPathBuilder()
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
    // CGPDFContentStreamCreateWithStream의 2번째 인자는 폼의 /Resources 사전이다
    // (스트림 사전 전체가 아님 — 전체를 넘기면 폼 내부 리소스 조회가 전부 실패).
    // Swift에서 이 인자는 non-optional로 임포트되므로 /Resources 가 없는 폼은
    // 스트림 사전 자체를 폴백으로 전달한다. /Resources 키가 없는 폼은 내부에서
    // XObject/ExtGState 등을 참조하지 않으므로 실질 영향 없음.
    // 3번째 인자는 C에서 nullable이지만 Swift에는 non-optional로 임포트된다.
    // Do 콜백은 scan()이 스택에 push한 뒤 동기적으로 호출되므로 last는 항상
    // 비-nil — force-unwrap 안전.
    var formResources: CGPDFDictionaryRef? = nil
    _ = CGPDFDictionaryGetDictionary(dictionary, "Resources", &formResources)
    let resourcesForChild = formResources ?? dictionary
    let childStream = CGPDFContentStreamCreateWithStream(
      formStream, resourcesForChild, contentStreamStack.last!)
    scan(contentStream: childStream)
    CGPDFContentStreamRelease(childStream)
    let formNodes = Self.grouped(sinkStack.removeLast())
    pathBuilder = parentPathBuilder
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

  // MARK: - 셰이딩 (M4b-1)

  /// sh 연산자 — Shading 리소스를 그라디언트로 변환해 현재 클립(없으면
  /// mediaBox) 패스에 fill한다.
  private func paintShading(_ scanner: CGPDFScannerRef) {
    guard let name = Self.popName(scanner),
      let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "Shading", name)
    else {
      report.add(.unsupportedShading, detail: "셰이딩 리소스를 찾지 못함")
      return
    }
    guard let parsed = PDFShading.parse(object) else {
      report.add(.unsupportedShading, detail: "미지원 셰이딩 (mesh·function type·색공간)")
      return
    }
    if parsed.lossyRadial {
      report.add(.unsupportedShading, detail: "원형 셰이딩 근사 — 끝 원만 반영 (시작 원 무시)")
    }
    if parsed.lossyFunction {
      report.add(.unsupportedShading, detail: "성분별 분리 함수 근사 — 첫 함수만 반영")
    }
    let toModel = state.ctm.concatenating(pageFlip)
    let gradient = parsed.gradient.applying(toModel)
    let paint: Paint =
      parsed.isRadial ? .radialGradient(gradient) : .linearGradient(gradient)
    // sh는 클립 영역을 채운다 — 클립 패스를 fill 패스로 사용하므로
    // 별도 clip 래퍼 없이 노드를 직접 추가한다 (클립이 없으면 mediaBox 전체).
    let fillPath = state.clip ?? mediaBoxPath
    appendNode(
      .path(PathNode(path: fillPath, style: Style(fill: paint, opacity: state.fillAlpha))),
      explicitClip: nil)
  }

  /// fill 패턴 이름 → 그라디언트 Paint. PatternType 2(shading)만 지원하며
  /// tiling(type 1)·해석 실패는 리포트 후 nil (채움 스킵).
  private func resolveShadingPatternFill(_ name: String) -> Paint? {
    guard let stream = contentStreamStack.last,
      let object = CGPDFContentStreamGetResource(stream, "Pattern", name),
      let dictionary = CGPDFReading.dictionary(from: object)
    else {
      report.add(.unsupportedShading, detail: "패턴 리소스를 찾지 못함")
      return nil
    }
    guard CGPDFReading.integer(dictionary, "PatternType") == 2 else {
      report.add(.unsupportedShading, detail: "타일링 패턴 (반복 콘텐츠 — 미지원)")
      return nil
    }
    guard let shadingObject = CGPDFReading.object(dictionary, "Shading"),
      let parsed = PDFShading.parse(shadingObject)
    else {
      report.add(.unsupportedShading, detail: "패턴 셰이딩 변환 실패")
      return nil
    }
    if parsed.lossyRadial {
      report.add(.unsupportedShading, detail: "원형 패턴 근사 — 끝 원만 반영")
    }
    if parsed.lossyFunction {
      report.add(.unsupportedShading, detail: "성분별 분리 함수 근사 — 첫 함수만 반영")
    }
    // 패턴 좌표 = pattern /Matrix × pageFlip (CTM 미적용 — 결정 기록).
    let patternMatrix = Self.matrix(from: dictionary, key: "Matrix") ?? .identity
    let toModel = patternMatrix.concatenating(pageFlip)
    let gradient = parsed.gradient.applying(toModel)
    return parsed.isRadial ? .radialGradient(gradient) : .linearGradient(gradient)
  }

  // MARK: - 미지원 요소 리포트

  /// BT 연산자 — 파스당 한 번만 보고한다.
  fileprivate func reportTextOnce() {
    guard !didReportText else { return }
    didReportText = true
    report.add(.unsupportedText, detail: "텍스트 (M4b에서 지원 예정)")
  }

  /// BI 연산자 — 파스당 한 번만 보고한다.
  fileprivate func reportInlineImageOnce() {
    guard !didReportInlineImage else { return }
    didReportInlineImage = true
    report.add(.unsupportedImage, detail: "인라인 이미지 (M4b에서 지원 예정)")
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
