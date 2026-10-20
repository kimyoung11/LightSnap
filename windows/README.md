# LightSnap Windows 0.1.1

macOS판의 배치 정책을 옮긴 **Windows 10 1607 이상 / Windows 11 x64용 첫 버전**입니다. Windows 전용 C++17/Win32 앱이며 Electron·.NET·Swift 런타임 설치가 필요 없습니다. 기존 macOS 앱은 별도로 유지합니다. Windows ARM64 네이티브 빌드는 제공하지 않습니다.

## 실행

1. **[Windows ZIP 다운로드](https://github.com/kimyoung11/LightSnap/releases/download/windows-v0.1.1/LightSnap-0.1.1-Windows-x64.zip)** 후 계속 사용할 폴더에 **모두 압축 해제**합니다.
2. `LightSnap.exe`를 실행합니다. 처음에는 설정 창이 열립니다.
3. 메모장이나 브라우저의 일반 창을 선택하고 `Ctrl+Alt+←`를 누릅니다.
4. 설정 창을 닫으면 알림 영역(트레이)에 남습니다. 숨겨진 아이콘의 LightSnap을 열어 설정·진단·종료를 사용할 수 있습니다.

접근성 권한 등록은 필요 없습니다. 관리자 권한으로 실행한 앱, 크기 조절이 불가능한 창, 게임·전체 화면·가상 데스크톱의 숨겨진 창은 제어가 제한될 수 있습니다. 자동 권한 상승은 하지 않습니다. 이 첫 배포본은 Authenticode 서명이 없는 테스트용 빌드이며 신뢰도 경고가 표시될 수 있습니다. 정식 서명이나 SmartScreen 평판을 확보한 배포본으로 설명하지 않습니다.

## V3 실행 알림과 보안 상태

‘한 번만 실행’ 등의 선택지가 있는 프로그램 실행 알림은 신뢰 정보가 부족한 파일에 대한 평판 확인일 수 있습니다. 악성코드 진단명·치료/격리 알림과 구분해야 하며, 버튼 이름만으로 오탐이나 안전을 단정할 수 없습니다. 0.1.1은 메모리 보호와 빌드 검증을 보강한 버전이며 **V3 경고 해제 또는 안랩 인증을 받은 버전이 아닙니다.**

- CFG·스택 보호·ASLR·DEP를 MSVC에 명시하고, CI가 실제 PE 보호 정보를 검사합니다.
- ZIP에는 `security-report.json`, `antivirus-report.json`, `LightSnap.exe.sha256`도 포함합니다. Defender 검사 가능 여부와 결과, 서명 상태를 기록하며 V3는 별도 미검증으로 표시합니다.
- 현재 코드 서명용 신뢰 인증서가 제공되지 않아 **미서명**입니다. 서명은 배포자 확인·변조 방지에 필요하지만 백신/평판 경고의 제거를 보장하지 않습니다.
- [보안 보강 내용과 정식 서명·안랩 문의 절차](../docs/WINDOWS_SECURITY.md)를 확인하세요. EXE를 실행하기 전에 읽을 수 있습니다. V3 설정이나 예외 목록을 앱이 변경하지 않습니다.

## 기본 단축키

모두 **Ctrl+Alt**를 포함합니다. Windows 자체 `Win+방향키`는 사용하지 않습니다.

| 동작 | 추가 키 |
| --- | --- |
| 왼쪽 / 오른쪽 절반 | ← / → |
| 위쪽 / 아래쪽 절반 | ↑ / ↓ |
| 왼쪽 위 / 오른쪽 위 | U / I |
| 왼쪽 아래 / 오른쪽 아래 | J / K |
| 첫 번째 / 가운데 / 마지막 ⅓ | D / F / G |
| 왼쪽 / 오른쪽 ⅔ | E / T |
| 6분할 위쪽 왼쪽부터 | 1 / 2 / 3 |
| 6분할 아래쪽 왼쪽부터 | 4 / 5 / 6 |
| 작업 표시줄을 제외한 최대화 | Enter |
| 이 실행 세션의 최초 배치 복원 | Backspace |
| 다음 모니터 | Shift+→ |

좌우 키를 반복하면 **½ → ⅔ → ⅓ → ½**로 순환합니다. 같은 창·방향·화면에서 마지막 배치와 실제 좌표가 일치할 때만 이어집니다. 작업 영역 최대화는 일반 창 배치이며 전체 화면 모드가 아닙니다. 다음 모니터는 작업 영역의 x, y 순으로 순환하며 상대 위치·크기를 환산합니다. 복원 이력은 최대 128개이며 앱 종료 후에는 사라집니다.

설정의 동작 목록에서 항목을 고르고 오른쪽 입력칸에 조합을 입력한 뒤 **단축키 저장**을 누릅니다. 사용자 조합에는 Ctrl이 필수이며 Alt/Shift를 더할 수 있습니다. Windows 키 조합은 현재 편집기에서 지원하지 않습니다. **이 동작 해제**는 다시 실행해도 유지됩니다. 같은 조합·다른 앱이 점유한 조합은 기존 설정을 유지하며 안내합니다. 언어에 따라 AltGr가 Ctrl+Alt로 처리될 수 있으므로 해당 키보드에서는 사용자 조합으로 변경해 주세요.

## 설정·로그인 실행·삭제

- 사용자 설정: `%LOCALAPPDATA%\LightSnap\settings.ini` (버전 1). Windows 가상 키 코드이며 macOS 설정과 공유하지 않습니다.
- 최초 실행 시 기본값을 사용하며 사용자 변경 시 저장합니다. 누락된 동작은 해제 상태입니다. 손상·미지원 버전은 원본을 덮어쓰지 않고 안내합니다. 복구하려면 앱 종료 후 파일을 별도로 백업·이름 변경하고 재실행하세요.
- 로그인 실행은 기본적으로 꺼져 있습니다. 체크하면 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`의 `LightSnap` 값에 현재 EXE 경로와 `--background`를 등록합니다. 체크 표시는 **이 경로의 등록 여부**이며 Windows 시작 앱 설정에서 별도로 차단할 수 있습니다.
- EXE를 옮기려면 자동 실행을 해제한 뒤 옮기고 다시 등록하세요. 삭제 전에도 자동 실행 해제 → 앱 종료 → EXE 삭제 순서로 진행하세요. 설정까지 지우려면 위 사용자 설정 폴더를 삭제합니다.
- 진단은 요청할 때 자기 프로세스의 메모리와 최근 성공 100회의 지연 p95를 표시합니다. 상시 샘플링·지속 로그·서버 전송·계정 연결·자동 업데이트는 없습니다. 메모리/지연 목표 달성은 아직 실측하지 않았습니다.

## Windows에서 빌드

Visual Studio 2022 이상 또는 Build Tools의 **C++ 데스크톱 개발**, Windows SDK, CMake 3.20 이상이 필요합니다. 저장소 루트에서:

```powershell
cmake -S windows -B windows/build -A x64
cmake --build windows/build --config Release --parallel
ctest --test-dir windows/build -C Release --output-on-failure
.\windows\build\Release\LightSnap.exe
```

Release는 MSVC 런타임을 정적으로 링크합니다. 사용자 배포본은 **[GitHub Releases](https://github.com/kimyoung11/LightSnap/releases/tag/windows-v0.1.1)**에서 ZIP과 SHA-256으로 제공합니다. Release 첨부 파일에는 Actions 아티팩트의 14일 보관 기간이 적용되지 않습니다. EXE 실행에는 로그인이 필요 없습니다. CI 빌드도 Actions에서 별도로 확인할 수 있습니다.

Mac/Linux에서는 별도 설치한 [Zig](https://ziglang.org/download/) 0.17.0으로 `ZIG=/absolute/path/to/zig ./scripts/build-windows.sh` 크로스 컴파일도 가능합니다. 스크립트가 도구를 자동 다운로드하지 않으며 Windows 실행 검증을 대신하지 않습니다.

## 구조와 검증 범위

- `core.hpp`: 22개 액션 ID, 정수 경계 분할, 비례 이동, 크기 순환, 설정 검증·직렬화. `tests.cpp`는 홀수 크기/음수 원점/해제 보존/깨진 설정/중복/수동 이동 후 순환 초기화 등을 검사합니다.
- `main.cpp`: 트레이와 설정, RegisterHotKey, 단일 인스턴스, 직렬 작업자, DWM/Win32 창 배치와 읽기 검증, 복원 이력, HKCU 자동 실행, 요청 시 진단.
- `app.rc` / `app.manifest`: 아이콘·버전·asInvoker·PerMonitorV2 DPI. UI는 Windows 기본 컨트롤입니다.
- `--self-test`: 숨겨진 자기 창의 Win32 배치/읽기, 임시 파일에 설정 교체·재읽기를 검사합니다. 사용자 창·설정·레지스트리·전역 단축키는 변경하지 않습니다.

실제 다른 앱의 전역 키 전달·다중 모니터 DPI 변화·UI 배치·시작 앱 차단·재로그인은 별도 수동 검증이 필요합니다. Windows 실행 검증과 Mac에서의 크로스 컴파일 결과는 루트 `VALIDATION.md`에 구분해 기록합니다.

API 근거: [RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey), [DWM과 GetWindowRect의 프레임 차이](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect), [WINDOWPLACEMENT 좌표와 복원](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-windowplacement), [Run 레지스트리 키](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).
