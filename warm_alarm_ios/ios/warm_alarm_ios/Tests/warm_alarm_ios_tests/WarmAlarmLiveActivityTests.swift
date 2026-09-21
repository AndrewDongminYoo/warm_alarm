import XCTest

@testable import warm_alarm_ios

final class WarmAlarmLiveActivityTests: XCTestCase {
    func testCapabilityIsUnsupportedWithoutHostConfiguration() {
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: true)
        let controller = WarmAlarmLiveActivityController(
            runtimeAvailable: true,
            supportsLiveActivities: false,
            liveActivityEnabled: true,
            adapterProvider: { adapter }
        )

        XCTAssertEqual(controller.capability, .unsupported)
    }

    func testUnavailableRuntimeDoesNotCallTheAdapter() {
        let completed = expectation(description: "Unavailable runtime completes")
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: true)
        let controller = WarmAlarmLiveActivityController(
            runtimeAvailable: false,
            supportsLiveActivities: true,
            liveActivityEnabled: true,
            adapterProvider: { adapter }
        )

        XCTAssertEqual(controller.capability, .unsupported)
        controller.start(state: makeState()) { result in
            XCTAssertEqual(try? result.get(), WarmAlarmLiveActivityOperationResult(status: .unsupported))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(adapter.startedStates.count, 0)
    }

    func testCapabilityReflectsAdapterRegistrationAndAuthorization() {
        XCTAssertEqual(
            makeController(adapter: nil).capability,
            .unsupported
        )
        XCTAssertEqual(
            makeController(adapter: RecordingLiveActivityAdapter(activitiesEnabled: false)).capability,
            .limited
        )
        XCTAssertEqual(
            makeController(adapter: RecordingLiveActivityAdapter(activitiesEnabled: true)).capability,
            .supported
        )
    }

    func testStartReturnsUnsupportedWithoutARegisteredAdapter() {
        let completed = expectation(description: "Unsupported start completes")

        makeController(adapter: nil).start(state: makeState()) { result in
            XCTAssertEqual(try? result.get(), WarmAlarmLiveActivityOperationResult(status: .unsupported))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    func testStartReturnsDisabledWithoutCallingTheAdapter() {
        let completed = expectation(description: "Disabled start completes")
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: false)

        makeController(adapter: adapter).start(state: makeState()) { result in
            XCTAssertEqual(try? result.get(), WarmAlarmLiveActivityOperationResult(status: .disabled))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(adapter.startedStates.count, 0)
    }

    func testStartReturnsTheAdapterActivityIdentifier() {
        let completed = expectation(description: "Start completes")
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: true)
        let state = makeState()

        makeController(adapter: adapter).start(state: state) { result in
            XCTAssertEqual(
                try? result.get(),
                WarmAlarmLiveActivityOperationResult(status: .completed, activityId: "activity-1")
            )
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(adapter.startedStates, [state])
    }

    func testUpdateMapsARecoveredActivityToCompleted() {
        let completed = expectation(description: "Update completes")
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: true)
        let state = makeState(status: .ringing, scheduledAt: nil)

        makeController(adapter: adapter).update(activityId: "activity-1", state: state) { result in
            XCTAssertEqual(try? result.get(), WarmAlarmLiveActivityOperationResult(status: .completed))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(adapter.updatedActivityIDs, ["activity-1"])
        XCTAssertEqual(adapter.updatedStates, [state])
    }

    func testUpdateMapsAMissingActivityToNotFound() {
        let completed = expectation(description: "Missing update completes")
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: true, updateResult: .success(false))

        makeController(adapter: adapter).update(activityId: "missing", state: makeState()) { result in
            XCTAssertEqual(try? result.get(), WarmAlarmLiveActivityOperationResult(status: .notFound))
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    func testEndMapsRecoveredAndMissingActivities() {
        let completed = expectation(description: "Recovered end completes")
        let missing = expectation(description: "Missing end completes")
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: true)
        let missingAdapter = RecordingLiveActivityAdapter(activitiesEnabled: true, endResult: .success(false))

        makeController(adapter: adapter).end(activityId: "activity-1") { result in
            XCTAssertEqual(try? result.get(), WarmAlarmLiveActivityOperationResult(status: .completed))
            completed.fulfill()
        }
        makeController(adapter: missingAdapter).end(activityId: "missing") { result in
            XCTAssertEqual(try? result.get(), WarmAlarmLiveActivityOperationResult(status: .notFound))
            missing.fulfill()
        }

        wait(for: [completed, missing], timeout: 1)
        XCTAssertEqual(adapter.endedActivityIDs, ["activity-1"])
        XCTAssertEqual(missingAdapter.endedActivityIDs, ["missing"])
    }

    func testAdapterFailureIsReturnedToTheCaller() {
        let completed = expectation(description: "Adapter failure completes")
        let expectedError = NSError(domain: "LiveActivityTests", code: 42)
        let adapter = RecordingLiveActivityAdapter(activitiesEnabled: true, startResult: .failure(expectedError))

        makeController(adapter: adapter).start(state: makeState()) { result in
            switch result {
            case .success:
                XCTFail("An adapter failure must not report success")
            case let .failure(error):
                XCTAssertEqual((error as NSError).domain, expectedError.domain)
                XCTAssertEqual((error as NSError).code, expectedError.code)
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
    }

    private func makeController(
        adapter: RecordingLiveActivityAdapter?,
        supportsLiveActivities: Bool = true,
        liveActivityEnabled: Bool = true
    ) -> WarmAlarmLiveActivityController {
        WarmAlarmLiveActivityController(
            runtimeAvailable: true,
            supportsLiveActivities: supportsLiveActivities,
            liveActivityEnabled: liveActivityEnabled,
            adapterProvider: { adapter }
        )
    }

    private func makeState(
        status: WarmAlarmLiveActivityDisplayStatus = .scheduled,
        scheduledAt: Date? = Date(timeIntervalSince1970: 1_900_000_000)
    ) -> WarmAlarmLiveActivityState {
        WarmAlarmLiveActivityState(
            alarmId: 42,
            title: "Wake up",
            status: status,
            scheduledAt: scheduledAt
        )
    }
}

private final class RecordingLiveActivityAdapter: WarmAlarmLiveActivityAdapter {
    let activitiesEnabled: Bool
    private let startResult: Result<String, Error>
    private let updateResult: Result<Bool, Error>
    private let endResult: Result<Bool, Error>
    private(set) var startedStates = [WarmAlarmLiveActivityState]()
    private(set) var updatedActivityIDs = [String]()
    private(set) var updatedStates = [WarmAlarmLiveActivityState]()
    private(set) var endedActivityIDs = [String]()

    init(
        activitiesEnabled: Bool,
        startResult: Result<String, Error> = .success("activity-1"),
        updateResult: Result<Bool, Error> = .success(true),
        endResult: Result<Bool, Error> = .success(true)
    ) {
        self.activitiesEnabled = activitiesEnabled
        self.startResult = startResult
        self.updateResult = updateResult
        self.endResult = endResult
    }

    func start(
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        startedStates.append(state)
        completion(startResult)
    }

    func update(
        activityId: String,
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        updatedActivityIDs.append(activityId)
        updatedStates.append(state)
        completion(updateResult)
    }

    func end(
        activityId: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        endedActivityIDs.append(activityId)
        completion(endResult)
    }
}
