# Vecta

macOS 네이티브 벡터 그래픽 에디터. Adobe Illustrator 없이 .ai(PDF 호환)
파일을 만들고, 열고, 편집하는 것이 목표다.

## 구조

- `VectaEngine/` — 모델·렌더러·.ai 입출력·undo 스토어 (SPM, UI 의존성 없음)
- `VectaApp/` — AppKit 캔버스 + SwiftUI 패널 셸 (XcodeGen)
- `docs/superpowers/specs/` — 설계 스펙
- `docs/superpowers/plans/` — 마일스톤별 구현 계획

## 빌드

```bash
# 엔진 테스트
cd VectaEngine && swift test

# 앱 빌드 (XcodeGen 필요: brew install xcodegen)
cd VectaApp && xcodegen generate && \
  xcodebuild -project Vecta.xcodeproj -scheme Vecta \
    -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Vecta.app
```

## 현재 상태

- [x] M1 최소 루프: 도형 그리기 → .ai 저장 → 재열기 100% 복원
- [x] M2 편집: 선택/이동/리사이즈/회전/직접선택/펜
- [x] M3 스타일·구조: 그라디언트 렌더/인스펙터/레이어 패널/그룹·순서
- [x] M4a 외부 .ai 임포트: 파서 코어(패스·스타일·클립·폼)·ImportReport 배너
- [x] M4b-1 외부 .ai 임포트: 그라디언트 (sh·shading 패턴)
- [x] M4b-2 외부 .ai 임포트: 이미지
- [x] M4b-3 외부 .ai 임포트: 텍스트
- [ ] M5 텍스트·이미지·패스파인더·정렬
- [ ] M6 마감
