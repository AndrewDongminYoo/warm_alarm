import XCTest

@testable import warm_alarm_ios

final class WarmAlarmRecoveryTests: XCTestCase {
    func testPreparesEachAlarmImmediatelyBeforeRecovery() {
        let completed = expectation(description: "recovery completes")
        var prepared = [Int64]()
        var recovered = [Int64]()
        var firstCompletion: ((Error?) -> Void)?

        WarmAlarmRecovery.recoverAll(
            [Int64(42), 84],
            prepare: { alarmId in
                prepared.append(alarmId)
                return alarmId
            },
            recover: { alarmId, completion in
                recovered.append(alarmId)
                if alarmId == 42 {
                    firstCompletion = completion
                } else {
                    completion(nil)
                }
            },
            completion: { result in
                if case let .failure(error) = result {
                    XCTFail("Recovery failed: \(error)")
                }
                completed.fulfill()
            }
        )

        XCTAssertEqual(prepared, [Int64(42)])
        XCTAssertEqual(recovered, [Int64(42)])

        firstCompletion?(nil)

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(prepared, [Int64(42), 84])
        XCTAssertEqual(recovered, [Int64(42), 84])
    }

    func testContinuesRecoveringLaterAlarmsAfterOneFailure() {
        let completed = expectation(description: "recovery completes")
        let expectedError = NSError(domain: "WarmAlarmTests", code: 3)
        var recovered = [Int64]()

        WarmAlarmRecovery.recoverAll(
            [Int64(42), 84],
            recover: { alarmId, completion in
                recovered.append(alarmId)
                completion(alarmId == 42 ? expectedError : nil)
            },
            completion: { result in
                switch result {
                case let .failure(error):
                    XCTAssertEqual((error as NSError).domain, expectedError.domain)
                case .success:
                    XCTFail("Recovery must report the first error after processing every alarm")
                }
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(recovered, [Int64(42), 84])
    }
}
