# 코드베이스 전체 리뷰: 미구현 및 개선 백로그

**검토일:** 2026-08-13
**범위:** 공개 Dart API, 세 플랫폼의 Dart/Pigeon 경계, Android Kotlin 런타임, iOS/macOS Swift 런타임,
테스트, CI, 문서/배포 설정
**방법:** 정적 코드 추적, `TODO`/미지원 표면 검색, 구현 계획과 현재 코드 비교, 워크스페이스 단위 테스트 실행

## 요약

현재 Phase 4 API까지 코드는 들어와 있지만, 저장소 문서는 여전히 Phase 4를 계획 상태로 표시한다. 더 중요한 문제는
Android 주간 반복 정보가 영속화 과정에서 사라지는 것과 Apple `init()`이 반복 알람을 단발성 알람으로 중복 복구하는
것이다. 두 문제 모두 프로세스 재시작/재부팅이라는 알람 플러그인의 핵심 경계에서 발생하므로 출시 전에 먼저 해결해야 한다.

우선순위별 결과는 다음과 같다.

- **P0 (출시 차단): 2개** — Android 반복 알람 영속화, Apple 반복 알람 초기화 복구
- **P1 (높음): 5개** — capability 오보고 2건, Apple 부분 성공, 입력 검증/오류 의미론, 네이티브 회귀 테스트 부재
- **P2 (중간): 7개** — 이벤트 내구성, 저장소 방어성, 권한 UX, 오디오 의미론, CI/E2E, 문서 드리프트, Apple 테스트 격차
- **P3 (낮음/배포 준비): 3개** — Privacy Manifest 판단, 예제 릴리스 설정, 패키지 공개 준비

## P0 — 출시 차단 결함

### 1. Android 주간 반복 정보가 저장 직후 소실됨

`WarmAlarmPlugin.scheduleAlarm()`은 `schedule.recurrence`로 첫 발생 시각을 계산한 뒤 전체 스케줄을 저장한다. 그러나
`WarmAlarmStore.encode()`는 `snooze`, `wakeCheck`, `payload` 등은 직렬화하면서 `recurrence`를 기록하지 않고,
`decode()`도 이를 복원하지 않는다. 이후 receiver가 저장소에서 다시 읽으면 `recurrence == null`이므로 다음 주 발생을
재등록하지 않는다. `getScheduledAlarms()`의 snapshot과 재부팅 복구에도 같은 손실이 전파된다.

**미구현 항목**

- `recurrence.weekdays` JSON encode/decode 및 기존 데이터 마이그레이션/기본값 처리
- `WarmAlarmStore` 왕복 테스트(반복, wake-check, fade, nullable payload를 한 필드씩 추가)
- 프로세스 재시작 및 재부팅 뒤 다음 주 발생을 검증하는 Android 통합 테스트

**TDD 순서**

1. recurrence가 포함된 wire schedule을 저장/로드하면 weekdays가 동일하다는 실패 테스트를 추가한다(Red).
2. recurrence만 최소 직렬화하여 통과시킨다(Green).
3. JSON 필드 접근과 테스트 fixture 중복을 별도 structural commit으로 정리한다(Refactor).

### 2. iOS/macOS `init()`이 반복 알람을 단발성 알람으로 중복 등록함

반복 알람의 실제 pending identifier는 `"{id}#{weekday}"`인데 `initialize()`는 `"{id}"`만 조회한다. 따라서 정상적으로
반복 요청들이 남아 있어도 항상 누락으로 판단하고 저장된 최초 시각에 단발성 요청을 하나 더 등록한다. 또한 복구 경로는
`makeRequests()`를 사용하지 않아 반복 규칙을 복원하지 못한다. 동일한 구현이 iOS와 macOS에 복제되어 있다.

**미구현 항목**

- 저장된 recurrence의 모든 예상 identifier를 계산하고 실제 pending set과 비교하는 복구 로직
- 누락된 weekday 요청만 다시 만드는 idempotent `init()`
- iOS/macOS 공통 시나리오 테스트: 전부 존재, 일부 누락, 전부 누락, 단발성, 반복성

## P1 — 높은 우선순위

### 3. Android `wakeCheck` capability가 실제 구현 및 README와 반대로 `unsupported`

Android에는 wake-check notification, dismiss, retrigger, 관련 이벤트가 구현되어 있고 README는 “Full”로 광고한다. 반면
native `getCapabilities()`와 Dart 테스트 fixture는 `unsupported`를 반환한다. capability-first라는 핵심 계약을 위반해
정상 클라이언트가 구현된 기능을 사용하지 않게 만든다.

**개선:** 먼저 capability가 `supported`여야 한다는 실패 테스트를 쓰고 native 값과 fixture를 함께 수정한다. 실제 제약이
있다면 `limited`로 정의하고 제한 조건을 README와 모델 문서에 명시한다.

### 4. iOS `liveActivity` capability는 구현 없이 `supported`

저장소에는 ActivityKit import, Activity 정의, 시작/갱신/종료 코드가 없지만 iOS는 `liveActivity: .supported`를 반환한다.
이는 Android와 반대 방향의 오보고이며 소비자가 존재하지 않는 기능을 신뢰하게 한다.

**미구현/개선 선택지**

- 현재 릴리스: 값을 `unsupported`로 낮추고 회귀 테스트를 고친다.
- 향후 기능: ActivityKit extension/attributes/lifecycle/API를 별도 기능으로 TDD 구현한 뒤 capability를 올린다.

### 5. Apple 반복 스케줄 등록이 원자적이지 않음

여러 weekday 요청 중 첫 요청만 completion 결과를 확인하고 나머지는 fire-and-forget이다. 추가 요청 일부가 실패해도 성공을
반환하고 전체 schedule을 저장하므로 실제 pending 요청과 snapshot이 달라진다.

**개선:** 모든 `center.add` 결과를 모아 전부 성공했을 때만 저장/성공을 반환하고, 실패하면 이번 호출이 만든 요청을
rollback한다. 부분 실패를 주입하는 테스트부터 작성한다.

### 6. 스케줄 입력 검증과 실패 의미론이 부족함

과거 시각, 빈 recurrence, 1~7 범위를 벗어난 weekday, 음수 duration, 잘못된 volume/fade 순서, 동시에 지정된 오디오
소스 등의 정책이 public model/native 경계에 일관되게 강제되지 않는다. Android는 저장 후 스케줄링 API를 바로 호출하고,
Apple은 일부 native 오류를 `Future` 실패가 아닌 “성공 결과 + limited warning”으로 바꾼다. 이미 정의된
`invalidArguments`, `audioFileNotFound`, `permissionDenied` 등의 failure code가 충분히 활용되지 않는다.

**개선:** 플랫폼 공통 validation contract를 문서화하고 public 생성자 또는 facade에서 결정론적 검증을 수행한다. 각 규칙은
한 번에 하나의 실패 테스트로 추가하고, 구조 정리와 행위 변경 commit을 분리한다.

### 7. 네이티브 저장/복구 경로가 CI에서 검증되지 않음

Dart wrapper 테스트는 wire 변환을 잘 덮지만 Android `WarmAlarmStore` 테스트가 없고, 현재 package workflow가 Gradle
unit test나 Swift test를 명시적으로 실행하지 않는다. iOS에는 일부 Swift 테스트가 있지만 macOS에는 native test target
자체가 없다. P0 결함들이 Dart 테스트를 모두 통과할 수 있는 이유다.

**미구현 항목**

- Android: `WarmAlarmStoreTest`, receiver/service 상태 전이 테스트, `./gradlew test`
- iOS/macOS: store/plugin recovery 테스트와 `swift test` 또는 `xcodebuild test`
- 각 플랫폼 CI에 네이티브 테스트 job 추가

## P2 — 중간 우선순위

### 8. 대부분의 background 이벤트가 유실될 수 있음

Android는 snooze만 별도 pending store로 재생한다. fired/stopped/failed/wake-check/retrigger 이벤트는 Flutter engine이 없는
동안 `pluginInstance == null`이면 즉시 버려진다. Apple도 `eventsApi.emitEvent`만 호출한다. “실시간 stream”으로 한정할
것인지, 알람 앱이 다음 실행 때 핵심 lifecycle을 복구할 수 있어야 하는지 계약이 불명확하다.

**개선:** live-only를 유지한다면 공개 문서에 명확히 명시한다. 내구성이 필요하면 bounded native event journal과
`init()` drain을 설계하고, 순서/중복/손상 복구 테스트를 먼저 작성한다.

### 9. Android 저장소가 손상된 JSON 한 건에 전체 조회를 실패시킴

`JSONArray(json)`과 각 record의 필수 `get*` 호출에 방어 처리가 없다. 앱 업데이트, 부분 write, 수동 손상 중 한 건만
발생해도 모든 알람 조회/복구가 예외로 중단된다. `SharedPreferences.apply()`의 비동기 write 직후 프로세스 종료도 중요한
알람 데이터에 적합한지 검토가 필요하다.

**개선:** schema version을 추가하고, record 단위 decode 실패 격리/telemetry, 원자적 commit 정책을 정의한다. 손상된 한
record와 정상 record가 섞인 fixture로 기대 정책을 먼저 테스트한다.

### 10. 권한 상태 조회만 있고 해결 동작이 없음

API는 readiness reason을 알려주지만 notification/exact alarm/full-screen 설정 화면을 열거나 권한을 요청하는 편의 API가
없다. 예제도 점검 중심이어서 사용자가 blocked/limited 상태를 해결하는 end-to-end 흐름을 증명하지 못한다.

**미구현 항목:** permission request/settings intent API 또는 명시적인 app-owned UX 가이드, reason별 예제 UI, 기기 E2E.

### 11. 오디오 옵션의 플랫폼별 의미가 일치하지 않음

Android는 `filePath`와 `assetPath`가 모두 있으면 음성 1회 + 배경 layer를 재생하지만 Apple은 `filePath`만 선택한다.
Android `volumeEnforced`는 시스템 alarm stream 자체를 최대로 바꾸는 반면 Apple은 player volume만 1.0으로 유지한다.
`vibrate`도 manifest/모델에는 있으나 실제 진동 호출을 찾을 수 없다. 이 차이가 capability나 API 문서에 드러나지 않는다.

**개선:** 공통 의미를 결정하거나 platform-honest 제한을 문서/모델로 노출한다. 특히 시스템 볼륨 변경은 이전 값을 복구하고
사용자 동의를 고려해야 한다. 각 플랫폼의 선택/loop/fade/vibrate 계약 테스트가 필요하다.

### 12. E2E가 red 상태로 PR에서 비활성화됨

workflow 주석상 Android와 iOS E2E가 red이며 수동 실행/태그에서만 돈다. macOS E2E job은 현재 workflow에 없다. 따라서
일반 PR은 핵심 런타임 smoke test 없이 병합될 수 있다.

**개선:** readiness flow부터 안정화해 PR required check로 복귀시키고, 실제 schedule/fire/cancel 최소 flow를 플랫폼별로
추가한다. 시간 의존 테스트에는 clock abstraction 또는 충분한 deadline/진단 artifact를 둔다.

### 13. 구현 상태 문서가 코드와 어긋남

루트 README는 Phase 4를 Planned로 표시하지만 `init()`, `hasAlarm()`, `getAlarm()`, full-screen toggle과 플랫폼 테스트가
이미 존재한다. Phase 4 계획 checklist도 미체크 상태다. API 표에는 `init`, `hasAlarm`, `getAlarm`이 빠져 있다.

**개선:** 기능을 검증한 뒤 Phase 4를 Done/부분 완료로 정확히 갱신하고, 남은 결함은 별도 issue/checklist로 분리한다.
완료 표시는 테스트 증거와 함께 변경한다.

### 14. Apple 플랫폼 테스트 대칭성이 부족함

iOS에는 recurrence/store Swift tests가 있지만 macOS에는 native Tests 디렉터리가 없고 Package.swift에도 test target이 없다.
두 구현은 복사본이라 drift가 발생하기 쉽고, 실제로 같은 `init()` 결함이 양쪽에 복제되어 있다.

**개선:** 공유 가능한 pure Swift recurrence/recovery logic을 작은 module로 추출하는 structural change를 먼저 검토하거나,
최소한 동일 contract test suite를 두 package에 둔다. 추출 전후 테스트가 모두 green임을 확인한다.

## P3 — 배포 준비 및 유지보수

### 15. Apple Privacy Manifest 판단이 TODO로 남음

두 Package.swift에 PrivacyInfo.xcprivacy TODO placeholder가 남아 있다. 사용하는 API가 required-reason 대상인지 릴리스 전에
감사하고, 필요하면 SwiftPM resources와 podspec resource bundle을 동시에 연결해야 한다.

### 16. 예제 Android 릴리스 설정이 placeholder

example application ID와 release signing TODO가 남아 있다. 예제 배포 의도가 없다면 문서로 명확히 하고, 스토어/릴리스
artifact를 만들 계획이면 고유 ID와 안전한 CI signing 구성을 추가해야 한다.

### 17. 패키지 공개 준비가 완료되지 않음

README가 pub.dev 미게시 상태를 명시한다. publish 전에는 각 package의 `pana`, changelog/version, README capability 표,
license check, generated-code 재현성, native 최소 버전, 실제 기기 증거를 하나의 release checklist로 묶어야 한다.

## 권장 실행 순서 (TDD + Tidy First)

1. **행위 수정:** Android recurrence store 왕복 실패 테스트 → 최소 구현 → 전체 테스트.
2. **행위 수정:** iOS/macOS idempotent recurrence recovery 실패 테스트 → 최소 구현 → 전체 테스트.
3. **행위 수정:** Android wake-check 및 iOS Live Activity capability contract 테스트 → 보고값 수정.
4. **구조 수정:** Apple request identifier 계산을 pure helper로 추출하고 양 플랫폼에 동일 테스트 적용.
5. **행위 수정:** Apple multi-request 부분 실패/rollback 테스트 → 원자적 scheduling.
6. **구조 수정:** native test commands를 공통 CI workflow/job으로 정리.
7. **행위 수정:** 손상 저장소, 입력 validation, durable event 정책을 작은 slice별로 구현.
8. 모든 검증이 green인 뒤에만 README/phase checklist를 실제 상태로 갱신한다.

각 단계는 structural/behavioral commit을 섞지 않고, 한 번에 하나의 실패 테스트를 추가한 뒤 Green을 확인한다. 네이티브 변경은
Dart test만이 아니라 해당 Gradle/Swift test와 가능한 플랫폼 E2E까지 통과해야 완료로 간주한다.

## 검증 메모

- 워크스페이스 의존성은 `flutter pub get`으로 해석했다.
- Dart/Flutter package unit tests는 `dart run melos run test:ci`로 실행했다.
- 정적 형식/공백 오류는 `git diff --check`로 확인했다.
- Android/iOS/macOS 기기 E2E는 이 Linux 검토 환경에서 실행하지 않았다.
- 작업 시작 시 이미 수정되어 있던 7개 `analysis_options.yaml` 파일은 본 리뷰에서 변경하거나 commit하지 않았다.
