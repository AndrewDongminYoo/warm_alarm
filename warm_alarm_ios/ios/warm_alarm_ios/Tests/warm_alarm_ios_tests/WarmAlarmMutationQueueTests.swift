import XCTest

@testable import warm_alarm_ios

final class WarmAlarmMutationQueueTests: XCTestCase {
    func testRunsPlatformMutationOnMainThread() {
        let completed = expectation(description: "platform mutation completes")
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.platform_mutation")

        mutationQueue.enqueueOnMain { finish in
            XCTAssertTrue(Thread.isMainThread)
            completed.fulfill()
            finish()
        }

        wait(for: [completed], timeout: 1)
    }

    func testDefersNotificationActionUntilRegistrationFinishes() {
        let registrationStarted = expectation(description: "registration starts")
        let cancellationStartedEarly = expectation(description: "cancellation does not start early")
        cancellationStartedEarly.isInverted = true
        let cancellationFinished = expectation(description: "cancellation finishes")
        let lock = NSLock()
        var finishRegistration: (() -> Void)?
        var registrationFinished = false
        var cancellationStartedBeforeRegistrationFinished = false
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.mutation")

        mutationQueue.enqueue { finish in
            lock.lock()
            finishRegistration = finish
            lock.unlock()
            registrationStarted.fulfill()
        }
        wait(for: [registrationStarted], timeout: 1)

        mutationQueue.enqueue { finish in
            lock.lock()
            cancellationStartedBeforeRegistrationFinished = !registrationFinished
            let startedEarly = cancellationStartedBeforeRegistrationFinished
            lock.unlock()
            if startedEarly {
                cancellationStartedEarly.fulfill()
            }
            cancellationFinished.fulfill()
            finish()
        }

        wait(for: [cancellationStartedEarly], timeout: 0.1)
        lock.lock()
        registrationFinished = true
        let finish = finishRegistration
        lock.unlock()
        XCTAssertNotNil(finish)
        finish?()
        wait(for: [cancellationFinished], timeout: 1)
        XCTAssertFalse(cancellationStartedBeforeRegistrationFinished)
    }
}
