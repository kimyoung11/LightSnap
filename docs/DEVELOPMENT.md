# 개발과 버전업 절차

## 작업 시작

```sh
git status --short
git log -3 --oneline
swift --version
```

사용자 변경을 먼저 확인한다. 스크립트는 자신의 위치를 기준으로 저장소 루트로 이동한다. 일반 개발에 Apple 계정·API 키·서명 인증서는 필요 없다.

## 검사

```sh
./scripts/test.sh
./scripts/build-app.sh
plutil -lint dist/LightSnap.app/Contents/Info.plist
codesign --verify --strict --verbose dist/LightSnap.app
git diff --check
```

검사는 `swiftc`로 제품 코드 일부와 `Tests/main.swift`를 직접 컴파일한다. `swift test`를 쓰는 XCTest 타깃은 없다. UI 진입점 main.swift는 테스트 실행기에 포함하지 않으며 전체 앱 빌드로 컴파일을 확인한다. 새 파일을 추가하면 제품 타깃은 SwiftPM이 찾지만 검사 스크립트의 명시적 파일 목록은 직접 갱신해야 한다.

기능 변경에는 관련 검사, 문서 변경에는 상대 링크·소스 일치성 검증을 수행한다. 고정 assertion 개수를 성공 기준으로 삼지 말고 실제 명령의 종료와 출력을 확인한다.

## 기능별 수정 지도

| 작업 | 주 수정 파일 | 필요한 확인 |
| --- | --- | --- |
| 고정 배치 추가 | Layout, 필요 시 UI/마이그레이션 | 공유 경계·음수 좌표·기존 단축키 유지 |
| 모니터 이동 정책 | WindowActions, SnapEngine | 순서·해상도·화면 분리·단일/미러링 |
| 크기 순환 정책 | CycleTracker, SnapEngine | 실패·수동 이동·창/화면 전환·설정 끄기 |
| 단축키 설정 | Hotkeys, main | 충돌 복구·해제 유지·편집 취소·일시정지 |
| 로그인 실행 | LoginItem, main | enabled/approval/error, 실제 재로그인 |
| 진단·로그 | Diagnostics, main, 필요 시 AX 래퍼 | 개인정보·스키마·메모리 상한·성공 0회 |
| 배포 | build-app.sh, CI, RELEASING | 버전·아키텍처·서명·공증·업데이트 설치 |

## 자동 검사로 증명하지 못하는 것

다른 앱의 실제 AX 응답, Carbon의 실제 전역 키 전달, TCC 허용, UI 레이아웃, 로그인 실행, 대표적인 장시간 메모리·전력은 따로 확인한다. Finder와 브라우저·Terminal, 최소 크기 창, 전체 화면, 다중 화면, 권한 취소·재연결을 포함한다. 사용자 Mac의 권한·로그인 항목을 테스트가 임의 변경하지 않도록 주입한 서비스를 사용한다.

## 버전 올릴 위치

제품 동작을 배포하는 버전업일 때 함께 변경한다. 문서만 바꾸는 커밋에는 앱 버전을 올릴 필요가 없다.

- `scripts/build-app.sh`: CFBundleShortVersionString과 증가하는 CFBundleVersion
- `main.swift`: 현재 하드코딩된 설정창 제목의 버전
- `README.md`: 현재 버전과 사용법
- `CHANGELOG.md`: 사용자 관점 변경 및 마이그레이션 주의
- `VALIDATION.md`: 실행한 검사, 실제 확인, 미확인 항목
- 이 문서들과 핸드오프의 기준 버전 설명이 사실과 맞는지 확인

다음 개선 후보는 단일 VERSION 파일 또는 빌드 메타데이터에서 제목·plist·문서를 연결하는 것이다. 아직 구현되어 있지 않다.

## 커밋 전

추적할 파일을 확인하고 `.build/`, `dist/`, `reports/`, 진단/크래시 파일, .env, 인증서·개인키를 제외한다. `.gitignore`는 이미 추적된 파일이나 과거 커밋을 지워주지 않는다. Git author 이메일도 공개 범위에 맞게 확인한다.

보안 스캔의 기준·도입안은 SECURITY_AND_LOGGING 문서를 참고한다. 현재 CI에 전용 비밀정보 스캐너는 없다. 검사 결과는 탐지 도구·대상·커밋을 함께 적고 ‘유출 가능성 0’으로 단정하지 않는다.

## 작업 종료 인계

변경한 동작, 검사 명령/결과, 수동 미확인 항목, 저장 형식·권한·리소스 영향, 다음 작업을 HANDOFF의 템플릿으로 요약한다. 코드와 제안 로드맵을 혼동하지 않는다.

## 브라우저 미리보기 수정

`preview/`는 앱 기능을 보여주는 별도 정적 페이지다. `model.mjs`가 Swift 동작을 수동으로 재현하며 실제 AX·Carbon 코드를 실행하지 않는다. 기능이 바뀌면 두 구현의 의미가 같은지 검토한다.

```sh
node --test preview/model.test.mjs
node --check preview/app.mjs
python3 -m http.server 4173 --bind 127.0.0.1 --directory preview
```

웹 검사에는 Node.js가 필요하지만 네이티브 앱 빌드에는 필요 없다. 브라우저에서 배치·반복·복원·모니터 전환·키보드·작은 화면을 확인한다. README의 캡처와 배너는 브라우저 데모/디자인 일러스트라고 구분한다.

호스팅 정보는 `preview/hosting.json`, 게시 방법과 비공개 범위는 `preview/README.md`에 있다. 실제 배포 체크아웃은 별도 Sites 프로젝트로 관리한다. 저장소 공개 여부를 바꿔도 Sites 방문 범위가 함께 바뀌지는 않는다.
