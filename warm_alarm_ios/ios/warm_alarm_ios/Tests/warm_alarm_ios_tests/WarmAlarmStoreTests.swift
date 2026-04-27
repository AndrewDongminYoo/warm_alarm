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
            notificationTitle: "T", notificationBody: "B",
            stopActionTitle: "Stop", snoozeActionTitle: "Snooze",
            filePath: "/tmp/alarm.mp3", assetPath: nil,
            loop: false, snoozeDurationMillis: 300_000
        )
        WarmAlarmStore.shared.save(data)
        let loaded = WarmAlarmStore.shared.load(id: 99)!
        XCTAssertEqual(loaded.stopActionTitle, "Stop")
        XCTAssertEqual(loaded.snoozeActionTitle, "Snooze")
        XCTAssertEqual(loaded.filePath, "/tmp/alarm.mp3")
        XCTAssertNil(loaded.assetPath)
        XCTAssertFalse(loaded.loop)
        XCTAssertEqual(loaded.snoozeDurationMillis, 300_000)
    }

    private func makeData(id: Int64, title: String = "Alarm", scheduledAt: Int64 = 0) -> WarmAlarmScheduleData {
        WarmAlarmScheduleData(
            id: id, scheduledAtMillis: scheduledAt,
            notificationTitle: title, notificationBody: "",
            stopActionTitle: nil, snoozeActionTitle: nil,
            filePath: nil, assetPath: nil,
            loop: true, snoozeDurationMillis: nil
        )
    }
}
