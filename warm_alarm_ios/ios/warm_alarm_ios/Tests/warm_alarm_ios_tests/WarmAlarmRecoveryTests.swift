import XCTest

@testable import warm_alarm_ios

final class WarmAlarmRecoveryTests: XCTestCase {
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
