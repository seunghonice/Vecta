# Vecta 개발 명령. 엔진은 SPM(VectaEngine), 앱은 XcodeGen(VectaApp).

.PHONY: run generate build test format clean

# 기본 — 앱을 Debug로 빌드해 실행한다.
run: generate build
	open VectaApp/build/Build/Products/Debug/Vecta.app

# Xcode 프로젝트 생성 (XcodeGen).
generate:
	cd VectaApp && xcodegen generate

# 앱 Debug 빌드 (증분 — 변경분만 다시 컴파일).
build:
	cd VectaApp && xcodebuild -project Vecta.xcodeproj -scheme Vecta \
		-configuration Debug -derivedDataPath build build

# 엔진 테스트.
test:
	cd VectaEngine && swift test

# 코드 포맷 (엔진 + 앱).
format:
	cd VectaEngine && swift format --in-place --recursive Sources Tests
	swift format --in-place --recursive VectaApp/Sources

# 빌드 산출물·생성된 프로젝트 정리.
clean:
	rm -rf VectaApp/build VectaEngine/.build VectaApp/Vecta.xcodeproj
