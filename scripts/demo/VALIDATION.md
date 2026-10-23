# A 영상 관찰 확정 및 후보 기록

부모의 실제 영상 검토를 전달받아 [A-OBSERVATIONS.md](A-OBSERVATIONS.md), README와 기본 시나리오·편집 계획을 정정했습니다.
A는 권한 부족→허용 영상이 아니며 음성 녹음·알람·기상 확인·재알람 자료입니다.
후보 원본 구간은 00:34~00:47, 01:43~01:51, 03:14~03:23, 04:10~04:18(±1초)입니다.
배경 미리보기(01:06~01:12)를 실제 알람으로 설명하지 않으며, 개인 알림(02:16 전후)은 공개 제외 권고로 기록했습니다.
대기 생략 표시와 알림 문구 확대 권고, 청취 미검증도 명시했습니다.
실제 사용 흐름으로의 구성 변경과 편집은 사용자 승인 대기입니다. 영상에 대한 수정·녹화·후처리는 실행하지 않았습니다.
관찰 반영 후 기본 dry run, 4개 테스트, 후보 구간 경계·미승인 상태·렌더링 거부 검사, `git diff --check`가 통과했습니다. 이번 변경에서는 영상 편집 검증을 재실행하지 않았습니다.
아래의 권한 시나리오 및 내용 검토 대기 기록은 이전 상태이며, 최신 관찰과 구분해야 합니다.

---

# A 영상 제공 상태 반영

부모 작업에서 사용자 제공 `warmwake-demo-720p.mp4`(Library ID `libfile_1e0c350b93dc8191a46d45e2d8934d7a`)의 수신을 전달했습니다.
A는 원본 없음 상태가 아니라 **수신 완료·부모 내용/타임코드 검토 대기** 상태입니다.
영상은 내려받거나 수정하거나 다시 녹화하지 않았으며, 영상 내용의 성공·실패 여부도 이 작업에서 주장하지 않습니다.
`scenario.json`과 `timeline.json`에 출처를 등록했습니다. A 편집 후보의 원본 구간과 초점은 미확정입니다.
본편 타임라인은 `needs_review_inputs`로 표시하고 렌더링 거부를 유지합니다. B 원본 경로·구간은 여전히 필요합니다.
A 출처 반영 후 기본 dry run, 4개 테스트, 편집 거부 검사와 전체 `verify.py`를 다시 실행해 통과했습니다.
최신 합성 검증 경로는 `/var/folders/rb/n38l4h_x6_927hsc8bmyl2980000gn/T/warm-alarm-demo-validation-pbb01fko/`입니다.
아래의 A 촬영본 필요 기록은 수신 전 상태입니다.

---

# A/B 본편 재구성 검증

기존 사용자 수정 상태를 확인하고 `chore/macos-presentation-demo` worktree를 재사용했습니다.
수정 전 `scripts/demo/` 전체는 `/var/folders/rb/n38l4h_x6_927hsc8bmyl2980000gn/T/warm-demo-before-reframe-injr2ywn/demo`에도 보존했습니다.
기존 86초 설정은 `scenario-example-qa.json`, `timeline-example-qa.json`, 기존 README 본문은 `README-example-qa.md`로 보존했습니다.
기존 30초 macOS 설정에는 Q&A 용도 표지만 추가했습니다. 사용자 inspection 오류 처리와 기존 검사 기록은 유지했습니다.

## 코드 근거와 실행 범위

- WarmWake 저장소 `/Users/dongminyu/Development/01_personal/mirae`, 커밋 `cf11e8f1`을 읽었습니다. 파일은 변경하지 않았습니다.
- 한국어 제목 `온:음`, 저장 경고 “알람을 저장하려면 알림 권한이 필요해요”, `설정`/`저장` 동작을 소스에서 확인했습니다.
- `coreGranted`는 알림과 정확한 알람 권한의 AND입니다. 허용 후 자동 변화 대신 저장 재시도 시 재검사와 성공 처리 경로가 존재함을 확인했습니다. 실제 기기의 성공 여부는 검증하지 않았습니다.
- 기존 example README는 B의 두 값을 설명하지만 원본 비교 영상의 경로·실제 표시 구간은 특정하지 못했습니다. 앱/플러그인/현재 작업 폴더와 접근 가능한 Desktop/Downloads/Movies의 영상 파일 목록을 확인한 범위입니다.
- 본편 `scenario.json`은 수동 촬영용 큐만 포함합니다. `timeline.json`은 source/timecode/focus가 미정인 편집 계획이며 렌더링을 거부합니다.
- OS 권한 변경, UI 검사·클릭, 녹화, 앱 재실행·빌드, 슬라이드 변경, 설치·커밋·push·PR은 수행하지 않았습니다. 과거 접근성 거부 작업도 재시도하지 않았습니다.

## 이번 검증

다음 명령이 종료 코드 0으로 완료되었습니다.

```bash
python3 scripts/demo/demo.py
python3 scripts/demo/test_demo.py
python3 scripts/demo/verify.py
shellcheck scripts/demo/doctor.sh
git diff --check
```

- 4개 테스트가 통과했습니다. 기본 A/B 큐가 외부 명령을 호출하지 않으며 `--confirmed-target`을 붙여도 본편의 `--run`/`--inspect`는 거부합니다.
- 기존 빈 inspection 거부와 레이블 출력 검증을 유지했습니다. Apple Events 경계는 mock이며 실제 UI 결과를 추가로 주장하지 않습니다.
- 원본 미지정 본편 타임라인의 편집 거부를 확인했습니다.
- 9초 합성 영상 편집과 기존 86초·30초 **Q&A용 설정**의 합성 편집 검증이 통과했습니다. 합성 파일은 검증용이며 B 원본의 대체물이 아닙니다.
- 본편 A 권한 전후 화면, B 실제 영상의 값, 구도·타임코드는 미검증입니다.
- 이번 합성 검증 증거: `/var/folders/rb/n38l4h_x6_927hsc8bmyl2980000gn/T/warm-alarm-demo-validation-5_x7z13t/`.

아래는 보존한 이전 검증 기록입니다. 본편 A/B의 완료 증거로 해석하지 마세요.

---

# 검증 기록

## 사용자 Terminal에서 실제 버튼 검사 통과

사용자가 제공한 요소 진단 결과에는 `AXCloseButton`, `AXFullScreenButton`, `AXMinimizeButton`만 있었으며 Flutter 본문 그룹의 자식 수는 `0`이었습니다.
VoiceOver 활성화를 안내한 뒤 사용자가 다시 실행한 `--inspect`는 다음 레이블을 반환했습니다.

```plaintext
Inspect Alarm API, Inspect Alarm API, Request notification permission, Request notification permission, Open readiness settings, Open readiness settings, Schedule 1 minute alarm, Schedule 1 minute alarm
```

이 결과는 사용자 Terminal에서 대상 앱의 Flutter 버튼 레이블을 읽었다는 실제 실행 증거입니다.
검사 코드는 같은 버튼의 여러 속성에서 동일 레이블을 출력할 수 있으며 클릭 대상은 노드별로 한 번만 수집합니다.
현재 출력만으로 동일 레이블을 가진 노드의 수까지 확정하지는 않습니다.
실제 조작은 일치 노드가 하나가 아니면 중단됩니다.
README에 VoiceOver 활성화 상태에서 검사·사용자 실행·수동 녹화 종료 후 원상 복구하는 순서를 반영했습니다.
VoiceOver를 끈 뒤의 트리 유지, 실제 AXPress, 예약 결과, 알람 발화, 화면 기록은 아직 검증하지 못했습니다.
에이전트의 접근성 거부 상태를 재확인하거나 실제 UI 조작을 재시도하지 않았습니다.
이번 변경은 문서에 검증 상태를 반영하는 작업이며, 실행 코드는 변경하지 않았습니다.

## 사용자 실행 로그의 빈 inspection 보완

사용자 Terminal 로그에서는 접근성이 허용됐고 화면 기록은 미허용, 자동화 무팝업 조회는 `-600`이었습니다.
이 값은 이전 에이전트 조회 결과와 실행 주체가 다릅니다.
사용자가 실행한 Flutter 로그는 빌드 성공, 전면 표시 실패, Dart VM Service 시작을 보여줍니다.
이후 `--inspect`는 출력 없이 정상 종료했습니다.
코드를 확인한 결과, 빈 레이블 목록을 그대로 출력하고 성공 처리하는 경로가 있었습니다.
레이블 수집 중 속성 오류를 무시하는 AppleScript 때문에 빈 목록의 원인까지 확정할 수는 없습니다.

에이전트의 읽기 전용 프로세스 조회에서는 현재 worktree의 `example.app/Contents/MacOS/example` 실행을 확인했습니다.
System Events로 해당 앱의 창을 조회하는 작업은 `osascript is not allowed assistive access. (-25211)`로 거부됐습니다.
거부된 UI 조회는 재시도하거나 다른 도구로 대체하지 않았습니다.
사용자 Terminal에서 수행할 읽기 전용 요소 조회 명령을 README에 추가했으나 그 명령의 실제 앱 결과는 아직 확인하지 못했습니다.
클릭·예약·녹화·설정 변경·앱 재실행은 수행하지 않았습니다.

회귀 검증에는 test-driven-development와 verify-fix 스킬을 적용했습니다.

```plaintext
Fix: demo.py:main — empty inspection raises an error instead of reporting success.
Mutation proof: python3 scripts/demo/test_demo.py failed before the fix at "RuntimeError not raised"; a temporary copy with only the fix removed failed at the same assertion.
Blast radius: main --inspect consumes invoke output; main --run also uses invoke but is unchanged. python3 scripts/demo/test_demo.py → 2 tests passed. Apple Events boundary is mocked; actual UI interaction remains untested.
Invariant: empty inspection must not be success. Inspection handling exists only in demo.py:main within scripts/demo/demo.py; AppleScript still returns the raw label list, which this consumer validates.
Suite: python3 scripts/demo/verify.py → PASS, including the inspection tests, 30s Demo B and existing 9s/86s synthetic video checks.
```

이번 검증 증거는 다음 경로에 있습니다.

```plaintext
/var/folders/rb/n38l4h_x6_927hsc8bmyl2980000gn/T/warm-alarm-demo-validation-rydr7z_r/
```

## 발표 자료 반영 후 검증

사용자가 제공한 [준비 문서](https://docs.google.com/document/d/14WTwk-MIU3c3sPAjYzJAPoAIIDZPgxtyuQR828fOOHk)와 [슬라이드](https://docs.google.com/presentation/d/1mdHUMZahScIcwoOXhjIS17JCz946oJLNbpGKP3OslVQ)를 Andrew Chrome 프로필의 기존 탭에서 읽었습니다.
원본 문서와 슬라이드, 공유 설정은 수정하지 않았습니다.
문서는 A를 Android 권한 변경 40초, B를 Android/iOS 비교 30초로 설명합니다.
슬라이드 10과 13은 각각 A와 B이며, 13은 비교 대상으로 iOS/macOS를 표시합니다.
이 차이를 README에 명시하고 macOS 쪽만 준비하는 `scenario-b-macos.json`, `timeline-b-macos.json`을 추가했습니다.
기존 86초 설정은 유지했습니다.

`python3 scripts/demo/verify.py`는 종료 코드 0으로 완료되었습니다.
새 설정의 dry run은 두 번의 버튼 조작과 30초 종료 시각을 검사합니다.
ffmpeg 합성 영상 편집 결과는 ffprobe로 30초 길이를 확인했고, 15초 프레임을 원본과 비교하여 확대 구간의 픽셀이 달라지는 것을 확인했습니다.
기존 9초·86초 검증과 `shellcheck scripts/demo/doctor.sh`도 통과했습니다.
현재 증거 경로는 다음과 같습니다.

```plaintext
/var/folders/rb/n38l4h_x6_927hsc8bmyl2980000gn/T/warm-alarm-demo-validation-t462kcw7/
  demo-b-source.mp4
  demo-b-edited.mp4
  result.txt
```

실제 UI·예약·녹화는 실행하지 않았으며, 아래 권한 조회 이후 권한 상태를 다시 확인하지 않았습니다.
macOS에서 `unsupportedWakeCheck`가 실제 표시되는지는 아직 확인하지 못했습니다.
30초 시나리오는 8초에 1분 알람을 예약하므로 촬영이 끝난 뒤에도 약 T+68초에 울릴 수 있습니다.
실행자는 기존 복구 절차에 따라 남은 예약을 처리해야 합니다.
Android 데모 A와 B의 Android/iOS 쪽은 검증 범위 밖입니다.
마지막 상태 확인에서 플랫폼 Pigeon 생성 파일 변경도 관찰했으나, 이번 작업에서는 해당 파일을 읽어 수정하거나 재생성하지 않았습니다.

## 2026-10-23 재검증

현재 할당된 저장소 `/Volumes/dongminyu/Development/Codex/2026-10-22/task-4/warm_alarm`에서 검증했습니다.
브랜치는 `chore/macos-presentation-demo`, HEAD는 `fa3d11c`이며 원격은 개인 계정의 `AndrewDongminYoo/warm_alarm`입니다.
기존 worktree와 추적되지 않은 `scripts/demo/`를 재사용했습니다.
기존 플랫폼 manifest 3개의 Pigeon 버전 수정은 보존했으며 앱 코드, 의존성, Git 브랜치 상태를 변경하지 않았습니다.
이번 보완 범위는 `verify.py`, `README.md`, 이 검증 기록입니다.

`warm_alarm/example/README.md`에는 Android/iOS 발표 데모가 있습니다.
해당 문서와 `lib/main.dart`, macOS `AppInfo.xcconfig`를 읽어 현재 시나리오가 macOS 단독 리허설임을 문서에 명시했습니다.
실제 앱의 이름과 접근성 버튼 구조는 확인하지 못했습니다.

`python3 scripts/demo/verify.py`가 종료 코드 0으로 완료되었습니다.
이 검증은 구문과 입력 거부를 검사하며, 합성 영상의 프레임 픽셀과 ffprobe 메타데이터로 편집 결과를 읽습니다.
입력 거부 시 예상 오류 메시지를 확인하도록 보강했고, 줌 판정에 확대하지 않은 프레임 차이를 넣으면 `zoom phase must differ from overview frames`로 실패하는 것을 먼저 확인했습니다.
9초 영상은 640×360, 30fps이며 오디오가 유지되었습니다.
전체 화면·확대·전체 화면의 평균 픽셀 차이는 각각 1.2137, 112.0538, 1.4204였습니다.
기본 86초 타임라인, 무음 영상, 0.4초 선행 구간 제거, 편집 dry run의 출력 미생성, 원본 보존, 기존 출력 덮어쓰기 거부도 통과했습니다.
ShellCheck는 `shellcheck scripts/demo/doctor.sh`에서 종료 코드 0을 반환했습니다.
ffmpeg 9.0.2와 libx264, ffprobe, Python 3, osascript, clang을 확인했습니다.

합성 결과와 프레임 이미지의 경로는 다음과 같습니다.
임시 폴더가 정리되면 검증 명령으로 다시 생성할 수 있습니다.

```plaintext
/var/folders/rb/n38l4h_x6_927hsc8bmyl2980000gn/T/warm-alarm-demo-validation-1e44wb2o/
```

`./scripts/demo/doctor.sh`는 권한 요청 없이 다음 결과를 반환했습니다.

| 대상                 | 현재 결과 및 남은 작업                                                                                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 접근성               | `not granted`입니다. 실제 UI 조작은 차단된 상태이며 실행하지 않았습니다. 리허설 실행 호스트의 허용 여부를 사용자가 확인해야 합니다. |
| 화면 기록            | 현재 호출자는 `granted`입니다. 실제 녹화 앱의 권한과 촬영 영역은 별도 확인이 필요합니다. 녹화는 시작하지 않았습니다.                |
| System Events 자동화 | 무팝업 조회 코드 `0`입니다. 리허설 Terminal의 osascript 권한까지 보증하지 않습니다.                                                 |
| macOS example        | 소스 번들 ID로 실행 중인 앱이 발견되지 않았습니다. 버튼 검사·클릭·알람 예약은 실행하지 않았습니다.                                  |
| 기기·시뮬레이터      | 이번 대상은 macOS 네이티브 앱이므로 필요하지 않습니다. 모바일 기기 상태는 이번에 조회하지 않았습니다.                               |

설치, 영구 설정 변경, 실녹화, 앱 빌드, 원격 push, PR, merge, 게시는 수행하지 않았습니다.
Oracle에서 조회한 `wiki/concepts/exact-trigger-verification.md`의 선례는 실제 호출 경로와 유사 검증을 구분하라고 권고합니다.
이에 따라 합성 영상과 구문 검사 결과를 실제 Terminal의 접근성 조작 성공으로 해석하지 않았습니다.
데모 자동화와 macOS 권한 자체의 직접 선례는 `[no precedent found]`였으며, wiki 최신 원본과의 일치 여부는 확인되지 않았습니다.
아래 기록은 작업 시작 전에 존재하던 과거 결과이며 현재 권한 상태를 나타내지 않습니다.

## 기존 2026-10-22 기록

2026-10-22, Mac mini 실행 환경(macOS 27.0.1, arm64)에서 확인했습니다.

- 원본 저장소: `/Users/dongminyu/Development/01_personal/warm_alarm`
- 기준 커밋: `1fc3dd3`, 기존 브랜치: `feat/scheduling-warnings-facade`
- 작업 브랜치: `chore/macos-presentation-demo`
- 변경 범위: `scripts/demo/`만 추가했습니다. 앱 코드와 원본 브랜치의 작업 파일은 수정하지 않았습니다.
- 앱 UI 및 번들 ID의 출처: `warm_alarm/example/lib/main.dart`, `warm_alarm/example/macos/Runner/Configs/AppInfo.xcconfig`
- 저장소의 `docs/`와 README에서 별도 발표·리허설 시나리오 문서는 발견하지 못했습니다.

### 통과한 검증

`python3 scripts/demo/verify.py`가 종료 코드 0으로 완료되었습니다.

- Python 구문 검사, `bash -n`, `osacompile`이 통과했습니다.
- 기본 dry run과 확인 플래그 없는 실제 실행·검사 요청의 거부를 확인했습니다.
- 순서가 잘못된 시나리오와 유효 범위를 벗어난 줌 설정을 거부했습니다.
- 9초 합성 영상을 편집한 결과는 640×360, 30fps이며 오디오 트랙이 존재했습니다.
- 전체 화면 → 줌·팬 → 전체 화면 구간의 원본 대비 평균 픽셀 차이는 약 1.21 → 112.05 → 1.42였습니다.
- 기본 `timeline.json` 전체를 사용한 86초 무음 합성 영상 편집과 오디오 없는 입력 처리를 확인했습니다.
- 선행 0.4초를 제거했을 때 출력 길이가 약 8.6초인 것도 확인했습니다.
- 원본 보존, 기존 결과 덮어쓰기 거부, 원본 경로를 출력으로 지정했을 때의 거부, 짧은 영상 거부를 확인했습니다.
- 합성 결과의 0초·4초·8초 이미지도 직접 확인했습니다. 실제 앱 구도의 미리보기는 아닙니다.
- 설치된 ShellCheck로 `doctor.sh`를 검사했고 종료 코드 0이었습니다.
- 후처리에 사용한 ffmpeg 버전은 9.0.2이며 libx264를 포함합니다.

최종 검증의 임시 증거 경로는 다음과 같습니다. 임시 폴더 정리 후에는 `verify.py`로 재생성할 수 있습니다.

```text
/var/folders/rb/n38l4h_x6_927hsc8bmyl2980000gn/T/warm-alarm-demo-validation-3wp97d7x/
  synthetic.mp4
  edited.mp4
  timeline.json
  full-timeline-source.mp4
  full-timeline-edited.mp4
  trimmed.mp4
  result.txt
/tmp/warm-alarm-zoom-preview.png
```

### 완료하지 못한 현장 검증

| 대상                      | 관찰 결과와 상태                                                                                                                             |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| 접근성 권한               | `AXIsProcessTrusted()`가 false를 반환했습니다. 현재 실행 주체에서 미허용 상태입니다.                                                         |
| 화면 기록 권한            | `CGPreflightScreenCaptureAccess()`가 false를 반환했습니다. 현재 실행 주체에서 미허용 상태입니다.                                             |
| System Events 자동화 권한 | 동의 요청 없는 조회가 `-600`을 반환했습니다. 허용 여부를 확정할 수 없습니다.                                                                 |
| example 실행 및 버튼 검사 | 번들 ID로 실행 중인 앱이 조회되지 않았습니다. 실제 UI 조작은 실행하지 않았으며 앱 이름·레이블·구도는 현장 확인이 필요합니다.                 |
| iOS Simulator             | `xcrun simctl list devices booted`가 CoreSimulatorService 연결 실패와 로그 접근 제한으로 실패했습니다. 부팅 기기 유무는 확인하지 못했습니다. |
| Android 기기              | `adb devices`가 로컬 서버 시작을 시도했으나 리스너 생성이 `Operation not permitted`로 실패했습니다. 연결 기기 유무는 확인하지 못했습니다.    |
| Flutter 빌드              | 실행하지 않았습니다. 의존성 다운로드나 설치는 하지 않았습니다.                                                                               |
| 실제 녹화·알람            | 실행하지 않았습니다. 합성 영상 검증이 실제 알람 발화나 개인정보 노출 방지를 입증하지는 않습니다.                                             |

권한 요청, 설정 영구 변경, 패키지 설치, 원격 push, PR, merge, 게시는 수행하지 않았습니다.
앱 도구의 managed worktree 생성은 현재 작업 유형에서 지원되지 않아 Git worktree를 사용했습니다.
원본 저장소의 Git 메타데이터에 브랜치와 worktree를 등록하는 작업은 승인 후 완료되었습니다.
