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
