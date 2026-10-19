# LightSnap browser playground

**기본 실행 파일: `standalone.html`**

다운로드한 HTML 파일을 더블클릭하거나 일반 브라우저에서 열면 바로 체험할 수 있습니다. ChatGPT 연결·로그인·앱 설치·로컬 서버가 필요 없습니다. 스타일·스크립트·이미지가 모두 포함되어 파일 하나만 다른 사람에게 전달하면 됩니다.

GitHub의 파일 화면은 HTML 코드를 보여주므로 Raw 다운로드 버튼으로 저장해 주세요. 저장소가 비공개인 동안 GitHub 다운로드에는 접근 권한이 필요하지만, 받은 HTML 파일을 실행하는 데에는 계정이 필요 없습니다.

## 개발

유지관리하는 원본은 `index.html`, `style.css`, `model.mjs`, `app.mjs`, `assets/`입니다. 원본을 수정한 뒤 단일 HTML을 다시 생성합니다.

```sh
node scripts/build-preview.mjs
node scripts/build-preview.mjs --check
node --test preview/model.test.mjs
node --check preview/app.mjs
```

생성기는 외부 패키지 없이 Node.js 표준 라이브러리만 사용합니다. 이미지와 스타일을 포함하고 JavaScript를 합치며, 인라인 코드의 SHA-256을 CSP에 기록합니다. 일반 사용자는 Node.js 없이 완성된 파일만 열면 됩니다. 생성물을 직접 편집하기보다는 원본을 수정한 뒤 다시 생성해 주세요.

원본 모듈 버전을 개발 서버로 보려면 선택적으로 실행할 수 있습니다.

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory preview
```

## 동작과 범위

- 모의 창 선택, 절반·4분할·6분할·⅓·⅔ 배치
- 좌우 반복 크기 순환, 모니터 2개 시뮬레이션, 최초 배치 복원
- 모의 화면에 포커스가 있을 때 화살표·1–6·Enter·Backspace 조작
- 브라우저 메모리에만 상태 보관, 외부 API·분석 SDK·원격 폰트·쿠키·스토리지 미사용
- GitHub 링크는 직접 클릭할 때만 이동

실제 macOS 창 제어·전역 단축키·접근성 검사·로그인 실행·네이티브 성능 측정은 하지 않습니다. Swift 동작을 수동 재현한 별도 모델이므로 네이티브 변경 시 함께 검토합니다. 드래그 스냅·커스텀 그리드는 미구현입니다.

## 웹 주소로 제공하고 싶다면

같은 단일 HTML을 `index.html`로 이름 붙여 일반 정적 웹 호스팅에 올릴 수 있습니다. ChatGPT 인증은 필요 없습니다. 현재 작업에서는 외부 호스팅·인증을 연결하지 않으며 저장소는 비공개로 유지합니다. GitHub Pages를 사용할 경우 계정 플랜·비공개 저장소 지원과 실제 페이지 공개 범위를 먼저 확인해야 합니다. 저장소 공개나 Pages 활성화는 사용자가 결정합니다.

기존 Sites URL과 호스팅 식별 파일은 README/현재 코드의 기본 흐름에서 제거했습니다. 예전 비공개 사이트 자체를 삭제하거나 공개 설정을 바꾸지는 않았습니다.
