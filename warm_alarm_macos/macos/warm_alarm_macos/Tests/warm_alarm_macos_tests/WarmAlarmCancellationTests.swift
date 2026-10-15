import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmCancellationTests: XCTestCase {
    func testCancelAllPreservesHostNotificationsAndRemovesOwnedOrphans() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let delegate = makeDelegate()
        let schedule = makeSchedule()
        let content = delegate.makeContent(from: schedule)
        var pending = ["7760001", "7760001#1", "7760001#5", "orphan-alarm"].map {
            UNNotificationRequest(identifier: $0, content: content, trigger: nil)
        }
        let hostIDs = ["host-reminder", "42", "warm_alarm_host_notice", "warm_alarm_kill_warning_notif-copy"]
        let hostContent = UNMutableNotificationContent()
        hostContent.categoryIdentifier = "HOST_NOTIFICATION"
        hostContent.userInfo = ["alarmId": "7760001"]
        pending += hostIDs.map { UNNotificationRequest(identifier: $0, content: hostContent, trigger: nil) }
        pending.append(UNNotificationRequest(
            identifier: "warm_alarm_kill_warning_notif", content: UNMutableNotificationContent(), trigger: nil
        ))
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            pendingNotificationReader: { $0(pending) },
            pendingNotificationRemover: { identifiers in pending.removeAll { identifiers.contains($0.identifier) } }
        )
        let completed = expectation(description: "scoped cancellation completes")

        plugin.cancelAllAlarms { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            XCTAssertTrue(Thread.isMainThread)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(Set(pending.map(\.identifier)), Set(hostIDs))
        XCTAssertTrue(WarmAlarmStore.shared.loadAll().isEmpty)
        withExtendedLifetime(plugin) {}
    }

    func testCancelAllSuppressesForegroundDeliveryWhileWaitingForPendingRead() throws {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let schedule = makeSchedule()
        WarmAlarmStore.shared.save(schedule)
        let delegate = makeDelegate()
        let content = delegate.makeContent(from: schedule)
        let readStarted = expectation(description: "pending read starts")
        let secondRead = expectation(description: "later cancellation must wait")
        secondRead.isInverted = true
        var didReleaseRead = false
        var readCompletion: (([UNNotificationRequest]) -> Void)?
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            pendingNotificationReader: { completion in
                if readCompletion == nil {
                    readCompletion = completion
                    readStarted.fulfill()
                } else {
                    if !didReleaseRead { secondRead.fulfill() }
                    completion([])
                }
            },
            pendingNotificationRemover: { _ in }
        )
        var didComplete = false
        let completed = expectation(description: "cancellation completes after read")
        plugin.cancelAllAlarms { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            didComplete = true
            completed.fulfill()
        }
        wait(for: [readStarted], timeout: 2)
        let secondCompleted = expectation(description: "later cancellation completes")
        plugin.cancelAllAlarms { _ in secondCompleted.fulfill() }
        wait(for: [secondRead], timeout: 0.05)

        XCTAssertFalse(didComplete)
        XCTAssertNil(WarmAlarmStore.shared.load(id: schedule.id))
        XCTAssertTrue(delegate.handleForegroundDelivery(content: content).isEmpty)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        didReleaseRead = true
        try XCTUnwrap(readCompletion)([])

        wait(for: [completed, secondCompleted], timeout: 2)
        XCTAssertTrue(WarmAlarmStore.shared.loadAll().isEmpty)
        withExtendedLifetime(plugin) {}
    }

    private func makeDelegate() -> WarmAlarmDelegate {
        WarmAlarmDelegate(eventsApi: WarmAlarmEventsApi(binaryMessenger: CancellationTestMessenger()))
    }

    private func makeSchedule() -> WarmAlarmScheduleData {
        .from(wire: WarmAlarmScheduleWire(
            id: 7_760_001,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Cancellation", body: "Alarm", keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: false, vibrate: false, volumeEnforced: false)
        ))
    }
}

private final class CancellationTestMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
