# Windows 보안 보강과 V3 실행 알림

## 사용자가 보고한 현상

Windows 0.1.0 EXE 실행 시 V3에 ‘한 번만 실행’ 선택지가 나타났다고 보고했습니다. 경고 전문·악성코드 진단명·V3 제품/엔진 버전은 아직 확인되지 않았습니다. **평판 기반 프로그램 실행 확인일 가능성이 있으며, 악성코드 검출이나 오탐 확정으로 단정하지 않습니다.**

안랩은 [반복되는 프로그램 실행 알림](https://ask.ahnlab.com/hc/ko/articles/900003775666)을 파일 생성 날짜·사용자 수·의심 행위 등 신뢰 정보가 부족한 파일에 대한 클라우드 평판 확인으로 설명합니다. 코드 수정만으로 이 서비스의 판정을 변경할 수 없습니다. 최종 판정은 안랩과 해당 PC의 보안 정책에 달려 있습니다. 이 문서는 알림 해제나 백신 예외 등록을 안내하지 않습니다.

## 0.1.1에서 변경한 것

| 변경 | 목적 / 증거 | 보장하지 않는 것 |
| --- | --- | --- |
| `/guard:cf` 컴파일·링크 | 간접 호출 대상 검사, 실제 CFG 플래그와 함수 테이블까지 CI 확인 | V3 경고 제거 |
| `/GS /sdl` | 스택 보호·추가 개발 단계 보안 검사, EXE의 보안 쿠키 확인 | 모든 메모리 취약점 제거 |
| ASLR/HIGHENTROPYVA/DEP 명시 | 로드 주소 무작위화·비실행 데이터 보호, 실제 PE 확인 | 악성코드 검사 대체 |
| CETCOMPAT 표시 | 지원되는 환경의 하드웨어 스택 보호 호환 표시 | 모든 Windows에서 CET 활성화 |
| 읽기/쓰기+실행 섹션 검사 | 쓰기 가능하면서 실행 가능한 섹션을 배포 게이트에서 거부 | 전체 바이너리 감사 |
| SHA-256·검사 JSON | 사용자가 실행 전 파일 동일성과 검사 범위를 확인 | 배포자 서명·독립된 신뢰 보증 |
| 서명 상태·Defender 보고 | 검사 불가를 통과로 표시하지 않고 V3 미검증을 명시 | 모든 백신 무탐지 |

기존 창 제어는 Windows API로 그대로 수행합니다. 관리자 권한·키보드 전체 수집·네트워크·자동 실행 기본 켜기를 추가하지 않습니다. V3를 끄거나 예외를 추가하지 않으며 실행 파일 포장·난독화·탐지 패턴 회피를 하지 않습니다.

## ZIP의 증거 파일 읽기

- `security-report.json`: **동봉 EXE의 SHA-256**, x64 및 필수 PE 보호 확인 결과. 모든 check가 true인지 확인합니다.
- `antivirus-report.json`: Authenticode 상태와 CI 호스트 Defender 엔진/정의 버전·검사 결과. `not_run`, `service_unavailable` 등은 검사를 하지 못한 상태이며 안전 판정이 아닙니다. V3는 `not_tested`입니다. Defender가 위협/검사 오류를 보고하면 패키지 생성을 중단합니다.
- `LightSnap.exe.sha256`: 실행 파일의 SHA-256. Release에는 ZIP 자체의 SHA-256도 제공합니다. 보고서는 해당 CI 시점의 결과이며 서명이나 외부 기관의 인증서가 아닙니다.

Windows PowerShell에서 **실행 없이** 확인할 수 있습니다.

```powershell
Get-FileHash .\LightSnap.exe -Algorithm SHA256
Get-AuthenticodeSignature .\LightSnap.exe | Select-Object Status, StatusMessage
```

체크섬이 배포값과 다르면 실행하지 말고 파일 출처를 먼저 확인합니다. 서명은 현재 `NotSigned`가 예상되며, 신뢰 인증서로 서명한 릴리스를 만들기 전까지 이를 `Valid`로 설명하지 않습니다.

## 아직 필요한 배포자 코드 서명

이번 환경에는 Windows 배포자용 신뢰 인증서가 제공되지 않았습니다. 사용자/사업자 신원 확인이 필요한 Authenticode 인증서 또는 신뢰할 수 있는 관리형 서명 서비스를 관리자가 준비해야 합니다. 자체 서명 인증서를 만들어 사용자 PC에 루트 인증서를 설치하도록 요구하지 않습니다. 인증서·개인키·비밀번호를 채팅이나 Git에 넣지 않습니다.

정식 서명은 Windows SDK의 SignTool 또는 인증기관의 관리형 도구로 **최종 EXE에 SHA-256 서명 및 신뢰 타임스탬프 → 검증 → 최종 EXE 보안 검사/백신 검사 → ZIP → 체크섬 재생성** 순서로 수행합니다. 코드 서명은 배포자 식별·변조 검증에 도움이 되지만 SmartScreen·V3 등 평판 또는 보안 정책 경고 제거를 보장하지 않습니다. 서명 전후 파일 해시는 달라지므로 분석 기관에는 실제 사용자 배포 파일을 제출해야 합니다.

근거: [Microsoft CFG](https://learn.microsoft.com/en-us/cpp/build/reference/guard-enable-control-flow-guard), [SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool), [SmartScreen 배포자 평판](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation).

## 안랩 분석 요청에 필요한 내용

[안랩 공식 고객지원](https://ask.ahnlab.com/hc/ko/)의 악성코드 신고 또는 제품 문의에서 실행 알림/평판 확인을 요청할 수 있습니다. 실제 진단명 없이 오진이라고 단정하여 신고하지 않습니다. 다음 정보와 해당 배포 EXE를 준비합니다.

- V3 제품 이름·버전·엔진 날짜, Windows 버전
- 경고 제목·전체 문구·진단명(있는 경우), 발생 단계(EXE 실행)
- Release URL, EXE·ZIP의 SHA-256과 검사 보고서
- 제품 용도: 사용자 단축키에 따라 현재 창 위치/크기를 변경하는 네이티브 유틸리티
- 주요 API: RegisterHotKey, SetWinEventHook(창 전환/파괴 이벤트, OUTOFCONTEXT), SetWindowPos, 사용자 선택 HKCU Run 등록
- 관리자 자동 상승·프로세스 주입·키보드 전체 수집·네트워크 통신 없음

외부 전송/분석 요청은 이번 자동 빌드에서 수행하지 않습니다. 접수 번호·안랩 답변과 같은 증거를 받은 뒤 결과를 기록합니다. CI의 Defender 결과나 코드 변경만으로 ‘안랩 인증’, ‘V3 통과’, ‘경고 해결 완료’를 표시하지 않습니다.
