import XCTest

@testable import warm_alarm_macos

final class WarmAlarmRequestRegistrationTests: XCTestCase {
    func testAddsEveryRecurringIdentifierBeforeCompleting() {
        let completed = expectation(description: "registration completes")
        var added = [String]()

        WarmAlarmRequestRegistration.addAtomically(
            ["42#1", "42#3"],
            identifier: { $0 },
            add: { identifier, completion in
                added.append(identifier)
                completion(nil)
            },
            rollback: { _ in
                XCTFail("Successful registration must not roll back requests")
            },
            completion: { error in
                XCTAssertNil(error)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(added, ["42#1", "42#3"])
    }

    func testRollsBackEveryRecurringIdentifierWhenFirstRequestFails() {
        let completed = expectation(description: "registration fails")
        let expectedError = NSError(domain: "WarmAlarmTests", code: 1)
        var rolledBack = [String]()

        WarmAlarmRequestRegistration.addAtomically(
            ["42#1", "42#3"],
            identifier: { $0 },
            add: { _, completion in
                completion(expectedError)
            },
            rollback: { identifiers in
                rolledBack = identifiers
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, expectedError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(rolledBack, ["42#1", "42#3"])
    }

    func testRollsBackEveryRecurringIdentifierWhenLaterRequestFails() {
        let completed = expectation(description: "registration fails")
        let expectedError = NSError(domain: "WarmAlarmTests", code: 2)
        var added = [String]()
        var rolledBack = [String]()

        WarmAlarmRequestRegistration.addAtomically(
            ["42#1", "42#3"],
            identifier: { $0 },
            add: { identifier, completion in
                added.append(identifier)
                completion(identifier == "42#3" ? expectedError : nil)
            },
            rollback: { identifiers in
                rolledBack = identifiers
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, expectedError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(added, ["42#1", "42#3"])
        XCTAssertEqual(rolledBack, ["42#1", "42#3"])
    }
}
