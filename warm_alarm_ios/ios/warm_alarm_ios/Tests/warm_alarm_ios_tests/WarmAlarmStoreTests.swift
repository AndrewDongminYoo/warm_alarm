import XCTest

@testable import warm_alarm_ios

final class WarmAlarmStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WarmAlarmStore.shared.clear()
    }

    func testSaveAndLoad() {
        let data = makeData(id: 1, title: "Wake up", scheduledAt: 1_000_000)
        WarmAlarmStore.shared.save(data)
        let loaded = WarmAlarmStore.shared.load(id: 1)
        XCTAssertEqual(loaded?.id, 1)
        XCTAssertEqual(loaded?.notificationTitle, "Wake up")
        XCTAssertEqual(loaded?.scheduledAtMillis, 1_000_000)
    }

    func testRemove() {
        WarmAlarmStore.shared.save(makeData(id: 2))
        WarmAlarmStore.shared.remove(id: 2)
        XCTAssertNil(WarmAlarmStore.shared.load(id: 2))
    }

    func testReplacingAndRemovingSchedulesDeletesOnlyUnreferencedSounds() throws {
        let directory = WarmAlarmSoundFiles.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oldName = "warm-alarm-\(UUID().uuidString).caf"
        let newName = "warm-alarm-\(UUID().uuidString).caf"
        let oldURL = directory.appendingPathComponent(oldName)
        let newURL = directory.appendingPathComponent(newName)
        try Data([1]).write(to: oldURL)
        try Data([2]).write(to: newURL)
        var first = makeData(id: 1).withAlarmKitManaged(true)
        first.systemSoundFilePath = oldURL.path
        first.alarmKitSoundName = oldName
        WarmAlarmStore.shared.save(first)
        var second = makeData(id: 2).withAlarmKitManaged(true)
        second.systemSoundFilePath = oldURL.path
        second.alarmKitSoundName = oldName
        WarmAlarmStore.shared.save(second)

        first.systemSoundFilePath = newURL.path
        first.alarmKitSoundName = newName
        WarmAlarmStore.shared.save(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldURL.path))
        WarmAlarmStore.shared.remove(id: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(WarmAlarmStore.shared.load(id: 1)!.systemManagedAudio)
        WarmAlarmStore.shared.save(first.withAlarmKitManaged(false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertFalse(WarmAlarmStore.shared.load(id: 1)!.systemManagedAudio)
        XCTAssertNil(WarmAlarmStore.shared.load(id: 1)!.systemSoundFilePath)
    }

    func testSnoozeAndRecurringStateCopiesKeepSystemSoundOwnership() {
        var data = makeData(id: 3).withAlarmKitManaged(true)
        data.systemSoundFilePath = "/Library/Sounds/warm-alarm-test.caf"
        data.alarmKitSoundName = "warm-alarm-test.caf"
        let snoozed = data.withActiveSnooze(untilMillis: 1000)
        XCTAssertTrue(snoozed.systemManagedAudio)
        XCTAssertEqual(snoozed.clearingActiveSnooze().alarmKitSoundName, data.alarmKitSoundName)
        XCTAssertEqual(snoozed.withRecurrenceTime(hour: 8, minute: 0).systemSoundFilePath, data.systemSoundFilePath)
    }

    func testLoadAllReturnsAllSaved() {
        WarmAlarmStore.shared.save(makeData(id: 10))
        WarmAlarmStore.shared.save(makeData(id: 11))
        XCTAssertEqual(WarmAlarmStore.shared.loadAll().count, 2)
    }

    func testClearRemovesAll() {
        WarmAlarmStore.shared.save(makeData(id: 20))
        WarmAlarmStore.shared.clear()
        XCTAssertTrue(WarmAlarmStore.shared.loadAll().isEmpty)
    }

    func testRoundtripPreservesOptionals() {
        let data = WarmAlarmScheduleData(
            id: 99, scheduledAtMillis: 9_000,
            oneShotOccurrenceEpochMillis: 8_900,
            occurrenceSeriesToken: "series-99",
            notificationTitle: "T", notificationBody: "B",
            stopActionTitle: "Stop", snoozeActionTitle: "Snooze",
            filePath: "/tmp/alarm.mp3", assetPath: nil,
            loop: false, volume: 0.75, vibrate: true,
            fadeInDurationMillis: 3_000,
            recurrenceWeekdays: [1, 3, 5],
            recurrenceHour: 7,
            recurrenceMinute: 30,
            snoozeDurationMillis: 300_000,
            payload: "{\"key\":\"value\"}",
            volumeEnforced: nil,
            fadeSteps: nil,
            keepNotificationAfterAlarmEnds: nil,
            activeSnoozeUntilMillis: 9_500,
            fallbackAnchorMillis: 9_100,
            alarmKitManaged: true,
            alarmKitSnoozeObserved: true
        )
        WarmAlarmStore.shared.save(data)
        let loaded = WarmAlarmStore.shared.load(id: 99)!
        XCTAssertEqual(loaded.stopActionTitle, "Stop")
        XCTAssertEqual(loaded.snoozeActionTitle, "Snooze")
        XCTAssertEqual(loaded.filePath, "/tmp/alarm.mp3")
        XCTAssertNil(loaded.assetPath)
        XCTAssertFalse(loaded.loop)
        XCTAssertEqual(loaded.volume, 0.75)
        XCTAssertTrue(loaded.vibrate)
        XCTAssertEqual(loaded.fadeInDurationMillis, 3_000)
        XCTAssertEqual(loaded.recurrenceWeekdays, [1, 3, 5])
        XCTAssertEqual(loaded.recurrenceHour, 7)
        XCTAssertEqual(loaded.recurrenceMinute, 30)
        XCTAssertEqual(loaded.snoozeDurationMillis, 300_000)
        XCTAssertEqual(loaded.payload, "{\"key\":\"value\"}")
        XCTAssertEqual(loaded.activeSnoozeUntilMillis, 9_500)
        XCTAssertEqual(loaded.fallbackAnchorMillis, 9_100)
        XCTAssertEqual(loaded.oneShotOccurrenceEpochMillis, 8_900)
        XCTAssertEqual(loaded.occurrenceSeriesToken, "series-99")
        XCTAssertTrue(loaded.alarmKitManaged)
        XCTAssertTrue(loaded.alarmKitSnoozeObserved)
    }

    func testRoundtripNilOptionals() {
        let data = makeData(id: 50)
        WarmAlarmStore.shared.save(data)
        let loaded = WarmAlarmStore.shared.load(id: 50)!
        XCTAssertNil(loaded.volume)
        XCTAssertFalse(loaded.vibrate)
        XCTAssertNil(loaded.fadeInDurationMillis)
        XCTAssertNil(loaded.recurrenceWeekdays)
        XCTAssertNil(loaded.recurrenceHour)
        XCTAssertNil(loaded.recurrenceMinute)
        XCTAssertNil(loaded.snoozeDurationMillis)
        XCTAssertNil(loaded.payload)
        XCTAssertNil(loaded.activeSnoozeUntilMillis)
        XCTAssertNil(loaded.fallbackAnchorMillis)
        XCTAssertFalse(loaded.alarmKitManaged)
    }

    func testAlarmKitManagementMarkerCanBeChangedWithoutLosingScheduleData() {
        let schedule = makeData(id: 42, title: "Wake up", scheduledAt: 1_000)

        let managed = schedule.withAlarmKitManaged(true)
        let fallback = managed.withAlarmKitManaged(false)

        XCTAssertTrue(managed.alarmKitManaged)
        XCTAssertEqual(managed.notificationTitle, "Wake up")
        XCTAssertEqual(managed.scheduledAtMillis, 1_000)
        XCTAssertFalse(fallback.alarmKitManaged)
    }

    func testAlarmKitSnoozeObservationMarkerSurvivesRoundtripAndClearsWithSnooze() {
        let schedule = makeData(id: 43).withAlarmKitSnoozeObserved()
        WarmAlarmStore.shared.save(schedule)

        let loaded = WarmAlarmStore.shared.load(id: 43)!
        XCTAssertTrue(loaded.alarmKitSnoozeObserved)
        XCTAssertFalse(loaded.clearingActiveSnooze().alarmKitSnoozeObserved)
    }

    func testAddingActiveSnoozeClearsFallbackAnchorAndPreservesRecurringScheduleTime() {
        let schedule = makeData(
            id: 42,
            scheduledAt: 1_000,
            recurrenceWeekdays: [1, 3, 5],
            recurrenceHour: 7,
            recurrenceMinute: 30,
            fallbackAnchorMillis: 1_500
        )

        let snoozed = schedule.withActiveSnooze(untilMillis: 3_000)

        XCTAssertEqual(snoozed.scheduledAtMillis, 1_000)
        XCTAssertEqual(snoozed.recurrenceWeekdays, [1, 3, 5])
        XCTAssertEqual(snoozed.recurrenceHour, 7)
        XCTAssertEqual(snoozed.recurrenceMinute, 30)
        XCTAssertEqual(snoozed.activeSnoozeUntilMillis, 3_000)
        XCTAssertNil(snoozed.fallbackAnchorMillis)
        XCTAssertEqual(snoozed.snapshotScheduledAtMillis(nowMillis: 2_000), 3_000)
    }

    func testAddingActiveSnoozeCanReplaceFallbackAnchor() {
        let schedule = makeData(
            id: 42,
            scheduledAt: 1_000,
            recurrenceWeekdays: [1, 3, 5],
            fallbackAnchorMillis: 1_500
        )

        let snoozed = schedule.withActiveSnooze(
            untilMillis: 3_000,
            fallbackAnchorMillis: 3_000
        )

        XCTAssertEqual(snoozed.activeSnoozeUntilMillis, 3_000)
        XCTAssertEqual(snoozed.fallbackAnchorMillis, 3_000)
    }

    func testClearingFallbackAnchorPreservesRecurringSchedule() {
        let schedule = makeData(
            id: 42,
            scheduledAt: 1_000,
            recurrenceWeekdays: [1, 3, 5],
            fallbackAnchorMillis: 1_500
        )

        let cleared = schedule.clearingFallbackAnchor()

        XCTAssertEqual(cleared.id, 42)
        XCTAssertEqual(cleared.scheduledAtMillis, 1_000)
        XCTAssertEqual(cleared.recurrenceWeekdays, [1, 3, 5])
        XCTAssertNil(cleared.fallbackAnchorMillis)
    }

    func testClearingActiveSnoozeRemovesDeadlineAndFallbackAnchor() {
        let schedule = makeData(
            id: 42,
            scheduledAt: 1_000,
            recurrenceWeekdays: [1, 3, 5],
            fallbackAnchorMillis: 1_500
        ).withActiveSnooze(
            untilMillis: 3_000,
            fallbackAnchorMillis: 3_000
        )

        let cleared = schedule.clearingActiveSnooze()

        XCTAssertEqual(cleared.recurrenceWeekdays, [1, 3, 5])
        XCTAssertNil(cleared.activeSnoozeUntilMillis)
        XCTAssertNil(cleared.fallbackAnchorMillis)
    }

    func testExpiredActiveSnoozeDoesNotHideRecurringScheduleTime() {
        let calendar = utcCalendar()
        let schedule = makeData(
            id: 42,
            scheduledAt: millis(2026, 1, 5, 9, 0, calendar: calendar),
            recurrenceWeekdays: [1]
        )

        let snoozed = schedule.withActiveSnooze(
            untilMillis: millis(2026, 1, 5, 9, 30, calendar: calendar))

        XCTAssertEqual(
            snoozed.snapshotScheduledAtMillis(
                nowMillis: millis(2026, 1, 5, 10, 0, calendar: calendar),
                calendar: calendar
            ),
            millis(2026, 1, 12, 9, 0, calendar: calendar)
        )
    }

    func testRecurringSnapshotAdvancesPastOriginalSchedule() {
        let calendar = utcCalendar()
        let schedule = makeData(
            id: 42,
            scheduledAt: millis(2026, 1, 5, 9, 0, calendar: calendar),
            recurrenceWeekdays: [1]
        )

        let snapshotAt = schedule.snapshotScheduledAtMillis(
            nowMillis: millis(2026, 1, 5, 10, 0, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(snapshotAt, millis(2026, 1, 12, 9, 0, calendar: calendar))
    }

    func testFromWireCapturesRecurringWallTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduledAtMillis = millis(2030, 3, 11, 7, 30, calendar: calendar)
        let wire = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: scheduledAtMillis,
            notification: WarmAlarmNotificationWire(
                title: "Wake up", body: "Alarm", keepNotificationAfterAlarmEnds: false),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            recurrence: WarmAlarmRecurrenceWire(weekdays: [1])
        )

        let schedule = WarmAlarmScheduleData.from(wire: wire, calendar: calendar)

        XCTAssertEqual(schedule.recurrenceHour, 7)
        XCTAssertEqual(schedule.recurrenceMinute, 30)
    }

    func testRecurringSnapshotPreservesWallTimeAfterTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let wire = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar),
            notification: WarmAlarmNotificationWire(
                title: "Wake up", body: "Alarm", keepNotificationAfterAlarmEnds: false),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            recurrence: WarmAlarmRecurrenceWire(weekdays: [1])
        )
        let schedule = WarmAlarmScheduleData.from(wire: wire, calendar: schedulingCalendar)
        var snapshotCalendar = Calendar(identifier: .gregorian)
        snapshotCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let snapshotAtMillis = schedule.snapshotScheduledAtMillis(
            nowMillis: millis(2030, 3, 11, 6, 0, calendar: snapshotCalendar),
            calendar: snapshotCalendar
        )

        XCTAssertEqual(snapshotAtMillis, millis(2030, 3, 11, 7, 0, calendar: snapshotCalendar))
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func millis(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Int64 {
        let date = calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))!
        return Int64(date.timeIntervalSince1970 * 1_000)
    }

    private func makeData(
        id: Int64,
        title: String = "Alarm",
        scheduledAt: Int64 = 0,
        recurrenceWeekdays: [Int64]? = nil,
        recurrenceHour: Int? = nil,
        recurrenceMinute: Int? = nil,
        fallbackAnchorMillis: Int64? = nil
    ) -> WarmAlarmScheduleData {
        WarmAlarmScheduleData(
            id: id, scheduledAtMillis: scheduledAt,
            oneShotOccurrenceEpochMillis: scheduledAt,
            occurrenceSeriesToken: "warm-alarm-v1:\(id)",
            notificationTitle: title, notificationBody: "",
            stopActionTitle: nil, snoozeActionTitle: nil,
            filePath: nil, assetPath: nil,
            loop: true, volume: nil, vibrate: false,
            fadeInDurationMillis: nil, recurrenceWeekdays: recurrenceWeekdays,
            recurrenceHour: recurrenceHour, recurrenceMinute: recurrenceMinute,
            snoozeDurationMillis: nil, payload: nil,
            volumeEnforced: nil, fadeSteps: nil,
            keepNotificationAfterAlarmEnds: nil,
            activeSnoozeUntilMillis: nil,
            fallbackAnchorMillis: fallbackAnchorMillis,
            alarmKitManaged: false,
            alarmKitSnoozeObserved: false
        )
    }
}
