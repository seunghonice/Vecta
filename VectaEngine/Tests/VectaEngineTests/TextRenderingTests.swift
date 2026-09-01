import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import VectaEngine

/// 멀티라인 TextRendering.bounds 계약 검증.
///
/// 계약:
/// - 폭(width)  = 줄들 중 최대 줄폭
/// - 높이(height) = 각 줄 (ascent+descent) 의 합 ≈ N × 단일 줄 높이
/// - position  = 첫 줄 baseline (단일 줄 기존 동작 보존)

private let font = "Helvetica"
private let size: CGFloat = 24
private let origin = CGPoint(x: 10, y: 50)
private let heightTolerance: CGFloat = 2.0

// MARK: - 1. 멀티라인 높이 = 단일 줄 높이의 약 N배

@Test func multilineBoundsHeightIsApproximatelyNTimesLineHeight() {
  // Arrange
  let singleLine = "A"
  let threeLines = "A\nBB\nCCC"

  // Act
  let singleBounds = TextRendering.bounds(
    string: singleLine, fontName: font, fontSize: size, position: origin)
  let multiBounds = TextRendering.bounds(
    string: threeLines, fontName: font, fontSize: size, position: origin)

  // Assert: 3줄 높이가 단일 줄 높이의 약 3배 (±작은 오차)
  let expected = singleBounds.height * 3
  #expect(
    abs(multiBounds.height - expected) < heightTolerance,
    "3줄 높이(\(multiBounds.height))가 단일 줄 높이(\(singleBounds.height))의 3배(\(expected))와 다름"
  )
}

// MARK: - 2. 멀티라인 폭 = 가장 긴 줄의 폭

@Test func multilineBoundsWidthEqualsLongestLineWidth() {
  // Arrange: "A\nBB\nCCC" — 가장 긴 줄은 "CCC"
  let threeLines = "A\nBB\nCCC"
  let longestLine = "CCC"

  // Act
  let multiBounds = TextRendering.bounds(
    string: threeLines, fontName: font, fontSize: size, position: origin)
  let longestBounds = TextRendering.bounds(
    string: longestLine, fontName: font, fontSize: size, position: origin)

  // Assert: 폭이 최장 줄 폭과 동일 (소수점 오차)
  #expect(
    abs(multiBounds.width - longestBounds.width) < 1.0,
    "멀티라인 폭(\(multiBounds.width))이 최장 줄 폭(\(longestBounds.width))과 다름"
  )
}

// MARK: - 3. 단일 줄 회귀: "Hello" 동작 보존

@Test func singleLineBoundsMatchExpectedGeometry() {
  // Arrange
  let string = "Hello"
  let pos = CGPoint(x: 5, y: 30)

  // Act
  let bounds = TextRendering.bounds(
    string: string, fontName: font, fontSize: size, position: pos)

  // Assert: 폭·높이 모두 양수
  #expect(bounds.width > 0, "단일 줄 폭이 0")
  #expect(bounds.height > 0, "단일 줄 높이가 0")

  // 기존 계약: position이 baseline → rect.minY < position.y (ascent 위쪽)
  // 모델 top-down: baseline 위 = y 작은 방향
  #expect(
    bounds.minY < pos.y,
    "bounds.minY(\(bounds.minY))가 baseline(\(pos.y)) 위(y 작은 방향)에 있어야 함"
  )
  // descent: baseline 아래 = y 큰 방향
  #expect(
    bounds.maxY > pos.y,
    "bounds.maxY(\(bounds.maxY))가 baseline(\(pos.y)) 아래(y 큰 방향)에 있어야 함"
  )

  // 높이 = ascent + descent (CTTypographicBounds와 일치)
  // 비교 기준: advanceWidth는 별도 함수로 존재 — 여기서는 폭 일관성만 확인
  let advance = TextRendering.advanceWidth(
    string: string, fontName: font, fontSize: size)
  #expect(
    abs(bounds.width - advance) < 1.0,
    "단일 줄 폭(\(bounds.width))이 advanceWidth(\(advance))와 다름"
  )
}

// MARK: - 4. 빈 문자열·fontSize 0 가드

@Test func emptyStringReturnsZeroSizeAtPosition() {
  // Arrange & Act
  let bounds = TextRendering.bounds(
    string: "", fontName: font, fontSize: size, position: origin)

  // Assert
  #expect(bounds.origin == origin, "빈 문자열 bounds.origin이 position과 다름")
  #expect(bounds.size == .zero, "빈 문자열 bounds.size가 zero가 아님")
}

@Test func zeroFontSizeReturnsZeroSizeAtPosition() {
  // Arrange & Act
  let bounds = TextRendering.bounds(
    string: "Hello", fontName: font, fontSize: 0, position: origin)

  // Assert
  #expect(bounds.origin == origin, "fontSize=0 bounds.origin이 position과 다름")
  #expect(bounds.size == .zero, "fontSize=0 bounds.size가 zero가 아님")
}

// MARK: - 5. trailing / 중간 빈 줄도 한 줄로 계산 (R1)

@Test func trailingAndEmptyLinesCountAsLines() {
  let single = TextRendering.bounds(
    string: "A", fontName: font, fontSize: size, position: origin)
  let trailing = TextRendering.bounds(
    string: "A\n", fontName: font, fontSize: size, position: origin)
  let middleEmpty = TextRendering.bounds(
    string: "A\n\nB", fontName: font, fontSize: size, position: origin)

  // "A\n" = 2줄(마지막 빈 줄 포함), "A\n\nB" = 3줄
  #expect(
    abs(trailing.height - single.height * 2) < heightTolerance,
    "trailing \\n 높이(\(trailing.height))가 2줄(\(single.height * 2))과 다름")
  #expect(
    abs(middleEmpty.height - single.height * 3) < heightTolerance,
    "중간 빈 줄 높이(\(middleEmpty.height))가 3줄(\(single.height * 3))과 다름")
}

// MARK: - 6. lines() 의 dy 누적이 bounds().height 와 일관 (렌더↔측정 단일 규칙)

@Test func linesDyAccumulationMatchesBoundsHeight() {
  let string = "A\nBB\nCCC"
  let entries = TextRendering.lines(
    string: string, fontName: font, fontSize: size, color: .black)
  let bounds = TextRendering.bounds(
    string: string, fontName: font, fontSize: size, position: origin)

  #expect(entries.count == 3, "줄 수(\(entries.count))가 3이 아님")
  // dy 단조 증가 (첫 줄 0, 이후 누적)
  for index in 1..<entries.count {
    #expect(entries[index].dy > entries[index - 1].dy, "dy가 단조 증가하지 않음")
  }
  // 전체 높이 = 첫 줄 ascent + (마지막 줄 baseline dy + 마지막 줄 descent).
  // 동일 폰트라 첫 줄 ascent == 마지막 줄 ascent.
  var ascent: CGFloat = 0
  var descent: CGFloat = 0
  _ = CTLineGetTypographicBounds(entries[entries.count - 1].ctLine, &ascent, &descent, nil)
  let expectedHeight = ascent + entries[entries.count - 1].dy + descent
  #expect(
    abs(bounds.height - expectedHeight) < heightTolerance,
    "lines() dy 누적(\(expectedHeight))이 bounds 높이(\(bounds.height))와 불일치")
}
