> 보존한 이전 구성입니다. 기본 파일과 명령의 의미가 바뀌었으므로 이 문서의 기본 실행 명령을 복사하지 마세요. 현재 본편과 명시적 Q&A 명령은 [README.md](README.md)를 따르세요.

# warm_alarm macOS 발표 데모

기존 example을 약 86초 동안 조작하고, 녹화 파일에 부드러운 줌·팬을 적용합니다.
별도 저장소나 앱 코드 변경은 필요하지 않습니다.
`osascript`는 앱 포커스와 버튼 조작만 담당하며, 화면 녹화나 커서 추적 기능은 제공하지 않습니다.
실제 녹화는 사용자가 시작하고 종료합니다.

기존 발표 시나리오는 [example README](../../warm_alarm/example/README.md)의 `Inspection and presentation demos`에 있습니다.
그 문서는 Android 알림 권한 전환과 Android/iOS wake-check 결과 비교를 다룹니다.
이 스크립트는 같은 example의 버튼을 이용하는 macOS 단독 리허설용이며, 두 모바일 데모를 검증하거나 자동화하지 않습니다.
권한 변경은 시나리오에서 제외하고 readiness와 예약 결과, 실제 이벤트를 차례로 확인합니다.
example 화면은 호환용 `result.warning`으로 첫 경고만 표시하므로 모든 진단을 보여주는 데모로 설명하지 마세요.

## 실제 발표 자료에 맞춘 데모 B

발표의 기준 자료는 사용자가 제공한 [준비 문서](https://docs.google.com/document/d/14WTwk-MIU3c3sPAjYzJAPoAIIDZPgxtyuQR828fOOHk)와 [슬라이드](https://docs.google.com/presentation/d/1mdHUMZahScIcwoOXhjIS17JCz946oJLNbpGKP3OslVQ)입니다.
2026-10-23에 읽었으며 원본은 수정하지 않았습니다.
문서는 B를 Android/iOS 비교로 설명하고, 현재 슬라이드 13은 Android 대 iOS/macOS로 표시합니다.
여기서는 슬라이드의 macOS 쪽을 준비한다는 가정을 적용했습니다.

| 발표 구간                 | 필요한 장면                                                             | 이 구성의 범위                                                                                                         |
| ------------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 데모 A, 슬라이드 10, 40초 | Android 알림 권한 거부 → limited와 이유 → 설정 변경 → 앱 복귀 후 재조회 | macOS osascript로 자동화하지 않습니다. Android 녹화가 별도로 필요합니다.                                               |
| 데모 B, 슬라이드 13, 30초 | wakeCheck를 포함한 동일 예약의 결과와 경고 비교                         | `scenario-b-macos.json`으로 macOS 쪽만 조작합니다. Android 쪽은 정확 알람 권한을 미리 승인하고 별도로 녹화해야 합니다. |
| 기존 86초 구성            | 예약 후 실제 발화·이벤트 대기                                           | `scenario.json`과 `timeline.json`을 그대로 보존했습니다. B의 30초 장면과 구분하세요.                                   |

B는 알람이 울리는 것을 기다리지 않습니다.
0초에 포커스, 3초에 inspection, 8초에 1분 알람 예약을 누르고, 15~30초에 실제 예약 ID·경고 코드·메시지를 보여줍니다.
`Scheduled alarm id: 42`와 실제 경고를 직접 확인하세요.
예약이 실패하거나 경고가 예상과 다르면 해당 테이크를 성공으로 설명하지 마세요.
**30초 촬영 종료 후에도 약 T+68초에 알람이 울릴 수 있습니다.**
아래 중단·복구 절차에 따라 남은 예약을 처리하고, 처리 전에는 다시 예약하지 마세요.

먼저 권한 조회와 버튼 검사를 완료한 뒤 사용하세요.
첫 명령은 dry run이고, 두 번째 명령만 실제 앱을 조작합니다.
녹화는 두 번째 명령 전에 사용자가 직접 시작해야 합니다.

```bash
python3 scripts/demo/demo.py --scenario scripts/demo/scenario-b-macos.json
python3 scripts/demo/demo.py --scenario scripts/demo/scenario-b-macos.json --run --confirmed-target
```

편집에는 B 전용 타임라인을 함께 지정합니다.
`--start 7.2`는 예시이며 실제 녹화에서 T=0까지의 초로 바꾸세요.
이 명령은 선행 구간만 제거하고 종료 구간을 자르지는 않으므로 T=0 이후 약 30초 분량을 준비하세요.
줌 중심은 미실측 예시이며, Android/iOS와 나란히 합성하는 기능은 포함하지 않습니다.

```bash
python3 scripts/demo/edit.py /path/to/demo-b.mov /path/to/demo-b-edited.mp4 --timeline scripts/demo/timeline-b-macos.json --start 7.2 --dry-run
python3 scripts/demo/edit.py /path/to/demo-b.mov /path/to/demo-b-edited.mp4 --timeline scripts/demo/timeline-b-macos.json --start 7.2
```

## 구성과 전제조건

| 파일                         | 용도                                                      |
| ---------------------------- | --------------------------------------------------------- |
| `scenario.json`              | 화면 조작 순서, 시각, 버튼 이름을 지정합니다.             |
| `demo.py`, `ui.applescript`  | 정해진 시각에 System Events로 앱을 조작합니다.            |
| `timeline.json`              | 녹화 후 편집에 사용할 시각, 배율, 화면 중심을 지정합니다. |
| `edit.py`                    | ffmpeg로 확대·이동을 보간하고 MP4로 저장합니다.           |
| `doctor.sh`, `permissions.m` | 권한 요청 없이 현재 실행 주체의 권한을 조회합니다.        |
| `verify.py`                  | 화면을 촬영하지 않고 합성 영상으로 검증합니다.            |

macOS의 `osascript`, Xcode Command Line Tools의 `clang`/`osacompile`, Python 3가 필요합니다.
후처리와 합성 검증에는 `libx264` 인코더가 포함된 `ffmpeg` 및 `ffprobe`가 필요합니다.
추가 Python 패키지는 사용하지 않으며 어떤 스크립트도 도구를 설치하지 않습니다.
녹화에는 macOS 기본 스크린샷 도구(Shift-Command-5)를 사용할 수 있습니다.
시스템 알람 소리까지 담아야 한다면 선택한 녹화 도구가 시스템 오디오를 지원하는지 별도로 확인하세요.
기본 도구의 마이크 옵션만으로 앱의 내부 오디오 녹음을 보장할 수는 없습니다.

대상은 `warm_alarm/example`의 **macOS 앱**입니다.
소스의 제품 이름은 `example`, 번들 ID는 `com.example.myplugin.example`입니다.
일반적인 이름으로 앱을 자동 실행하지 않고, 이미 실행된 프로세스를 번들 ID로 한정합니다.
이 값은 소스에서 확인했으며 실제 실행 중인 앱의 식별자와 접근성 구조는 아직 검증하지 못했습니다.
시뮬레이터나 Android 창은 이 시나리오의 직접 조작 대상이 아닙니다.

## 리허설 준비

저장소 루트에서 실행합니다.

```bash
./scripts/demo/doctor.sh
python3 scripts/demo/demo.py
```

두 번째 명령은 기본 dry run입니다.
UI 조작, 대기, 예약, 녹화를 수행하지 않습니다.
`doctor.sh`는 임시 디렉터리에 조회 도구를 컴파일한 뒤 삭제하며, 권한 팝업을 요청하거나 설정을 바꾸지 않습니다.
권한은 실행 주체에 따라 달라지므로 리허설에 사용할 Terminal에서도 확인해야 합니다.
화면 기록은 실제 녹화 앱을 기준으로 별도 확인하세요.

접근성은 Terminal 등 실행 호스트에, 자동화는 그 호스트에서 System Events로의 제어에 필요합니다.
화면 기록은 선택한 녹화 앱에 필요합니다.
필요하다면 사용자가 시스템 설정의 개인정보 보호 및 보안에서 직접 허용해야 합니다.
자동화 조회 코드 `0`은 허용, `-1744`는 동의 필요, `-1743`은 거부입니다.
그 밖의 코드는 확인 실패이며, 허용으로 해석하면 안 됩니다.
조회 프로그램의 자동화 결과가 `osascript`의 실제 권한을 완전히 보증하지는 않습니다.

example을 직접 실행하고 앱의 알림 권한을 미리 확인하세요.
이미 의존성과 빌드 환경이 준비되어 있다면 별도 Terminal에서 다음 명령을 사용할 수 있습니다.

```bash
cd warm_alarm/example
flutter run --no-pub -d macos
```

이 작업에서는 앱을 빌드하거나 실행하지 않았습니다.
현재 할당된 `chore/macos-presentation-demo` 브랜치와 worktree를 재사용했습니다.
다른 worktree의 `.dart_tool`이나 빌드 결과가 이 작업 경로에도 있다고 가정하지 마세요.
의존성이 없다면 위 명령이 실패할 수 있으며, 이 스크립트가 자동으로 의존성을 내려받지는 않습니다.
Flutter의 첫 빌드, 알림 권한 대화상자, 시스템 설정 조작은 데모 순서에 넣지 마세요.

앱을 새로 열어 이전 예약 상태를 확인하고, 두 버튼이 모두 보이도록 창 크기와 스크롤 위치를 직접 맞춥니다.
화면 조작 좌표는 사용하지 않습니다.
다음 명령은 버튼의 접근성 레이블만 읽습니다. 앱 활성화나 클릭은 하지 않습니다.

```bash
python3 scripts/demo/demo.py --inspect --confirmed-target
```

`Inspect Alarm API`와 `Schedule 1 minute alarm`이 정확히 출력되는지 확인하세요.
같은 레이블이 여러 번 출력될 수 있습니다.
검사는 버튼마다 `AXTitle`, `AXDescription`, `AXValue`를 읽지만, 클릭 대상은 각 버튼 노드당 한 번만 수집합니다.
서로 다른 버튼 노드가 같은 레이블로 일치하면 실제 조작은 중단됩니다.
Flutter가 접근성 버튼을 노출하지 않거나 일치하는 버튼이 없거나 여러 개이면 실행은 중단됩니다.
권한이나 레이블이 확인되지 않으면 실제 실행을 진행하지 마세요.
좌표 클릭으로 임의 대체하지 않으며, 수동 데모 후 동일한 후처리를 사용할 수 있습니다.

`--inspect`가 빈 출력으로 끝나는 것은 버튼 확인 성공이 아닙니다.
현재 버전은 이 경우 `No labeled AXButtons found` 오류로 종료합니다.
프로세스·창을 찾았지만 레이블이 없는 경우와 접근성 속성 읽기 중 오류가 난 경우는 아직 구분하지 못합니다.
Flutter 접근성 트리 미노출은 가능한 원인이지만, 빈 출력만으로 확정할 수 없습니다.
`Failed to foreground app; open returned 1`이 보였다면 앱 창을 먼저 직접 열고 실제 화면이 보이는지 확인하세요.
같은 Terminal에서 다음 읽기 전용 명령으로 창 내부 요소가 노출되는지 확인할 수 있습니다.

```bash
osascript <<'APPLESCRIPT'
tell application "System Events"
  set targets to every application process whose bundle identifier is "com.example.myplugin.example"
  if (count targets) is not 1 then error "Expected one running example process"
  set targetProcess to item 1 of targets
  tell targetProcess
    if (count windows) is 0 then error "No accessible window"
    return entire contents of window 1
  end tell
end tell
APPLESCRIPT
```

사용자 Terminal에서 이 명령을 실행한 결과, 처음에는 창 제어 버튼만 노출되고 Flutter 본문 그룹의 자식은 `0`이었습니다.
이후 VoiceOver 활성화 진단 단계에서 `--inspect`가 실제 example 버튼 레이블을 반환했습니다.
현재 환경에서 재현할 때는 example을 실행한 뒤 VoiceOver를 수동으로 잠시 켜고 inspection을 수행하세요.
검사가 통과하면 VoiceOver를 유지한 상태로 사용자가 녹화를 시작하고 시나리오를 실행한 뒤 녹화를 종료합니다.
시나리오가 끝나면 사용자가 VoiceOver를 원래 상태로 복구하세요.
VoiceOver를 끈 뒤에도 버튼 트리가 유지되는지는 확인하지 못했습니다.
VoiceOver 안내 음성이 촬영에 들어갈 수 있으므로 녹화 도구의 오디오 설정을 먼저 확인하세요.
스크립트는 VoiceOver나 시스템 권한을 변경하지 않습니다.
접근성 권한이 거부되면 해당 실행 호스트의 권한부터 확인하고, 요소나 버튼이 노출되지 않으면 시나리오를 실행하지 마세요.
`doctor.sh`의 자동화 조회가 `-600`이어도 허용·거부 여부는 확정되지 않습니다.
Terminal과 에이전트, 조회용 프로그램과 실제 osascript의 권한 결과를 혼용하지 마세요.
Terminal의 화면 기록이 미허용이어도 선택한 녹화 앱의 권한은 별도로 확인해야 합니다.

## 녹화 및 실행

1. 개인 창과 알림 노출 가능성을 직접 점검하고, 촬영할 앱 영역을 선택합니다.
2. Shift-Command-5에서 녹화 영역과 저장 위치, 필요한 마이크 옵션을 확인한 뒤 직접 녹화를 시작합니다.
3. 준비된 Terminal에서 다음 명령을 실행합니다. 5초 카운트다운 뒤 앱에 포커스를 줍니다.

```bash
python3 scripts/demo/demo.py --run --confirmed-target
```

4. `T=0` 이후의 조작 시각을 기준으로 녹화 시작 부분을 맞춥니다. 로그를 보존하려면 다음처럼 실행할 수 있습니다.

```bash
python3 -u scripts/demo/demo.py --run --confirmed-target > /tmp/warm-alarm-take.log 2>&1
```

5. 86초 시나리오가 끝나면 메뉴 막대의 정지 버튼 또는 Control-Command-Escape로 녹화를 직접 종료합니다.

| 시각    | 화면 조작과 발표 내용                                                                       |
| ------- | ------------------------------------------------------------------------------------------- |
| 0초     | 앱 전체를 보여줍니다.                                                                       |
| 4초     | `Inspect Alarm API`를 눌러 readiness와 플랫폼 기능을 설명합니다.                            |
| 12초    | `Schedule 1 minute alarm`을 누릅니다. 실제 알람 ID는 42이며 약 72초 시점에 울릴 예정입니다. |
| 12~78초 | 예약 결과와 macOS의 지원 범위를 설명합니다. 임의로 시간을 단축하지 않습니다.                |
| 78~86초 | 실제 이벤트 목록과 알림을 확인하고 마칩니다.                                                |

앱이나 시스템 상태에 따라 예약 실패, 경고, 이벤트 지연이 발생할 수 있습니다.
스크립트의 클릭 성공은 API 호출이나 알람 재생 성공을 뜻하지 않습니다.
예약 ID와 warning, 실제 fired 이벤트는 발표자가 화면에서 확인해야 합니다.
2초를 넘는 실행 지연이나 10초를 넘는 AppleScript 호출은 실패로 처리합니다.

## 줌·팬 후처리

`timeline.json`은 화면 조작 시나리오와 독립적입니다.
시각은 모두 녹화 파일의 선행 부분을 제거한 뒤의 `T=0`을 기준으로 합니다.
`zoom`은 1~3배, `x`/`y`는 원본 화면에서 초점을 둘 중심 위치(왼쪽/위쪽 0, 오른쪽/아래쪽 1)입니다.
현재 중심 좌표는 **실측하지 않은 예시 값**입니다.
실제 녹화 구도에 맞게 수정하고 편집 결과를 확인하세요.
앱 바깥 전체 화면을 녹화하면 같은 값으로 버튼 위치를 가리키지 못할 수 있습니다.
가장자리에서는 화면 밖으로 벗어나지 않도록 중심이 제한됩니다.
키프레임 사이를 smoothstep으로 보간하므로 확대·이동이 부드럽게 시작하고 끝납니다.
커서 위치를 읽거나 자동 추적하지 않습니다.

```bash
python3 scripts/demo/edit.py /path/to/take.mov /path/to/demo-edited.mp4 --start 7.2 --dry-run
python3 scripts/demo/edit.py /path/to/take.mov /path/to/demo-edited.mp4 --start 7.2
```

`7.2`는 예시입니다. 실제 녹화에서 시나리오 시작 전까지의 초로 바꾸세요.
실행 전 전체 경로와 편집 시작점을 확인하세요.
원본과 같은 경로 또는 기존 출력 파일을 지정하면 거부합니다.
마지막 키프레임(기본 84초)보다 짧은 영상도 거부합니다.
출력은 원본 크기를 기준으로 짝수 픽셀에 맞춘 30fps H.264 MP4이며, 첫 번째 오디오 트랙이 있으면 AAC로 다시 인코딩합니다.
오디오 트랙이 없는 원본에 소리를 추가하지 않습니다.
회전 메타데이터에 의존하지 않는 가로 방향 macOS 캡처를 사용하세요.
고해상도 파일은 원본을 2배로 확대하여 처리하므로 시간이 걸릴 수 있습니다.

## 중단과 복구

- Terminal에서 Control-C를 누르면 이후 조작을 중단합니다. 진행 중인 클릭이 이미 반영되었을 수 있습니다.
- 녹화는 별도로 종료해야 합니다. 자동 종료나 강제 앱 종료는 수행하지 않습니다.
- 이미 예약된 ID 42는 Control-C나 앱 종료만으로 취소되지 않습니다. example에는 예약 취소 버튼이 없습니다.
- 발화한 알림의 `Stop`을 직접 선택하세요. `Snooze`는 새 예약을 만들 수 있으므로 복구 중에는 누르지 마세요.
- 발화 전 취소가 꼭 필요하면 실행 중인 앱의 Dart 디버거에서 `WarmAlarm.cancelAlarm(42)` 호출을 완료해야 합니다. 이는 앱 안에서 실행할 API이며 셸 명령이 아닙니다. 이 스크립트는 그 디버거 연결을 제공하지 않습니다.
- 디버거를 사용할 수 없다면 한 번 예약된 1분 알람이 울릴 수 있음을 고려하고, 알림에서 정지한 뒤 다음 녹화를 시작하세요. 앱의 알림 허용 상태 때문에 정지 동작도 사용할 수 없다면 먼저 그 상태를 수동으로 해결해야 합니다.
- 재시도 전 앱의 readiness, 남은 알림과 예약 상태, 버튼 노출 상태를 확인하세요. 원치 않는 예약을 반복하지 마세요.
- 편집 중 Control-C나 ffmpeg 실패로 생긴 불완전한 출력 파일은 해당 파일을 확인한 뒤 직접 지우거나 새 출력 이름으로 재시도하세요. 원본은 덮어쓰지 않습니다.

## 검증 재실행

```bash
python3 scripts/demo/verify.py
shellcheck scripts/demo/doctor.sh
```

검증은 임시 폴더에 9초짜리 합성 영상과 기본 타임라인용 86초짜리 무음 합성 영상, 각 편집 결과를 생성합니다.
B 전용 30초 dry run과 합성 영상 편집도 검사합니다.
구문, dry run, 실행 확인 플래그, 잘못된 설정 거부, 확대 전후 픽셀 차이, 출력 길이·크기·프레임률, 오디오 존재, 덮어쓰기 방지를 확인합니다.
거부 검사는 비정상 종료뿐 아니라 예상 오류 메시지도 확인합니다.
줌 판정이 확대하지 않은 프레임을 거부하는지 먼저 확인한 뒤 실제 편집 결과를 검사합니다.
`preview-0.png`, `preview-120.png`, `preview-240.png`는 합성 결과의 전체 화면·확대·전체 화면 구간입니다.
화면이나 마이크는 캡처하지 않고 Apple Events도 보내지 않습니다.
출력된 임시 폴더에서 결과를 직접 재생할 수 있습니다.
실제 앱의 버튼, 알람 소리, 녹화 품질, 발표 구도는 별도 현장 검증이 필요합니다.
현재 실행 환경에서 확인한 결과는 [VALIDATION.md](VALIDATION.md)에 기록했습니다.
