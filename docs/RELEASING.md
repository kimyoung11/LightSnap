# 릴리스와 배포

현재 구현과 앞으로 구성할 정식 배포 절차를 구분한다. 문서의 공증 명령은 절차 예시이며 현재 스크립트가 자동 수행하지 않는다. 실제 인증서·Apple 자격증명은 저장소에 넣지 않는다.

## 현재 가능한 것

```sh
./scripts/test.sh
./scripts/build-app.sh
plutil -lint dist/LightSnap.app/Contents/Info.plist
codesign --verify --strict --verbose dist/LightSnap.app
```

기본은 ad-hoc 서명, 빌드한 Mac의 아키텍처용 앱이다. 환경변수 `LIGHTSNAP_SIGN_IDENTITY`에 설치된 인증서를 지정하면 hardened runtime·timestamp 옵션으로 서명한다. 이 옵션만으로 공증이나 Gatekeeper 검증까지 완료되지는 않는다.

macOS CI job은 소스 checkout → 도구 버전 → 회귀 검사 → 로컬 앱 빌드 → plist/서명 검증을 수행한다. Windows job은 MSVC x64 빌드·CTest 후 서명되지 않은 테스트 ZIP과 체크섬을 14일 아티팩트로 저장한다. CI가 GitHub Release를 자동 공개하지는 않는다. Windows 첫 버전은 사용자 요청에 따라 수동 Release로 제공한다. 인증서·공증·Release 업로드·태그 빌드·비밀정보 전용 스캔은 없다. 한 번의 macos-latest 빌드는 두 아키텍처 검증이 아니다.

## R01 — 버전 원본과 릴리스 메타데이터 (우선)

현재 버전은 빌드 plist와 UI 제목 등에 중복된다. 단일 VERSION 원본에서 표시 버전과 빌드 번호를 주입하고, 앱·ZIP·태그·CHANGELOG 일치 검사를 추가한다. 버전 변경만으로 앱 ID `dev.lightsnap.mac`을 바꾸지 않는다.

## R02 — 아키텍처별 CI (우선)

Intel/Apple Silicon 각각의 실행 가능한 runner와 도구 체인을 확인해 matrix를 구성한다. 사용 가능한 label·과금·Swift 지원을 확인하고 기계 종류를 가정하지 않는다. 크로스 컴파일과 해당 기계에서 실제 실행하는 검사를 구분한다. universal 앱을 제공하려면 양쪽 바이너리 결합과 최종 서명·실행 검증도 필요하다.

## R03 — 정식 서명·공증 (배포 전 우선)

필요 조건: 관리자가 준비한 적절한 Developer ID 인증서와 개인키, Apple 공증 인증 설정, Xcode의 notarytool/stapler. API 키·앱 전용 암호·인증서 파일을 채팅·README·CI 로그에 기록하지 않는다. 공증 프로필은 Keychain 또는 보호된 CI 환경에서 구성한다.

예시 흐름(프로필과 인증서가 이미 준비된 환경):

```sh
# YOUR_SIGNING_IDENTITY는 실제 설치된 인증서 식별값으로 설정한다.
LIGHTSNAP_SIGN_IDENTITY="$YOUR_SIGNING_IDENTITY" ./scripts/build-app.sh
codesign --verify --strict --verbose dist/LightSnap.app

ditto -c -k --keepParent dist/LightSnap.app dist/LightSnap-notary.zip
xcrun notarytool submit dist/LightSnap-notary.zip --keychain-profile lightsnap-notary --wait
# 결과 status=Accepted를 확인한다. 거절/실패 시 배포하지 않고 원인을 분석한다.
xcrun stapler staple dist/LightSnap.app
xcrun stapler validate dist/LightSnap.app
spctl --assess --type execute --verbose=2 dist/LightSnap.app

# staple 이후 앱으로 최종 ZIP을 다시 만든다.
ditto -c -k --keepParent dist/LightSnap.app dist/LightSnap-final.zip
shasum -a 256 dist/LightSnap-final.zip > dist/LightSnap-final.zip.sha256
```

실제 배포 파일명에는 버전과 아키텍처를 넣는다. 최종 ZIP을 새 위치에 풀어 서명·staple·버전·아키텍처·실행을 다시 확인한다. 이전 버전 위 교체, 기존 단축키 보존, 접근성 권한·로그인 항목의 업데이트 동작도 확인한다. 정식 서명은 안정적인 코드 식별에 도움이 되지만 모든 권한 유지와 OS 동작을 보장하지 않는다.

근거: [Apple 공증 절차](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [코드 서명 요구사항](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

## R04 — 태그 기반 배포 자동화

제안: 버전 일치·검사 성공 → 보호된 릴리스 환경 → 서명 → 공증 Accepted → staple → 최종 ZIP 재생성 → 체크섬 → GitHub 초안 Release → 검토 후 공개.

- 일반 PR 검사에는 저장소 contents:read만 사용한다. 쓰기 권한·서명·공증 자격증명은 릴리스 job에만 부여한다.
- 외부 PR 코드를 secrets가 있는 workflow_run/pull_request_target에서 실행하지 않는다.
- 인증서는 임시 Keychain에 가져오고 실행 종료 시 정리한다. base64는 암호화가 아니다.
- 서명된 산출물이 인증서·키·진단 로그를 포함하지 않는지 검사한다.
- Action은 검토한 전체 commit SHA로 고정하고 업데이트 도구를 통해 변경을 검토한다.
- 로그에는 원본 인증 응답·패스워드·키를 출력하지 않는다. 비밀정보 마스킹에만 의존하지 않는다.
- 라이선스가 아직 미지정이므로 공개 배포 전에 관리자가 결정한다. 저장소 공개 전환도 별도 제품 결정이다.

## R05 — 무결성과 업데이트

체크섬은 전송·파일 비교에 유용하지만 같은 배포 계정이 침해되면 파일과 체크섬을 함께 바꿀 수 있다. 코드 서명·공증과 결합한다. 자동 업데이트는 후속 제안이며 HTTPS, 업데이트 서명 검증, 다운로드 실패·권한 필요 시 복구, 다운그레이드와 설정 호환 정책을 먼저 설계한다.

## 수동 릴리스 확인표

- [ ] 버전/빌드/CHANGELOG/태그 일치
- [ ] 관련 자동 검사와 아키텍처별 실행 확인
- [ ] 신규 설치 및 이전 버전 교체 확인
- [ ] 접근성 미허용·재허용·업데이트 후 연결 확인
- [ ] 로그인 항목 켜기·끄기·승인·다음 로그인 확인
- [ ] 실제 다중 모니터·고정 크기·전체 화면·복원 확인
- [ ] 개인정보·비밀정보·아카이브 메타데이터 검사
- [ ] 정식 배포라면 서명·공증·staple·Gatekeeper 확인
- [ ] 최종 압축 파일에서 재검사, 체크섬 기록
- [ ] 성능 주장은 측정 조건과 표본을 포함해 기록

## Windows 테스트 배포

`windows/README.md`의 CMake Release와 CTest를 먼저 통과시킨다. CI 아티팩트의 ZIP은 EXE와 Windows README만 포함하며 SHA256.txt를 함께 제공한다. MSVC 런타임은 정적 링크한다. 소스 ZIP에 빌드 폴더·PDB·개인 설정을 포함하지 않는다. 정식 Authenticode 인증서 서명과 설치 프로그램·자동 업데이트는 후속 작업이다. 키나 인증서를 저장소에 넣지 않는다. 서명되지 않은 테스트 빌드를 SmartScreen 검증 완료로 안내하지 않는다.

## Windows 0.1.0 수동 Release

`windows-v0.1.0`은 첫 테스트 버전으로 prerelease 표시한다. 검증된 8dd9013 MSVC 실행 파일은 그대로 유지하고 설치 README만 갱신하여 ZIP과 SHA-256을 제공한다. 정식 코드 서명과 실제 데스크톱 수동 검증은 별도다.
