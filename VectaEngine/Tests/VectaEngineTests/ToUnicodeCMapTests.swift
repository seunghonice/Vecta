import Testing

@testable import VectaEngine

private let sampleCMap = """
  /CIDInit /ProcSet findresource begin
  12 dict begin begincmap
  /CMapName /Adobe-Identity-UCS def
  1 begincodespacerange
  <0000> <FFFF>
  endcodespacerange
  2 beginbfchar
  <0041> <0041>
  <0042> <00E9>
  endbfchar
  1 beginbfrange
  <0061> <0063> <0061>
  endbfrange
  endcmap
  """

@Test func parsesBfcharSingleMappings() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  #expect(cmap.string(forCode: 0x41) == "A")
  #expect(cmap.string(forCode: 0x42) == "é")  // 0x00E9
}

@Test func parsesBfrangeMappings() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  #expect(cmap.string(forCode: 0x61) == "a")
  #expect(cmap.string(forCode: 0x62) == "b")
  #expect(cmap.string(forCode: 0x63) == "c")
}

@Test func unmappedCodeReturnsNil() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  #expect(cmap.string(forCode: 0x99) == nil)
}

@Test func decodesByteSequenceWithCodeWidth() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  // 1바이트 코드: 0x41 0x42 0x61 → "Aéa"
  #expect(cmap.decode([0x41, 0x42, 0x61], codeBytes: 1) == "Aéa")
}

@Test func twoByteCodeDecodes() {
  let cmap = ToUnicodeCMap.parse(sampleCMap)
  // 2바이트 코드: 0x00 0x41 → "A"
  #expect(cmap.decode([0x00, 0x41], codeBytes: 2) == "A")
}

@Test func bfrangeWithArrayDestinations() {
  let arrayCMap = """
    1 beginbfrange
    <0080> <0082> [<0041> <0042> <0043>]
    endbfrange
    endcmap
    """
  let cmap = ToUnicodeCMap.parse(arrayCMap)
  #expect(cmap.string(forCode: 0x80) == "A")
  #expect(cmap.string(forCode: 0x81) == "B")
  #expect(cmap.string(forCode: 0x82) == "C")
}

@Test func multiCharDestination() {
  // dst가 여러 UTF-16 코드유닛 (예: ﬁ ligature → "fi")
  let ligCMap = """
    1 beginbfchar
    <0001> <00660069>
    endbfchar
    endcmap
    """
  let cmap = ToUnicodeCMap.parse(ligCMap)
  #expect(cmap.string(forCode: 0x01) == "fi")
}

@Test func skipsCommentLinesWithHexTokens() {
  // 주석(% ...) 안의 hex 토큰이 매핑을 오염시키지 않는다
  let cmap = """
    % 주석 안 <00AA> 토큰은 무시되어야 한다
    2 beginbfchar
    <0041> <0042>
    % 블록 중간 주석 <00BB>
    <0043> <0044>
    endbfchar
    endcmap
    """
  let parsed = ToUnicodeCMap.parse(cmap)
  #expect(parsed.string(forCode: 0x41) == "B")  // 실제 매핑 보존
  #expect(parsed.string(forCode: 0x43) == "D")
  #expect(parsed.string(forCode: 0xAA) == nil)  // 주석 hex 무시
  #expect(parsed.string(forCode: 0xBB) == nil)
}

@Test func surrogatePairDestinationDecodes() {
  // 이모지(U+1F600) = UTF-16 서로게이트 쌍 <D83DDE00>
  let cmap = """
    1 beginbfchar
    <0001> <D83DDE00>
    endbfchar
    endcmap
    """
  let parsed = ToUnicodeCMap.parse(cmap)
  #expect(parsed.string(forCode: 0x01) == "😀")
}

@Test func countTokenBeforeBlockIsSkipped() {
  // beginbfchar 앞의 카운트 정수가 매핑을 깨지 않는다
  let cmap = """
    3 beginbfchar
    <0041> <0042>
    endbfchar
    endcmap
    """
  let parsed = ToUnicodeCMap.parse(cmap)
  #expect(parsed.string(forCode: 0x41) == "B")
}
