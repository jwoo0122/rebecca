# Rebecca macOS 앱 패키징 및 CI 정비

Rebecca는 Rust로 구현된 macOS computer-use 애플리케이션이다.

현재 목표는 다음과 같다.

1. Rust 바이너리를 정식 `Rebecca.app` 번들로 패키징한다.
2. Xcode 26 및 Icon Composer의 `.icon` 형식을 사용해 macOS 26 Liquid Glass 아이콘을 지원한다.
3. 일반 CI와 macOS 릴리스 CI를 분리한다.
4. 로컬과 CI에서 동일한 명령으로 재현 가능한 패키징 과정을 만든다.
5. 추후 Developer ID 서명과 Apple notarization을 추가할 수 있도록 구조를 준비한다.

## 책임 분리

Rust/Cargo가 담당할 범위:

* 애플리케이션 컴파일
* 단위·통합 테스트
* `cargo fmt`
* `cargo clippy`
* 아키텍처별 실행 파일 생성

Xcode가 담당할 범위:

* `.app` 번들 구조 생성
* `Info.plist`
* Icon Composer의 `AppIcon.icon` 컴파일
* entitlements 연결
* Rust 바이너리를 `Contents/MacOS/Rebecca`에 배치
* 코드 서명
* Archive 또는 배포 산출물 생성

Xcode 프로젝트에 Swift 또는 Objective-C 애플리케이션 로직을 추가하지 않는다. 필요한 경우 빌드 대상 구성을 위한 최소 placeholder만 사용하고, 실제 진입점은 Rust 바이너리로 유지한다.

## 예상 저장소 구조

현재 저장소 구조를 먼저 조사한 후, 기존 관례를 존중하면서 대략 다음 역할이 분명하게 드러나도록 정리한다.

```text
rebecca/
├── Cargo.toml
├── Cargo.lock
├── src/
├── macos/
│   ├── Rebecca.xcodeproj/
│   ├── Info.plist
│   ├── Rebecca.entitlements
│   └── AppIcon.icon
├── scripts/
│   ├── build-macos-app.sh
│   ├── verify-macos-app.sh
│   └── release-macos.sh
└── .github/
    └── workflows/
        ├── ci.yml
        └── release.yml
```

`AppIcon.icon`은 사용자가 Xcode와 Icon Composer를 이용해 직접 제작할 예정이다. 초기 작업에서는 유효한 아이콘 파일이 없어도 프로젝트 구조와 CI가 가능한 범위까지 동작하도록 한다.

아이콘 파일이 아직 없다면 다음 중 하나로 처리한다.

* Xcode 프로젝트가 임시 기본 아이콘으로 빌드되도록 구성한다.
* 또는 `macos/AppIcon.icon`이 없을 때 명확한 오류 메시지와 함께 패키징 단계만 실패하도록 한다.

불완전하거나 임의로 생성한 `.icon` 파일을 커밋하지 않는다.

## 로컬 빌드 인터페이스

다음과 같이 하나의 공개된 명령으로 앱 번들을 만들 수 있도록 한다.

```bash
./scripts/build-macos-app.sh
```

스크립트 요구사항:

* 저장소 루트 외부에서 실행해도 정상적으로 루트를 찾는다.
* `set -euo pipefail`을 사용한다.
* 필요한 명령이 없으면 명확하게 실패한다.
* `cargo build --release --locked`를 실행한다.
* 생성된 Rust 바이너리의 실제 경로를 확인한다.
* `xcodebuild`를 호출한다.
* DerivedData는 저장소 외부 또는 명시적인 임시 디렉터리에 둔다.
* 최종 산출물 경로를 안정적으로 출력한다.
* 결과물을 예를 들어 `dist/Rebecca.app`으로 복사한다.
* 스크립트가 Xcode GUI 상태나 사용자별 DerivedData 위치에 의존하지 않게 한다.
* 개발용 로컬 빌드에서는 기본적으로 ad-hoc signing 또는 signing 비활성화를 허용한다.

예상 인터페이스:

```bash
./scripts/build-macos-app.sh
./scripts/build-macos-app.sh --release
./scripts/build-macos-app.sh --arch arm64
```

현재 프로젝트가 universal binary를 지원하지 않는다면 처음부터 억지로 추가하지 않는다. 우선 현재 지원 아키텍처를 정확히 문서화한다.

## Xcode 프로젝트

최소 macOS Application target을 구성한다.

요구사항:

* Product Name: `Rebecca`
* Executable Name: `Rebecca`
* Bundle Identifier는 환경 또는 build setting으로 재정의할 수 있게 한다.
* Deployment target은 현재 사용 중인 macOS API 요구사항을 조사해 결정한다.
* `Info.plist`와 entitlements를 저장소에서 명시적으로 관리한다.
* Rust 바이너리 경로는 `RUST_BINARY_PATH` build setting으로 전달받는다.
* Build Phase에서 해당 바이너리를 앱 번들 내부로 복사한다.
* 복사된 파일에 실행 권한을 설정한다.
* 바이너리가 전달되지 않았거나 존재하지 않으면 빌드를 즉시 실패시킨다.
* 앱 아이콘 source는 최종적으로 `AppIcon.icon`을 사용하도록 준비한다.
* 기존 `.icns` 또는 asset catalog 설정과 충돌하지 않게 한다.
* 사용자별 signing team이나 로컬 절대 경로를 `.pbxproj`에 기록하지 않는다.
* Xcode의 automatic signing에 CI가 암묵적으로 의존하지 않게 한다.

Rust 바이너리가 Xcode가 생성한 placeholder 실행 파일을 대체하는 방식이라면, 최종 앱의 `CFBundleExecutable`과 실제 파일명이 반드시 일치하는지 검증한다.

## 검증 스크립트

다음 명령을 제공한다.

```bash
./scripts/verify-macos-app.sh dist/Rebecca.app
```

최소 검증 항목:

```bash
test -d Rebecca.app
test -f Rebecca.app/Contents/Info.plist
test -x Rebecca.app/Contents/MacOS/Rebecca
plutil -lint Rebecca.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 Rebecca.app
```

추가로 다음을 검사한다.

* `CFBundleIdentifier`
* `CFBundleName`
* `CFBundleDisplayName`
* `CFBundleExecutable`
* minimum system version
* entitlement 내용
* 앱 실행 파일의 아키텍처
* 앱 아이콘 리소스가 실제 번들에 포함되었는지
* 앱이 로컬에서 실행 가능한지

코드 서명이 비활성화된 개발 빌드에서는 서명 검증을 조건부로 건너뛰되, 나머지 번들 검증은 수행한다.

## GitHub Actions 일반 CI

기존 CI를 조사하고 중복을 최소화한다.

일반 PR 및 push CI는 다음만 수행한다.

* `cargo fmt --check`
* `cargo clippy --all-targets --all-features -- -D warnings`
* `cargo test --all-features --locked`
* 필요하다면 Rust 바이너리 release build

이 작업은 가능한 한 Linux runner에서 수행한다. macOS 전용 코드 때문에 Linux에서 컴파일할 수 없다면 macOS runner를 사용하되, 그 이유를 workflow 주석이나 문서에 남긴다.

일반 CI에서는 다음을 수행하지 않는다.

* Developer ID 인증서 설치
* notarization
* GitHub Release 업로드
* DMG 생성
* 민감한 signing secret 접근

## GitHub Actions macOS 패키징 CI

macOS 패키징을 검증하는 별도 job을 만든다.

PR마다 실행할지, 기본 브랜치에서만 실행할지는 기존 CI 비용과 현재 runner 지원 상황을 보고 결정한다. 최소한 기본 브랜치와 릴리스 태그에서는 실행되어야 한다.

작업 순서:

1. checkout
2. Rust toolchain 설치
3. Cargo cache 복원
4. 설치된 Xcode 버전 확인
5. 필요한 Xcode 버전 선택
6. Rust release binary 빌드
7. `build-macos-app.sh` 실행
8. `verify-macos-app.sh` 실행
9. unsigned 또는 ad-hoc signed `.app`을 artifact로 업로드

GitHub-hosted runner의 특정 Xcode 설치 경로를 추측해서 하드코딩하지 않는다. runner image가 제공하는 Xcode 목록을 확인하거나, 검증된 Xcode 선택 action 또는 설치 경로 탐색 로직을 사용한다.

CI 로그에 다음 정보를 출력한다.

```bash
sw_vers
uname -m
xcodebuild -version
xcode-select -p
rustc --version
cargo --version
```

## Release workflow

Release workflow는 `main` push에서 실행되며, `scripts/next-release-version.sh`가
최신 semantic version tag 이후의 Conventional Commit을 분석한다.

버전 규칙은 다음과 같다.

* `feat` → minor 증가
* `fix`, `perf` → patch 증가
* `BREAKING CHANGE` 또는 `!` → major 증가
* `docs`, `test`, `ci`, `chore`만 포함된 push → release 없음

release-worthy commit이 있으면 workflow가 다음 순서로 처리한다.

1. 새 version tag 생성
2. Rust CLI와 Swift host 빌드
3. `Contents/Resources/bin/rebecca`를 내부부터 Developer ID로 서명
4. hardened runtime과 secure timestamp를 적용해 앱 서명
5. 서명 검증
6. ZIP 생성
7. `xcrun notarytool submit --wait` 및 `Accepted` 상태 확인
8. ticket staple 및 검증
9. GitHub Release와 ZIP asset 생성
10. ZIP SHA-256으로 `jwoo0122/homebrew-tap/Casks/rebecca.rb` 갱신

Homebrew tap 갱신에는 `HOMEBREW_TAP_TOKEN` secret을 사용한다. Cask는 다음
명령으로 설치할 수 있다.

```bash
brew tap jwoo0122/tap
brew install --cask jwoo0122/tap/rebecca
rebecca status
```

Apple 인증서와 private key는 저장소에 넣지 않는다. GitHub encrypted secret을
사용하고, workflow 종료 시 임시 keychain과 인증서 파일을 삭제한다.

## 접근성 및 화면 캡처 권한

Rebecca는 computer-use 앱이므로 다음 영역을 조사한다.

* Accessibility 권한
* Screen Recording 또는 Screen & System Audio Recording 권한
* Automation/Apple Events 권한 사용 여부
* Input Monitoring 필요 여부
* hardened runtime과 관련된 entitlements
* TCC 권한이 bundle identifier 및 code signature 변경에 의해 초기화되는지 여부

불필요한 entitlement를 추가하지 않는다.

권한 요청과 entitlement를 혼동하지 않는다. TCC 사용자 동의가 필요한 기능은 앱 실행 중 실제 API 접근 시 적절한 안내와 함께 요청되어야 한다.

현재 코드가 실제로 사용하는 API를 근거로 필요한 entitlement만 확정한다.

## 문서화

다음을 README 또는 `docs/macos-distribution.md`에 문서화한다.

* 개발 환경 요구사항
* 필요한 macOS 및 Xcode 버전
* Icon Composer 아이콘을 사용자가 추가하는 방법
* 로컬 앱 빌드 명령
* 앱 검증 명령
* unsigned CI와 signed release의 차이
* Apple Developer Program이 필요한 단계
* 필요한 GitHub Secrets
* 인증서 갱신 방법
* notarization 실패 시 로그 확인 방법
* 최종 산출물 위치

## 테스트 기준

작업 완료 조건:

1. 깨끗한 checkout에서 문서화된 단일 명령으로 `Rebecca.app`을 생성할 수 있다.
2. 앱 내부 실행 파일이 Rust release binary와 일치한다.
3. Xcode GUI를 열지 않고 CLI만으로 앱을 재빌드할 수 있다.
4. Icon Composer의 `.icon` 파일을 추가한 후 추가적인 수동 export 없이 CI에서 아이콘이 포함된다.
5. GitHub Actions에서 unsigned macOS 앱 artifact가 생성된다.
6. signing secret이 없을 때 일반 CI와 unsigned packaging CI가 실패하지 않는다.
7. signing secret이 있을 때 signed/notarized release 경로를 활성화할 수 있다.
8. 사용자별 절대 경로, Team ID, 인증서 이름 또는 비밀 값이 저장소에 커밋되지 않는다.
9. 빌드 및 검증 스크립트가 실패 원인을 명확하게 출력한다.
10. 기존 Rust 테스트와 개발 흐름을 불필요하게 변경하지 않는다.

## 작업 방식

먼저 저장소와 기존 GitHub Actions, 번들링 방식, entitlements, 배포 스크립트를 조사한다.

그 후 다음 순서로 진행한다.

1. 현재 상태와 문제점 요약
2. 최소 변경 설계 제안
3. 로컬 패키징 구현
4. 검증 스크립트 구현
5. 일반 CI 정리
6. unsigned macOS packaging CI 구현
7. release signing/notarization 뼈대 구현
8. 문서화
9. 실제 명령 실행 결과와 남은 수동 작업 보고

확인되지 않은 Apple signing 설정이나 bundle identifier를 임의로 결정하지 않는다. 사용자가 입력해야 하는 값은 placeholder와 명확한 TODO로 남긴다.

