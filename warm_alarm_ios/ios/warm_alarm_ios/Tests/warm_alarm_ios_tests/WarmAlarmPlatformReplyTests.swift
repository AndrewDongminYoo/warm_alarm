import XCTest

@testable import warm_alarm_ios

final class WarmAlarmPlatformReplyTests: XCTestCase {
    func testCompletesOnMainThreadBeforeReleasingMutation() {
        let reply = expectation(description: "reply runs on the main thread")
        let mutationReleased = expectation(description: "mutation releases after the reply")
        let callbackQueue = DispatchQueue(label: "warm_alarm_tests.callback")

        callbackQueue.async {
            WarmAlarmPlatformReply.complete(
                .success(()) as Result<Void, Error>,
                completion: { result in
                    XCTAssertTrue(Thread.isMainThread)
                    if case let .failure(error) = result {
                        XCTFail("Unexpected reply failure: \(error)")
                    }
                    reply.fulfill()
                },
                finish: {
                    XCTAssertTrue(Thread.isMainThread)
                    mutationReleased.fulfill()
                }
            )
        }

        wait(for: [reply, mutationReleased], timeout: 1, enforceOrder: true)
    }

    func testPendingLimitFailureEmitsAndCompletesOnMainThread() {
        let event = expectation(description: "failure event runs on the main thread")
        let reply = expectation(description: "failure reply runs on the main thread")
        let mutationReleased = expectation(description: "mutation releases after the reply")
        let callbackQueue = DispatchQueue(label: "warm_alarm_tests.capacity_failure")

        callbackQueue.async {
            WarmAlarmPlugin.completePendingLimitFailure(
                alarmId: 42,
                error: NSError(domain: "WarmAlarmTests", code: 64),
                emitFailure: { alarmId, _ in
                    XCTAssertEqual(alarmId, 42)
                    XCTAssertTrue(Thread.isMainThread)
                    event.fulfill()
                },
                completion: { result in
                    XCTAssertTrue(Thread.isMainThread)
                    if case .success = result {
                        XCTFail("Pending-limit failure must not succeed")
                    }
                    reply.fulfill()
                },
                finish: {
                    XCTAssertTrue(Thread.isMainThread)
                    mutationReleased.fulfill()
                }
            )
        }

        wait(for: [event, reply, mutationReleased], timeout: 1, enforceOrder: true)
    }
}
