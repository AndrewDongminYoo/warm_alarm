// cspell:words NSKeyedUnarchiver

import AVFAudio
import Flutter
import XCTest
import UserNotifications

@testable import warm_alarm_ios

final class WarmAlarmRequestRegistrationTests: XCTestCase {
    func testAlarmKitPlanPreservesTheRequestedRecordingForSystemPlayback() {
        let wire = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(title: "Wake up", body: "Voice", keepNotificationAfterAlarmEnds: false),
            audio: WarmAlarmAudioWire(filePath: "/recordings/message.m4a", loop: false, vibrate: true, volumeEnforced: false)
        )

        let plan = WarmAlarmAlarmKitPlan(schedule: WarmAlarmScheduleData.from(wire: wire))

        XCTAssertEqual(plan.soundFilePath, "/recordings/message.m4a")
        XCTAssertNil(plan.soundAssetPath)
    }

    func testAlarmKitMetadataUsesAHostIndependentType() {
        if #available(iOS 26.0, *) {
            let _: Never.Type = WarmAlarmAlarmKitMetadata.self
        }
    }

    func testAlarmKitBackendIsSelectedOnlyForConfiguredAvailableHosts() {
        XCTAssertEqual(
            WarmAlarmPlugin.schedulingBackend(
                alarmKitAvailable: true,
                alarmKitUsageDescription: "Wake up with your recorded message.",
                authorizationState: .authorized
            ),
            .alarmKit
        )
        XCTAssertEqual(
            WarmAlarmPlugin.schedulingBackend(
                alarmKitAvailable: true,
                alarmKitUsageDescription: "Wake up with your recorded message.",
                authorizationState: .notDetermined
            ),
            .alarmKit
        )
        XCTAssertEqual(
            WarmAlarmPlugin.schedulingBackend(
                alarmKitAvailable: true,
                alarmKitUsageDescription: "Wake up with your recorded message.",
                authorizationState: .denied
            ),
            .userNotifications
        )
        XCTAssertEqual(
            WarmAlarmPlugin.schedulingBackend(
                alarmKitAvailable: false,
                alarmKitUsageDescription: "Wake up with your recorded message.",
                authorizationState: .authorized
            ),
            .userNotifications
        )
        XCTAssertEqual(
            WarmAlarmPlugin.schedulingBackend(
                alarmKitAvailable: true,
                alarmKitUsageDescription: "   ",
                authorizationState: .authorized
            ),
            .userNotifications
        )
        XCTAssertEqual(
            WarmAlarmPlugin.schedulingBackend(
                alarmKitAvailable: true,
                alarmKitUsageDescription: nil,
                authorizationState: .authorized
            ),
            .userNotifications
        )
    }

    func testAuthorizedAlarmKitReportsExactReadyWithoutNotificationPermission() {
        let snapshot = WarmAlarmPlugin.permissionSnapshot(
            notificationsGranted: false,
            alarmKitConfigured: true,
            alarmKitAuthorization: .authorized
        )

        XCTAssertTrue(snapshot.permissionState.exactAlarmGranted)
        XCTAssertFalse(snapshot.permissionState.notificationsGranted)
        XCTAssertEqual(snapshot.readiness.level, .ready)
        XCTAssertEqual(snapshot.readiness.reasons, [])
    }

    func testNotificationFallbackReadinessUsesNotificationPermission() {
        for authorization in [WarmAlarmAlarmKitAuthorization.authorized, .notDetermined] {
            let blocked = WarmAlarmPlugin.permissionSnapshot(
                notificationsGranted: false, alarmKitConfigured: true,
                alarmKitAuthorization: authorization, effectiveBackend: .userNotifications
            )
            XCTAssertEqual(blocked.readiness.level, .blocked)
            XCTAssertEqual(blocked.readiness.reasons, [.notificationPermissionDenied, .backgroundExecutionLimited])

            let limited = WarmAlarmPlugin.permissionSnapshot(
                notificationsGranted: true, alarmKitConfigured: true,
                alarmKitAuthorization: authorization, effectiveBackend: .userNotifications
            )
            XCTAssertEqual(limited.readiness.level, .limited)
            XCTAssertEqual(limited.readiness.reasons, [.backgroundExecutionLimited])
        }
        let native = WarmAlarmPlugin.permissionSnapshot(
            notificationsGranted: false, alarmKitConfigured: true,
            alarmKitAuthorization: .authorized, effectiveBackend: .alarmKit
        )
        XCTAssertEqual(native.readiness.level, .ready)
    }

    func testDeniedAlarmKitFallsBackToLimitedNotifications() {
        let snapshot = WarmAlarmPlugin.permissionSnapshot(
            notificationsGranted: true,
            alarmKitConfigured: true,
            alarmKitAuthorization: .denied
        )

        XCTAssertFalse(snapshot.permissionState.exactAlarmGranted)
        XCTAssertEqual(snapshot.readiness.level, .limited)
        XCTAssertEqual(
            snapshot.readiness.reasons,
            [.exactAlarmPermissionDenied, .backgroundExecutionLimited]
        )
    }

    func testUnconfiguredHostKeepsLegacyNotificationReadiness() {
        let snapshot = WarmAlarmPlugin.permissionSnapshot(
            notificationsGranted: false,
            alarmKitConfigured: false,
            alarmKitAuthorization: nil
        )

        XCTAssertFalse(snapshot.permissionState.exactAlarmGranted)
        XCTAssertEqual(snapshot.readiness.level, .blocked)
        XCTAssertEqual(
            snapshot.readiness.reasons,
            [.notificationPermissionDenied, .backgroundExecutionLimited]
        )
    }

    func testPluginRegistrationInstallsForwardingNotificationCenterDelegate() {
        let engine = FlutterEngine(name: "warm_alarm_registration_test")
        XCTAssertTrue(engine.run())
        guard let registrar = engine.registrar(forPlugin: "WarmAlarmRegistrationTest") else {
            XCTFail("Expected FlutterEngine to provide a plugin registrar")
            return
        }
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let existingDelegate = ExistingNotificationCenterDelegate()
        center.delegate = existingDelegate
        defer { center.delegate = previousDelegate }

        WarmAlarmPlugin.register(with: registrar)

        let installedDelegate = center.delegate as? WarmAlarmNotificationCenterDelegate
        XCTAssertNotNil(installedDelegate)
        XCTAssertTrue(installedDelegate?.forwardingDelegate === existingDelegate)
    }

    func testPluginRegistrationFlattensAnExistingWarmAlarmDelegateChain() {
        let engine = FlutterEngine(name: "warm_alarm_second_registration_test")
        XCTAssertTrue(engine.run())
        guard let registrar = engine.registrar(forPlugin: "WarmAlarmSecondRegistrationTest") else {
            XCTFail("Expected FlutterEngine to provide a plugin registrar")
            return
        }
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let existingDelegate = ExistingNotificationCenterDelegate()
        let firstWarmAlarmDelegate = WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.first_registration")
        )
        let firstProxy = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: firstWarmAlarmDelegate,
            forwardingDelegate: existingDelegate
        )
        center.delegate = firstProxy
        defer { center.delegate = previousDelegate }

        WarmAlarmPlugin.register(with: registrar)

        let installedDelegate = center.delegate as? WarmAlarmNotificationCenterDelegate
        XCTAssertNotNil(installedDelegate)
        XCTAssertFalse(installedDelegate === firstProxy)
        XCTAssertTrue(installedDelegate?.forwardingDelegate === existingDelegate)
        XCTAssertTrue(installedDelegate?.restorationDelegate === firstProxy)
    }

    func testNotificationCenterDelegateRestoresNewestLiveProxyFromThreeRegistrations() {
        let existingDelegate = ExistingNotificationCenterDelegate()
        var firstProxy: WarmAlarmNotificationCenterDelegate? = makeNotificationCenterDelegate(
            forwardingDelegate: existingDelegate,
            label: "first"
        )
        var secondProxy: WarmAlarmNotificationCenterDelegate? = makeNotificationCenterDelegate(
            forwardingDelegate: existingDelegate,
            previousWarmAlarmDelegate: firstProxy,
            label: "second"
        )
        let thirdProxy = makeNotificationCenterDelegate(
            forwardingDelegate: existingDelegate,
            previousWarmAlarmDelegate: secondProxy,
            label: "third"
        )

        XCTAssertTrue(thirdProxy.restorationDelegate === secondProxy)
        weak let releasedSecondProxy = secondProxy
        secondProxy = nil
        XCTAssertNil(releasedSecondProxy)
        XCTAssertTrue(thirdProxy.restorationDelegate === firstProxy)
        weak let releasedFirstProxy = firstProxy
        firstProxy = nil
        XCTAssertNil(releasedFirstProxy)
        XCTAssertTrue(thirdProxy.restorationDelegate === existingDelegate)
    }

    func testNotificationCenterDelegateUninstallsInLastRegisteredFirstOrder() {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let existingDelegate = ExistingNotificationCenterDelegate()
        center.delegate = existingDelegate
        defer { center.delegate = previousDelegate }
        let firstProxy = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "lifo_first"),
            on: center
        )
        let secondProxy = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "lifo_second"),
            on: center
        )
        let thirdProxy = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "lifo_third"),
            on: center
        )

        XCTAssertTrue(center.delegate === thirdProxy)
        thirdProxy.uninstall(from: center)
        XCTAssertTrue(center.delegate === secondProxy)
        secondProxy.uninstall(from: center)
        XCTAssertTrue(center.delegate === firstProxy)
        firstProxy.uninstall(from: center)
        XCTAssertTrue(center.delegate === existingDelegate)
    }

    func testNotificationCenterDelegateDoesNotOverwriteAnExternalReplacement() {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let existingDelegate = ExistingNotificationCenterDelegate()
        let externalReplacement = ExistingNotificationCenterDelegate()
        center.delegate = existingDelegate
        defer { center.delegate = previousDelegate }
        let proxy = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "external_replacement"),
            on: center
        )

        center.delegate = externalReplacement
        proxy.uninstall(from: center)

        XCTAssertTrue(center.delegate === externalReplacement)
    }

    func testNotificationCenterDelegateDoesNotRetainOriginalDelegate() {
        var existingDelegate: ExistingNotificationCenterDelegate? = ExistingNotificationCenterDelegate()
        weak let releasedDelegate = existingDelegate
        let proxy = makeNotificationCenterDelegate(
            forwardingDelegate: existingDelegate,
            label: "weak_original"
        )

        existingDelegate = nil

        XCTAssertNil(releasedDelegate)
        XCTAssertNil(proxy.restorationDelegate)
    }

    func testNotificationCenterDelegateRoutesOnlyWarmAlarmContentToWarmAlarmDelegate() {
        let warmAlarmDelegate = WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.notification_routing")
        )
        let existingDelegate = ExistingNotificationCenterDelegate()
        let delegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: warmAlarmDelegate,
            forwardingDelegate: existingDelegate
        )
        let warmContent = UNMutableNotificationContent()
        warmContent.categoryIdentifier = WarmAlarmDelegate.categoryIdentifier
        let unrelatedContent = UNMutableNotificationContent()
        unrelatedContent.categoryIdentifier = "OTHER_ALARM"

        XCTAssertTrue(delegate.target(for: warmContent) === warmAlarmDelegate)
        XCTAssertTrue(delegate.target(for: unrelatedContent) === existingDelegate)
    }

    func testNotificationCenterDelegatePreservesFlutterLifeCycleProviderConformance() {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let flutterAppDelegate = FlutterAppDelegate()
        center.delegate = flutterAppDelegate
        defer { center.delegate = previousDelegate }

        let delegate = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "flutter_lifecycle_provider"),
            on: center
        )

        XCTAssertTrue(delegate is FlutterAppLifeCycleProvider)
        XCTAssertTrue(delegate.forwardingDelegate === flutterAppDelegate)
    }

    func testNotificationCenterDelegateDoesNotClaimFlutterLifeCycleForAnUnrelatedDelegate() {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let existingDelegate = ExistingNotificationCenterDelegate()
        center.delegate = existingDelegate
        defer { center.delegate = previousDelegate }

        let delegate = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "unrelated_delegate"),
            on: center
        )

        XCTAssertFalse(delegate is FlutterAppLifeCycleProvider)
        XCTAssertTrue(delegate.forwardingDelegate === existingDelegate)
    }

    func testNotificationCenterDelegatePreservesFlutterLifeCycleProviderAcrossRegistrations() {
        let center = UNUserNotificationCenter.current()
        let previousDelegate = center.delegate
        let flutterAppDelegate = FlutterAppDelegate()
        center.delegate = flutterAppDelegate
        defer { center.delegate = previousDelegate }

        let firstDelegate = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "first_flutter_lifecycle_provider"),
            on: center
        )
        let secondDelegate = WarmAlarmNotificationCenterDelegate.install(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: "second_flutter_lifecycle_provider"),
            on: center
        )

        XCTAssertTrue(firstDelegate is FlutterAppLifeCycleProvider)
        XCTAssertTrue(secondDelegate is FlutterAppLifeCycleProvider)
        XCTAssertTrue(secondDelegate.forwardingDelegate === flutterAppDelegate)
        XCTAssertTrue(secondDelegate.restorationDelegate === firstDelegate)
    }

    func testMalformedWarmAlarmResponseCompletesWithoutMutatingState() {
        let delegate = WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.malformed_response")
        )
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = WarmAlarmDelegate.categoryIdentifier
        var didComplete = false

        let handled = delegate.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            deliveredIdentifier: "malformed",
            content: content,
            deliveredAtMillis: 1_000,
            completionHandler: { didComplete = true }
        )

        XCTAssertTrue(handled)
        XCTAssertTrue(didComplete)
    }

    func testScheduledEventIsEmittedOnMainThread() {
        let emitted = expectation(description: "scheduled event emitted")
        var wasEmittedOnMainThread = false
        let eventsApi = RecordingWarmAlarmEventsApi { _ in
            wasEmittedOnMainThread = Thread.isMainThread
            emitted.fulfill()
        }
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.event_thread")
        )

        DispatchQueue.global().async {
            delegate.emitScheduled(alarmId: 42)
        }

        wait(for: [emitted], timeout: 1)
        XCTAssertTrue(wasEmittedOnMainThread)
    }

    private func makeWarmAlarmDelegate(label: String) -> WarmAlarmDelegate {
        WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.\(label)")
        )
    }

    private func makeNotificationCenterDelegate(
        forwardingDelegate: UNUserNotificationCenterDelegate?,
        previousWarmAlarmDelegate: WarmAlarmNotificationCenterDelegate? = nil,
        label: String
    ) -> WarmAlarmNotificationCenterDelegate {
        WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: makeWarmAlarmDelegate(label: label),
            forwardingDelegate: forwardingDelegate,
            previousWarmAlarmDelegate: previousWarmAlarmDelegate
        )
    }

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

    func testSubmitsEveryRequestBeforeWaitingForCallbacks() {
        var added = [String]()
        var callbacks = [(Error?) -> Void]()
        var didComplete = false

        WarmAlarmRequestRegistration.addAtomically(
            ["42", "42#fallback#1"],
            identifier: { $0 },
            add: { identifier, completion in
                added.append(identifier)
                callbacks.append(completion)
            },
            rollback: { _ in
                XCTFail("Successful registration must not roll back requests")
            },
            completion: { error in
                XCTAssertNil(error)
                didComplete = true
            }
        )

        XCTAssertEqual(added, ["42", "42#fallback#1"])
        guard callbacks.count == 2 else { return }
        XCTAssertFalse(didComplete)
        callbacks[0](nil)
        XCTAssertFalse(didComplete)
        callbacks[1](nil)
        XCTAssertTrue(didComplete)
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

final class WarmAlarmSnoozeRegistrationTests: XCTestCase {
    func testCompletesOnMainThreadWhenRegistrationFinishesInBackground() {
        let completed = expectation(description: "snooze registration completes")

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {},
            register: { completion in
                DispatchQueue.global().async {
                    completion(nil, false)
                }
            },
            rollback: { _, _ in
                XCTFail("A successful registration must not roll back the intent")
            },
            completion: { error in
                XCTAssertNil(error)
                XCTAssertTrue(Thread.isMainThread)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
    }

    func testPersistsIntentBeforeRegistrationStarts() {
        var steps = [String]()

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {
                steps.append("persist")
            },
            register: { _ in
                steps.append("register")
            },
            rollback: { _, _ in
                XCTFail("An unfinished registration must not roll back the intent")
            },
            completion: { _ in
                XCTFail("An unfinished registration must not complete")
            }
        )

        XCTAssertEqual(steps, ["persist", "register"])
    }

    func testRollsBackIntentWhenRegistrationReportsFailure() {
        let expectedError = NSError(domain: "WarmAlarmTests", code: 4)
        let completed = expectation(description: "snooze registration completes")
        var steps = [String]()

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {
                steps.append("persist")
            },
            register: { completion in
                steps.append("register")
                completion(expectedError, false)
            },
            rollback: { didSubmitRequests, rollbackCompletion in
                XCTAssertFalse(didSubmitRequests)
                steps.append("rollback")
                rollbackCompletion(nil)
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, expectedError.domain)
                steps.append("completion")
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(steps, ["persist", "register", "rollback", "completion"])
    }

    func testReportsRollbackFailure() {
        let registrationError = NSError(domain: "WarmAlarmRegistrationTests", code: 1)
        let rollbackError = NSError(domain: "WarmAlarmRollbackTests", code: 2)
        let completed = expectation(description: "snooze rollback failure completes")

        WarmAlarmSnoozeRegistration.perform(
            persistIntent: {},
            register: { completion in
                completion(registrationError, true)
            },
            rollback: { didSubmitRequests, completion in
                XCTAssertTrue(didSubmitRequests)
                completion(rollbackError)
            },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, rollbackError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
    }
}

final class WarmAlarmRequestTests: XCTestCase {
    func testSoundPreparationDoesNotWaitForNotificationMutationsAndRepliesOnMain() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let input = try makeSoundLifecycleRecording()
        defer { try? FileManager.default.removeItem(at: input) }
        let expired = try WarmAlarmSoundFiles.prepare(primary: input, background: nil)
        defer { WarmAlarmSoundFiles.remove(named: expired.lastPathComponent) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-25 * 60 * 60)], ofItemAtPath: expired.path
        )
        let queue = WarmAlarmMutationQueue(label: "warm_alarm_tests.background_preparation")
        let plugin = makeSoundLifecyclePlugin(backend: RecordingAlarmKitBackend(scheduleError: nil), mutationQueue: queue)
        let entered = expectation(description: "background mutation holds the queue")
        var release: (() -> Void)?
        queue.enqueue { finish in
            XCTAssertFalse(Thread.isMainThread)
            release = finish
            entered.fulfill()
        }
        wait(for: [entered], timeout: 10)
        let completed = expectation(description: "prepared sound reply reaches main")
        var didComplete = false

        plugin.prepareSystemSound(primaryFilePath: input.path, backgroundAssetPath: nil) { result in
            XCTAssertTrue(Thread.isMainThread)
            didComplete = true
            switch result {
            case let .success(path):
                XCTAssertNotNil(path)
                if let path { WarmAlarmSoundFiles.remove(named: URL(fileURLWithPath: path).lastPathComponent) }
            case let .failure(error): XCTFail("Preparation failed: \(error)")
            }
            completed.fulfill()
        }

        let waitResult = XCTWaiter.wait(for: [completed], timeout: 2)
        let completedBeforeRelease = didComplete
        release?()
        drainMutationQueue(queue)
        XCTAssertEqual(waitResult, .completed)
        XCTAssertTrue(completedBeforeRelease)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expired.path))
    }

    func testInitializationRemovesExpiredStagingSoundsOnlyAfterConfirmedRecovery() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        let input = try makeSoundLifecycleRecording()
        defer {
            try? FileManager.default.removeItem(at: input)
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let orphanID = WarmAlarmAlarmKitPlan.id(for: 4_242_424_274)
        for cancellationFails in [true, false] {
            WarmAlarmStore.shared.clear()
            let expired = try WarmAlarmSoundFiles.prepare(primary: input, background: nil)
            defer { WarmAlarmSoundFiles.remove(named: expired.lastPathComponent) }
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-25 * 60 * 60)], ofItemAtPath: expired.path
            )
            let backend = RecordingAlarmKitBackend(
                scheduleError: nil,
                cancelError: cancellationFails ? NSError(domain: "StagingRecovery", code: 1) : nil,
                snapshot: WarmAlarmAlarmKitSnapshot(states: [orphanID: .scheduled])
            )
            let plugin = makeSoundLifecyclePlugin(backend: backend)
            let completed = expectation(description: "initialization checks staging sounds after recovery")

            plugin.initialize { result in
                switch result {
                case .success: XCTAssertFalse(cancellationFails)
                case .failure: XCTAssertTrue(cancellationFails)
                }
                completed.fulfill()
            }

            wait(for: [completed], timeout: 10)
            XCTAssertEqual(backend.cancelledIDs, [orphanID])
            XCTAssertEqual(FileManager.default.fileExists(atPath: expired.path), cancellationFails)
            withExtendedLifetime(plugin) {}
        }
    }

    func testInitializationCleansAbandonedSoundBeforeFirstAlarmKitAuthorization() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        let input = try makeSoundLifecycleRecording()
        defer {
            try? FileManager.default.removeItem(at: input)
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let backend = RecordingAlarmKitBackend(scheduleError: nil, authorizationState: .notDetermined)
        let plugin = makeSoundLifecyclePlugin(backend: backend)
        let prepared = expectation(description: "sound preparation before authorization completes")
        var output: String?
        plugin.prepareSystemSound(primaryFilePath: input.path, backgroundAssetPath: nil) { result in
            switch result {
            case let .success(path): output = path
            case let .failure(error): XCTFail("Preparation failed: \(error)")
            }
            prepared.fulfill()
        }
        wait(for: [prepared], timeout: 10)
        let outputPath = try XCTUnwrap(output)
        defer { WarmAlarmSoundFiles.remove(named: URL(fileURLWithPath: outputPath).lastPathComponent) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-25 * 60 * 60)], ofItemAtPath: outputPath
        )
        XCTAssertTrue(WarmAlarmStore.shared.loadAll().isEmpty)
        let initialized = expectation(description: "empty initialization cleans abandoned sound")

        plugin.initialize { result in
            if case let .failure(error) = result { XCTFail("Initialization failed: \(error)") }
            initialized.fulfill()
        }

        wait(for: [initialized], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
        XCTAssertTrue(backend.scheduledPlans.isEmpty)
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
        XCTAssertEqual(backend.cancelAllCount, 0)
        withExtendedLifetime(plugin) {}
    }

    func testDeniedInitializationPreservesOldSoundWhenTheStoreHasLostANativeAlarm() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let previousRecords = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        let input = try makeSoundLifecycleRecording()
        let output = try WarmAlarmSoundFiles.prepare(primary: input, background: nil)
        defer {
            try? FileManager.default.removeItem(at: input)
            WarmAlarmSoundFiles.remove(named: output.lastPathComponent)
            WarmAlarmStore.shared.clear()
            previousRecords.forEach { WarmAlarmStore.shared.save($0) }
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-25 * 60 * 60)], ofItemAtPath: output.path
        )
        let orphanID = WarmAlarmAlarmKitPlan.id(for: 4_242_424_278)
        let backend = RecordingAlarmKitBackend(
            scheduleError: nil, authorizationState: .denied,
            snapshot: WarmAlarmAlarmKitSnapshot(states: [orphanID: .scheduled])
        )
        let plugin = makeSoundLifecyclePlugin(backend: backend)
        let completed = expectation(description: "denied initialization preserves an unverified native sound")
        plugin.initialize { result in
            if case let .failure(error) = result { XCTFail("Initialization failed: \(error)") }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 10)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: output.path),
            "Denied authorization does not prove that native references are gone"
        )
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
        XCTAssertEqual(backend.cancelAllCount, 0)
        withExtendedLifetime(plugin) {}
    }

    func testInitializationCancelsOnlyOwnedOrphansWithEmptyOrMixedStore() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let known = WarmAlarmScheduleData.from(wire: makeWireSchedule(id: 4_242_424_270, scheduledAtMillis: 1_900_000_000_000))
        let knownID = WarmAlarmAlarmKitPlan.id(for: known.id)
        let orphanID = WarmAlarmAlarmKitPlan.id(for: 4_242_424_271)
        let foreignID = UUID(uuidString: "00000000-0000-0000-0000-00000000002A")!
        for hasKnownSchedule in [false, true] {
            WarmAlarmStore.shared.clear()
            if hasKnownSchedule { WarmAlarmStore.shared.save(known) }
            var states: [UUID: WarmAlarmAlarmKitState] = [orphanID: .scheduled, foreignID: .scheduled]
            if hasKnownSchedule { states[knownID] = .scheduled }
            let backend = RecordingAlarmKitBackend(scheduleError: nil, snapshot: WarmAlarmAlarmKitSnapshot(states: states))
            let plugin = makeSoundLifecyclePlugin(backend: backend)
            let completed = expectation(description: "orphan recovery completes")

            plugin.initialize { result in
                if case let .failure(error) = result { XCTFail("Initialization failed: \(error)") }
                completed.fulfill()
            }

            wait(for: [completed], timeout: 10)
            XCTAssertEqual(backend.cancelledIDs, [orphanID])
            XCTAssertTrue(backend.scheduledPlans.isEmpty)
            if hasKnownSchedule { XCTAssertEqual(WarmAlarmStore.shared.load(id: known.id)?.alarmKitManaged, true) }
            withExtendedLifetime(plugin) {}
        }
    }

    func testInitializationPreservesLocalStateWhenOrphanCancellationFails() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let known = WarmAlarmScheduleData.from(wire: makeWireSchedule(id: 4_242_424_272, scheduledAtMillis: 1_900_000_000_000))
        WarmAlarmStore.shared.save(known)
        let failure = NSError(domain: "OrphanCancellation", code: 1)
        let orphanID = WarmAlarmAlarmKitPlan.id(for: 4_242_424_273)
        let backend = RecordingAlarmKitBackend(
            scheduleError: nil, cancelError: failure,
            snapshot: WarmAlarmAlarmKitSnapshot(states: [WarmAlarmAlarmKitPlan.id(for: known.id): .scheduled, orphanID: .scheduled])
        )
        let plugin = makeSoundLifecyclePlugin(backend: backend)
        let completed = expectation(description: "orphan cancellation failure returns")

        plugin.initialize { result in
            switch result {
            case .success: XCTFail("Unconfirmed orphan cancellation must fail initialization")
            case let .failure(error): XCTAssertEqual((error as NSError).domain, failure.domain)
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 10)
        XCTAssertEqual(backend.cancelledIDs, [orphanID])
        XCTAssertEqual(WarmAlarmStore.shared.load(id: known.id)?.alarmKitManaged, false)
        XCTAssertTrue(backend.scheduledPlans.isEmpty)
    }

    func testInitializationCleansOwnedAlarmsAfterHostOptInIsRemoved() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = makeSoundLifecyclePlugin(backend: backend, usageDescription: nil)
        let completed = expectation(description: "disabled host cleanup completes")

        plugin.initialize { result in
            if case let .failure(error) = result { XCTFail("Initialization failed: \(error)") }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 10)
        XCTAssertEqual(backend.cancelAllCount, 1)
        XCTAssertTrue(backend.scheduledPlans.isEmpty)
    }

    func testCancelAllCleansAuthorizedOrphansWithoutRequiringLocalRecords() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        for authorization in [WarmAlarmAlarmKitAuthorization.authorized, .notDetermined, .denied] {
            let backend = RecordingAlarmKitBackend(scheduleError: nil, authorizationState: authorization)
            let plugin = makeSoundLifecyclePlugin(backend: backend, usageDescription: nil)
            let completed = expectation(description: "empty-store cancel all completes")

            plugin.cancelAllAlarms { result in
                if case let .failure(error) = result { XCTFail("Cancel all failed: \(error)") }
                completed.fulfill()
            }

            wait(for: [completed], timeout: 10)
            XCTAssertEqual(backend.cancelAllCount, authorization == .authorized ? 1 : 0)
            withExtendedLifetime(plugin) {}
        }
    }

    func testAlarmKitStoreUpdatesWaitForTheActiveMutation() {
        let alarmID: Int64 = 4_242_424_274
        let schedule = WarmAlarmScheduleData.from(wire: makeWireSchedule(id: alarmID, scheduledAtMillis: 1_900_000_000_000))
            .withAlarmKitManaged(true)
        WarmAlarmStore.shared.save(schedule)
        defer { WarmAlarmStore.shared.remove(id: alarmID) }
        let queue = WarmAlarmMutationQueue(label: "warm_alarm_tests.observer_serialization")
        let events = RecordingWarmAlarmEventsApi()
        let delegate = WarmAlarmDelegate(eventsApi: events, notificationMutationQueue: queue)
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate, notificationMutationQueue: queue,
            notificationCenter: UNUserNotificationCenter.current(),
            notificationCenterDelegate: WarmAlarmNotificationCenterDelegate(warmAlarmDelegate: delegate, forwardingDelegate: nil),
            alarmKitBackend: backend, alarmKitUsageDescription: "Wake up", alarmKitLiveActivityEnabled: true
        )
        let entered = expectation(description: "mutation holds the queue")
        var release: (() -> Void)?
        queue.enqueue { finish in
            release = finish
            entered.fulfill()
        }
        wait(for: [entered], timeout: 10)

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [WarmAlarmAlarmKitPlan.id(for: alarmID): .paused]))

        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmID)?.alarmKitSnoozeObserved, false)
        XCTAssertTrue(events.events.isEmpty)
        WarmAlarmStore.shared.save(schedule.withAlarmKitManaged(false))
        release?()
        drainMutationQueue(queue)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmID)?.alarmKitManaged, false)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmID)?.alarmKitSnoozeObserved, false)
        XCTAssertTrue(events.events.isEmpty)
        withExtendedLifetime(plugin) {}
    }

    private func drainMutationQueue(_ queue: WarmAlarmMutationQueue) {
        let drained = expectation(description: "queued observation completes")
        queue.enqueue { finish in
            drained.fulfill()
            finish()
        }
        wait(for: [drained], timeout: 10)
    }

    func testDelayedNativeRemovalDoesNotStopCancelledOrReplacedSchedules() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        let alarmID: Int64 = 4_242_424_275
        let nativeID = WarmAlarmAlarmKitPlan.id(for: alarmID)
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: WarmAlarmPlugin.requestIdentifiers(for: alarmID, recurrenceWeekdays: nil)
            )
        }
        for operation in ["cancel", "cancelAll", "replace"] {
            WarmAlarmStore.shared.clear()
            WarmAlarmStore.shared.save(WarmAlarmScheduleData.from(
                wire: makeWireSchedule(id: alarmID, scheduledAtMillis: 1_900_000_000_000)
            ).withAlarmKitManaged(true))
            let queue = WarmAlarmMutationQueue(label: "warm_alarm_tests.delayed_removal")
            let events = RecordingWarmAlarmEventsApi()
            let delegate = WarmAlarmDelegate(eventsApi: events, notificationMutationQueue: queue)
            let backend = RecordingAlarmKitBackend(scheduleError: nil)
            let plugin = WarmAlarmPlugin(
                delegate: delegate, notificationMutationQueue: queue,
                notificationCenter: UNUserNotificationCenter.current(),
                notificationCenterDelegate: WarmAlarmNotificationCenterDelegate(warmAlarmDelegate: delegate, forwardingDelegate: nil),
                alarmKitBackend: backend, alarmKitUsageDescription: "Wake up", alarmKitLiveActivityEnabled: true
            )
            backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [nativeID: .alerting]))
            drainMutationQueue(queue)
            XCTAssertEqual(events.events.map(\.type), [.fired])
            let completed = expectation(description: "local mutation completes before native removal")
            let completion: (Result<Void, Error>) -> Void = { result in
                if case let .failure(error) = result { XCTFail("Mutation failed: \(error)") }
                completed.fulfill()
            }
            switch operation {
            case "cancel": plugin.cancelAlarm(id: alarmID, completion: completion)
            case "cancelAll": plugin.cancelAllAlarms(completion: completion)
            default:
                backend.authorizationState = .denied
                plugin.scheduleAlarm(schedule: makeWireSchedule(id: alarmID, scheduledAtMillis: 1_900_000_600_000)) {
                    completion($0.map { _ in () })
                }
            }
            wait(for: [completed], timeout: 10)

            backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))
            drainMutationQueue(queue)

            XCTAssertFalse(events.events.contains { $0.type == .stopped })
            if operation == "replace" {
                XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmID)?.alarmKitManaged, false)
            } else {
                XCTAssertNil(WarmAlarmStore.shared.load(id: alarmID))
            }
            withExtendedLifetime(plugin) {}
        }
    }

    func testAlarmKitObservationStateConsumesLocalTerminalTransitionAtomically() {
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: 4_242_424_261)
        let state = WarmAlarmAlarmKitObservationState()
        _ = state.update(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))
        state.beginMutation(ids: [alarmKitID])

        let update = state.update(WarmAlarmAlarmKitSnapshot(states: [:]))

        XCTAssertEqual(update.previous.states[alarmKitID], .alerting)
        XCTAssertEqual(update.suppressedTerminalIDs, [alarmKitID])
        XCTAssertTrue(state.update(WarmAlarmAlarmKitSnapshot(states: [:])).suppressedTerminalIDs.isEmpty)
    }

    func testAlarmKitAlertingUpdateEmitsFiredEventForStoredAlarm() {
        let alarmId = Int64(4_242_424_250)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_observation")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(
            scheduleError: nil,
            authorizationState: .denied
        )
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        backend.authorizationState = .authorized
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(
            states: [WarmAlarmAlarmKitPlan.id(for: alarmId): .alerting]
        ))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired])
        XCTAssertEqual(eventsApi.events.map(\.alarmId), [alarmId])
    }

    func testAlarmKitCountdownUpdateStopsAudioAndEmitsSnoozedEvent() {
        let alarmId = Int64(4_242_424_251)
        let fireAtMillis = Int64(1_900_000_300_000)
        let wire = WarmAlarmScheduleWire(
            id: alarmId,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            snooze: WarmAlarmSnoozeWire(durationMillis: 300_000)
        )
        let schedule = WarmAlarmScheduleData.from(wire: wire).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_countdown")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: mutationQueue,
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "alarmkit#1"
        )
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(
            states: [alarmKitID: .countdown],
            nextTriggerDates: [alarmKitID: Date(timeIntervalSince1970: Double(fireAtMillis) / 1_000)]
        ))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired, .snoozed])
        XCTAssertEqual(eventsApi.events.last?.snoozeDurationMillis, 300_000)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis, fireAtMillis)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
    }

    func testAlarmKitPausedThenCountdownUpdateWaitsForAuthoritativeSnoozeDeadline() {
        let alarmId = Int64(4_242_424_253)
        let fireAtMillis = Int64(1_900_000_300_000)
        let wire = WarmAlarmScheduleWire(
            id: alarmId,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            snooze: WarmAlarmSnoozeWire(durationMillis: 300_000)
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(WarmAlarmScheduleData.from(wire: wire).withAlarmKitManaged(true))

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_paused")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: mutationQueue,
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "alarmkit#1"
        )
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .paused]))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired, .snoozed])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.alarmKitSnoozeObserved, true)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(
            states: [alarmKitID: .countdown],
            nextTriggerDates: [alarmKitID: Date(timeIntervalSince1970: Double(fireAtMillis) / 1_000)]
        ))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired, .snoozed])
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis, fireAtMillis)
    }

    func testAlarmKitInitialCountdownUpdateSynchronizesAuthoritativeSnoozeDeadline() {
        let alarmId = Int64(4_242_424_254)
        let fireAtMillis = Int64(1_900_000_300_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_initial_countdown")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(
            states: [alarmKitID: .countdown],
            nextTriggerDates: [alarmKitID: Date(timeIntervalSince1970: Double(fireAtMillis) / 1_000)]
        ))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.snoozed])
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis, fireAtMillis)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.alarmKitSnoozeObserved, true)
    }

    func testAlarmKitCountdownWithoutFireDateEmitsOnceThenSynchronizesDeadline() {
        let alarmId = Int64(4_242_424_280)
        let fireAtMillis = Int64(1_900_000_300_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_initial_countdown")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .scheduled]))
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .countdown]))
        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.snoozed])
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.alarmKitSnoozeObserved, true)
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis)

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .countdown]))
        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.snoozed])

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(
            states: [alarmKitID: .countdown],
            nextTriggerDates: [alarmKitID: Date(timeIntervalSince1970: Double(fireAtMillis) / 1_000)]
        ))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.snoozed])
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis, fireAtMillis)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.alarmKitSnoozeObserved, true)
    }

    func testAlarmKitInitializationEmitsSnoozedOnceForCountdownSnapshot() {
        let alarmId = Int64(4_242_424_259)
        let fireAtMillis = Int64(Date().addingTimeInterval(300).timeIntervalSince1970 * 1_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: fireAtMillis)
        ).withAlarmKitManaged(true).withActiveSnooze(untilMillis: fireAtMillis)
        let encodedSchedule = try! JSONEncoder().encode(schedule)
        var legacyScheduleObject = try! JSONSerialization.jsonObject(with: encodedSchedule) as! [String: Any]
        legacyScheduleObject.removeValue(forKey: "alarmKitSnoozeObserved")
        let legacySchedule = try! JSONDecoder().decode(
            WarmAlarmScheduleData.self,
            from: JSONSerialization.data(withJSONObject: legacyScheduleObject)
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(legacySchedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_initial_countdown_replay")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        let countdownSnapshot = WarmAlarmAlarmKitSnapshot(
            states: [alarmKitID: .countdown],
            nextTriggerDates: [alarmKitID: Date(timeIntervalSince1970: Double(fireAtMillis) / 1_000)]
        )
        let backend = RecordingAlarmKitBackend(
            scheduleError: nil,
            snapshot: countdownSnapshot
        )
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let completed = expectation(description: "initialization completes")

        plugin.initialize { result in
            if case let .failure(error) = result {
                XCTFail("Initialization failed: \(error)")
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.snoozed])
        XCTAssertEqual(
            eventsApi.events.first.map { $0.occurredAtMillis + ($0.snoozeDurationMillis ?? 0) },
            fireAtMillis
        )
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis, fireAtMillis)

        backend.emitSnapshot(countdownSnapshot)

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.snoozed])
    }

    func testAlarmKitStoppedUpdateStopsAudioAndRemovesOneShotSchedule() {
        let alarmId = Int64(4_242_424_252)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_stop")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: mutationQueue,
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "alarmkit#1"
        )
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired, .stopped])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
    }

    func testAlarmKitStoppedUpdateAfterPauseRemovesOneShotSchedule() {
        let alarmId = Int64(4_242_424_260)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_paused_stop")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .paused]))
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))

        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.snoozed, .stopped])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
    }

    func testAlarmKitInitializationEmitsStoppedForMissingExpiredOneShot() {
        let alarmId = Int64(4_242_424_258)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                id: alarmId,
                scheduledAtMillis: Int64(Date().addingTimeInterval(-60).timeIntervalSince1970 * 1_000)
            )
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_expired_stop")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let completed = expectation(description: "initialization completes")

        plugin.initialize { result in
            if case let .failure(error) = result {
                XCTFail("Initialization failed: \(error)")
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(eventsApi.events.map(\.type), [.stopped])
        XCTAssertEqual(eventsApi.events.map(\.alarmId), [alarmId])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
    }

    func testAlarmKitQueryEmitsStoppedOnceForMissingExpiredOneShot() {
        let alarmId = Int64(4_242_424_281)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                id: alarmId,
                scheduledAtMillis: Int64(Date().addingTimeInterval(-60).timeIntervalSince1970 * 1_000)
            )
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_expired_stop")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let completed = expectation(description: "query completes")

        plugin.getScheduledAlarms { result in
            if case let .failure(error) = result {
                XCTFail("Query failed: \(error)")
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        XCTAssertEqual(eventsApi.events.map(\.type), [.stopped])
        XCTAssertEqual(eventsApi.events.map(\.alarmId), [alarmId])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
        let repeated = expectation(description: "repeated query completes")
        plugin.getScheduledAlarms { result in
            if case let .failure(error) = result { XCTFail("Query failed: \(error)") }
            repeated.fulfill()
        }
        wait(for: [repeated], timeout: 2)
        XCTAssertEqual(eventsApi.events.map(\.type), [.stopped])
    }

    func testCancelAlarmDoesNotEchoNativeRemovalAsStoppedEvent() {
        let alarmId = Int64(4_242_424_255)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_cancel_observation")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))
        backend.onCancel = { _ in
            backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))
        }
        let completed = expectation(description: "cancel alarm completes")

        plugin.cancelAlarm(id: alarmId) { result in
            if case let .failure(error) = result {
                XCTFail("Cancel alarm failed: \(error)")
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
    }

    func testCancelAllAlarmsDoesNotEchoNativeRemovalAsStoppedEvent() {
        let alarmId = Int64(4_242_424_256)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_cancel_all_observation")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))
        backend.onCancelAll = {
            backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))
        }
        let completed = expectation(description: "cancel all alarms completes")

        plugin.cancelAllAlarms { result in
            if case let .failure(error) = result {
                XCTFail("Cancel all alarms failed: \(error)")
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1)
        drainMutationQueue(mutationQueue)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
    }

    func testAlarmKitToNotificationReplacementDoesNotEchoNativeRemovalAsStoppedEvent() {
        let alarmId = Int64(4_242_424_257)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)

        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.alarmkit_replacement_observation")
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi, notificationMutationQueue: mutationQueue)
        let notificationCenter = UNUserNotificationCenter.current()
        let notificationCenterDelegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: delegate,
            forwardingDelegate: nil
        )
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: mutationQueue,
            notificationCenter: notificationCenter,
            notificationCenterDelegate: notificationCenterDelegate,
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: true
        )
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            notificationCenter.removePendingNotificationRequests(
                withIdentifiers: WarmAlarmPlugin.requestIdentifiers(for: alarmId, recurrenceWeekdays: nil)
            )
            withExtendedLifetime(plugin) {}
        }
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))
        backend.authorizationState = .denied
        backend.onCancel = { _ in
            backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))
        }
        let completed = expectation(description: "replacement completes")

        plugin.scheduleAlarm(
            schedule: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_600_000)
        ) { result in
            if case let .failure(error) = result {
                XCTFail("Replacement failed: \(error)")
            }
            completed.fulfill()
        }

        wait(for: [completed], timeout: 2)
        drainMutationQueue(mutationQueue)
        XCTAssertFalse(eventsApi.events.map(\.type).contains(.stopped))
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.alarmKitManaged, false)
    }

    func testPreparedSoundIsAdoptedReplacedAndRemovedThroughPlugin() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let alarmId: Int64 = 918_412
        let plugin = makeSoundLifecyclePlugin(backend: RecordingAlarmKitBackend(scheduleError: nil))
        let input = try makeSoundLifecycleRecording()
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            try? FileManager.default.removeItem(at: input)
            withExtendedLifetime(plugin) {}
        }
        func prepare() throws -> String {
            var prepared: Result<String?, Error>?
            let completed = expectation(description: "sound preparation completes")
            plugin.prepareSystemSound(primaryFilePath: input.path, backgroundAssetPath: nil) {
                prepared = $0
                completed.fulfill()
            }
            wait(for: [completed], timeout: 10)
            return try XCTUnwrap(try prepared?.get())
        }
        func schedule(_ sound: String) {
            var wire = makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
            wire.audio.systemSoundFilePath = sound
            let completed = expectation(description: "prepared sound is scheduled")
            plugin.scheduleAlarm(schedule: wire) { result in
                if case let .failure(error) = result { XCTFail("Scheduling failed: \(error)") }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 10)
        }
        let first = try prepare()
        schedule(first)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.systemSoundFilePath, first)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.systemManagedAudio, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first))
        let second = try prepare()
        schedule(second)
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second))
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.systemSoundFilePath, second)
        let cancelled = expectation(description: "prepared sound is cancelled")
        plugin.cancelAlarm(id: alarmId) { result in
            if case let .failure(error) = result { XCTFail("Cancellation failed: \(error)") }
            cancelled.fulfill()
        }
        wait(for: [cancelled], timeout: 10)
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testEmptyExplicitSoundFailsBeforeReplacingExistingAlarm() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let alarmId: Int64 = 918_413
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plugin = makeSoundLifecyclePlugin(backend: backend)
        let existing = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.save(existing)
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            withExtendedLifetime(plugin) {}
        }
        var replacement = makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_600_000)
        replacement.audio.systemSoundFilePath = ""
        let completed = expectation(description: "invalid sound is rejected")
        plugin.scheduleAlarm(schedule: replacement) { result in
            XCTAssertTrue(Thread.isMainThread, "Sound preparation errors must reply on the platform thread")
            if case .success = result { XCTFail("An explicit empty sound must fail before replacement") }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 10)
        XCTAssertTrue(backend.scheduledPlans.isEmpty)
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.scheduledAtMillis, existing.scheduledAtMillis)
    }

    func testUserStopDuringSoundPreparationPreservesTheCorrectScheduleGeneration() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let previousRecords = Array(WarmAlarmStore.shared.loadAll().values)
        let input = try makeSoundLifecycleRecording()
        defer {
            try? FileManager.default.removeItem(at: input)
            WarmAlarmStore.shared.clear()
            previousRecords.forEach { WarmAlarmStore.shared.save($0) }
        }
        let alarmId: Int64 = 4_242_424_277
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: alarmId)
        for preparationFails in [true, false] {
            WarmAlarmStore.shared.clear()
            let original = WarmAlarmScheduleData.from(
                wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
            ).withAlarmKitManaged(true)
            WarmAlarmStore.shared.save(original)
            let output = try WarmAlarmSoundFiles.prepare(primary: input, background: nil)
            defer { WarmAlarmSoundFiles.remove(named: output.lastPathComponent) }
            let backend = RecordingAlarmKitBackend(scheduleError: nil)
            let events = RecordingWarmAlarmEventsApi()
            let queue = WarmAlarmMutationQueue(label: "warm_alarm_tests.preparation_user_stop")
            let delegate = WarmAlarmDelegate(eventsApi: events, notificationMutationQueue: queue)
            let preparationError = NSError(domain: "PreparationUserStop", code: 1)
            var preparationCalls = 0
            let plugin = WarmAlarmPlugin(
                delegate: delegate,
                notificationMutationQueue: queue,
                notificationCenter: UNUserNotificationCenter.current(),
                notificationCenterDelegate: WarmAlarmNotificationCenterDelegate(
                    warmAlarmDelegate: delegate, forwardingDelegate: nil
                ),
                scheduleSoundPreparer: { source in
                    XCTAssertFalse(Thread.isMainThread)
                    XCTAssertEqual(source, input)
                    preparationCalls += 1
                    backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))
                    if preparationFails { throw preparationError }
                    return output
                },
                alarmKitBackend: backend,
                alarmKitUsageDescription: "Wake up",
                alarmKitLiveActivityEnabled: true
            )
            backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .alerting]))
            drainMutationQueue(queue)
            var replacement = makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_600_000)
            replacement.audio.filePath = input.path
            let completed = expectation(description: "preparation handles native Stop")
            plugin.scheduleAlarm(schedule: replacement) { result in
                XCTAssertTrue(Thread.isMainThread, "Sound preparation must reply on the platform thread")
                switch result {
                case .success: XCTAssertFalse(preparationFails)
                case let .failure(error):
                    XCTAssertTrue(preparationFails)
                    XCTAssertEqual((error as NSError).domain, preparationError.domain)
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 10)
            drainMutationQueue(queue)
            XCTAssertEqual(preparationCalls, 1)
            XCTAssertTrue(backend.cancelledIDs.isEmpty)
            if preparationFails {
                XCTAssertTrue(backend.scheduledPlans.isEmpty)
                XCTAssertEqual(events.events.map(\.type), [.fired, .stopped])
                XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
            } else {
                XCTAssertEqual(backend.scheduledPlans.count, 1)
                XCTAssertEqual(events.events.map(\.type), [.fired, .scheduled])
                XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.scheduledAtMillis, replacement.scheduledAtMillis)
                XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.alarmKitManaged, true)
            }
            withExtendedLifetime(plugin) {}
        }
    }

    func testPreparedSoundIsReleasedWhenPluginFallsBackToNotifications() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let alarmId: Int64 = 918_414
        let plugin = makeSoundLifecyclePlugin(backend: RecordingAlarmKitBackend(
            scheduleError: NSError(domain: "AlarmKitTests", code: 1)
        ))
        let input = try makeSoundLifecycleRecording()
        var prepared: Result<String?, Error>?
        let preparationCompleted = expectation(description: "fallback sound preparation completes")
        plugin.prepareSystemSound(primaryFilePath: input.path, backgroundAssetPath: nil) {
            prepared = $0
            preparationCompleted.fulfill()
        }
        wait(for: [preparationCompleted], timeout: 10)
        let output = try XCTUnwrap(try prepared?.get())
        defer {
            WarmAlarmStore.shared.remove(id: alarmId)
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: WarmAlarmPlugin.requestIdentifiers(for: alarmId, recurrenceWeekdays: nil)
            )
            try? FileManager.default.removeItem(at: input)
            WarmAlarmSoundFiles.remove(named: URL(fileURLWithPath: output).lastPathComponent)
            withExtendedLifetime(plugin) {}
        }
        var wire = makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        wire.audio.filePath = input.path
        wire.audio.systemSoundFilePath = output
        let completed = expectation(description: "prepared sound falls back")
        plugin.scheduleAlarm(schedule: wire) { result in
            if case let .failure(error) = result { XCTFail("Fallback failed: \(error)") }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 10)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.systemManagedAudio, false)
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId)?.systemSoundFilePath)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.filePath, input.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    private func makeSoundLifecyclePlugin(
        backend: RecordingAlarmKitBackend, usageDescription: String? = "Wake up",
        mutationQueue: WarmAlarmMutationQueue? = nil
    ) -> WarmAlarmPlugin {
        let queue = mutationQueue ?? WarmAlarmMutationQueue(label: "warm_alarm_tests.sound_lifecycle")
        let delegate = WarmAlarmDelegate(eventsApi: RecordingWarmAlarmEventsApi(), notificationMutationQueue: queue)
        return WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: queue,
            notificationCenter: UNUserNotificationCenter.current(),
            notificationCenterDelegate: WarmAlarmNotificationCenterDelegate(warmAlarmDelegate: delegate, forwardingDelegate: nil),
            alarmKitBackend: backend,
            alarmKitUsageDescription: usageDescription,
            alarmKitLiveActivityEnabled: true
        )
    }

    private func makeSoundLifecycleRecording() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][frame] = 0.2 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    func testAlarmKitSuccessDoesNotScheduleNotificationFallback() {
        let completed = expectation(description: "AlarmKit routing completes")
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let plan = makeAlarmKitPlan()
        var fallbackCallCount = 0

        WarmAlarmBackendRouting.schedule(
            plan: plan,
            alarmKitBackend: backend,
            fallback: { completion in
                fallbackCallCount += 1
                completion(nil)
            },
            completion: { result in
                XCTAssertEqual(try? result.get().backend, .alarmKit)
                XCTAssertNil(try? result.get().alarmKitError)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(backend.scheduledPlans, [plan])
        XCTAssertEqual(fallbackCallCount, 0)
    }

    func testAlarmKitFailureSchedulesNotificationFallback() {
        let completed = expectation(description: "fallback routing completes")
        let alarmKitError = NSError(domain: "AlarmKitTests", code: 1)
        let backend = RecordingAlarmKitBackend(scheduleError: alarmKitError)
        let plan = makeAlarmKitPlan()
        var fallbackCallCount = 0

        WarmAlarmBackendRouting.schedule(
            plan: plan,
            alarmKitBackend: backend,
            fallback: { completion in
                fallbackCallCount += 1
                completion(nil)
            },
            completion: { result in
                XCTAssertEqual(try? result.get().backend, .userNotifications)
                XCTAssertEqual((try? result.get().alarmKitError as NSError?)?.domain, alarmKitError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(backend.scheduledPlans, [plan])
        XCTAssertEqual(backend.cancelledIDs, [plan.id])
        XCTAssertEqual(fallbackCallCount, 1)
    }

    func testAlarmKitRollbackFailureDoesNotScheduleNotificationFallback() {
        let completed = expectation(description: "failed AlarmKit rollback completes")
        let scheduleError = NSError(domain: "AlarmKitScheduleTests", code: 1)
        let rollbackError = NSError(domain: "AlarmKitRollbackTests", code: 2)
        let backend = RecordingAlarmKitBackend(
            scheduleError: scheduleError,
            cancelError: rollbackError
        )
        let plan = makeAlarmKitPlan()
        var fallbackCallCount = 0

        WarmAlarmBackendRouting.schedule(
            plan: plan,
            alarmKitBackend: backend,
            fallback: { completion in
                fallbackCallCount += 1
                completion(nil)
            },
            completion: { result in
                switch result {
                case .success:
                    XCTFail("A failed AlarmKit rollback must not install a second backend")
                case let .failure(error):
                    XCTAssertEqual((error as NSError).domain, rollbackError.domain)
                }
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(backend.cancelledIDs, [plan.id])
        XCTAssertEqual(fallbackCallCount, 0)
    }

    func testNotificationFallbackFailureIsReturned() {
        let completed = expectation(description: "failed fallback routing completes")
        let backend = RecordingAlarmKitBackend(
            scheduleError: NSError(domain: "AlarmKitTests", code: 1)
        )
        let fallbackError = NSError(domain: "NotificationTests", code: 2)

        WarmAlarmBackendRouting.schedule(
            plan: makeAlarmKitPlan(),
            alarmKitBackend: backend,
            fallback: { completion in completion(fallbackError) },
            completion: { result in
                switch result {
                case .success:
                    XCTFail("Both failed backends must not report success")
                case let .failure(error):
                    XCTAssertEqual((error as NSError).domain, fallbackError.domain)
                }
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
    }

    func testAlarmKitPlanMapsOneShotIdentityAndSnoozeDuration() {
        let fireAtMillis = Int64(1_900_000_000_000)
        let wire = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: fireAtMillis,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                stopActionTitle: "Dismiss",
                snoozeActionTitle: "Snooze",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            snooze: WarmAlarmSnoozeWire(durationMillis: 300_000)
        )

        let plan = WarmAlarmAlarmKitPlan(
            schedule: WarmAlarmScheduleData.from(wire: wire),
            calendar: utcCalendar()
        )

        XCTAssertEqual(plan.id.uuidString, "5741524D-414C-4152-0000-00000000002A")
        XCTAssertEqual(plan.schedule, .fixed(Date(timeIntervalSince1970: 1_900_000_000)))
        XCTAssertEqual(plan.snoozeDuration, 300)
        XCTAssertEqual(plan.title, "Wake up")
        XCTAssertEqual(plan.stopTitle, "Dismiss")
        XCTAssertEqual(plan.snoozeTitle, "Snooze")
    }

    func testAlarmKitIdentityOwnershipDoesNotMatchUnrelatedAlarms() {
        XCTAssertTrue(WarmAlarmAlarmKitPlan.owns(WarmAlarmAlarmKitPlan.id(for: 42)))
        XCTAssertFalse(WarmAlarmAlarmKitPlan.owns(UUID(uuidString: "00000000-0000-0000-0000-00000000002A")!))
    }

    func testInvalidNativeWeekdaysDoNotReplaceAnExistingAlarm() {
        let previousRecords = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previousRecords.forEach { WarmAlarmStore.shared.save($0) }
        }
        let alarmId: Int64 = 4_242_424_279
        let original = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000, recurrenceWeekdays: [1, 3])
        ).withAlarmKitManaged(true)
        let invalidWeekdays: [[Int64]] = [[], [0], [8], [1, 8]]
        for weekdays in invalidWeekdays {
            WarmAlarmStore.shared.save(original)
            let backend = RecordingAlarmKitBackend(scheduleError: nil)
            let plugin = makeSoundLifecyclePlugin(backend: backend)
            let completed = expectation(description: "invalid native recurrence is rejected")
            plugin.scheduleAlarm(schedule: makeWireSchedule(
                id: alarmId, scheduledAtMillis: 1_900_000_600_000, recurrenceWeekdays: weekdays
            )) { result in
                XCTAssertTrue(Thread.isMainThread)
                switch result {
                case .success: XCTFail("Invalid recurrence must not become a successful native schedule")
                case let .failure(error): XCTAssertEqual((error as? PigeonError)?.code, "invalid-recurrence")
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 10)
            XCTAssertTrue(backend.scheduledPlans.isEmpty)
            XCTAssertTrue(backend.cancelledIDs.isEmpty)
            XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.scheduledAtMillis, original.scheduledAtMillis)
            XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.recurrenceWeekdays, [1, 3])
            withExtendedLifetime(plugin) {}
        }
    }

    func testAlarmKitPlanMapsIsoWeekdaysToLocalWeeklySchedule() {
        let calendar = utcCalendar()
        let fireAtMillis = millis(2026, 1, 5, 7, 30, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: fireAtMillis,
                recurrenceWeekdays: [1, 3, 5]
            ),
            calendar: calendar
        )

        let plan = WarmAlarmAlarmKitPlan(schedule: schedule, calendar: calendar)

        XCTAssertEqual(
            plan.schedule,
            .weekly(hour: 7, minute: 30, weekdays: [.monday, .wednesday, .friday])
        )
    }

    func testAlarmKitInitializationDoesNotDuplicateSystemManagedAlarm() {
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        )

        let selection = WarmAlarmPlugin.selectAlarmKitInitializationWork(
            schedules: [schedule],
            scheduledAlarmKitIDs: [WarmAlarmAlarmKitPlan.id(for: schedule.id)],
            nowMillis: 1_899_999_000_000
        )

        XCTAssertEqual(selection.alarmKitManaged.map(\.id), [schedule.id])
        XCTAssertEqual(selection.notificationRecovery.map(\.id), [])
        XCTAssertEqual(selection.expiredAlarmIDs, [])
    }

    func testAlarmKitInitializationFallsBackForMissingFutureAlarm() {
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        )

        let selection = WarmAlarmPlugin.selectAlarmKitInitializationWork(
            schedules: [schedule],
            scheduledAlarmKitIDs: [],
            nowMillis: 1_899_999_000_000
        )

        XCTAssertEqual(selection.alarmKitManaged.map(\.id), [])
        XCTAssertEqual(selection.notificationRecovery.map(\.id), [schedule.id])
        XCTAssertEqual(selection.expiredAlarmIDs, [])
    }

    func testAlarmKitInitializationRemovesMissingExpiredOneShot() {
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        )

        let selection = WarmAlarmPlugin.selectAlarmKitInitializationWork(
            schedules: [schedule],
            scheduledAlarmKitIDs: [],
            nowMillis: 1_900_000_000_001
        )

        XCTAssertEqual(selection.alarmKitManaged.map(\.id), [])
        XCTAssertEqual(selection.notificationRecovery.map(\.id), [])
        XCTAssertEqual(selection.expiredAlarmIDs, [schedule.id])
    }

    func testAlarmKitInitializationInventoryFailureDoesNotRecoverNotifications() {
        let inventoryError = NSError(domain: "AlarmKitInventoryTests", code: 3)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        )

        let result = WarmAlarmPlugin.resolveAlarmKitInitializationWork(
            schedules: [schedule],
            alarmStatesResult: .failure(inventoryError),
            nowMillis: 1_899_999_000_000
        )

        switch result {
        case .success:
            XCTFail("Unknown AlarmKit state must not be treated as an empty inventory")
        case let .failure(error):
            XCTAssertEqual((error as NSError).domain, inventoryError.domain)
        }
    }

    func testNativeCancellationFailurePreservesLocalState() {
        let completed = expectation(description: "failed native cancellation completes")
        let cancellationError = NSError(domain: "AlarmKitCancellationTests", code: 4)
        var cleanupCallCount = 0

        WarmAlarmNativeCancellation.perform(
            cancelNative: { completion in completion(cancellationError) },
            cleanupLocalState: { cleanupCallCount += 1 },
            completion: { error in
                XCTAssertEqual((error as NSError?)?.domain, cancellationError.domain)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(cleanupCallCount, 0)
    }

    func testNativeCancellationSuccessCleansLocalStateAfterNativeState() {
        let completed = expectation(description: "successful native cancellation completes")
        var operations = [String]()

        WarmAlarmNativeCancellation.perform(
            cancelNative: { completion in
                operations.append("native")
                completion(nil)
            },
            cleanupLocalState: { operations.append("local") },
            completion: { error in
                XCTAssertNil(error)
                completed.fulfill()
            }
        )

        wait(for: [completed], timeout: 1)
        XCTAssertEqual(operations, ["native", "local"])
    }

    func testAlarmKitSnapshotReportsOnlyAlertingAlarmAsRinging() {
        let alertingID = WarmAlarmAlarmKitPlan.id(for: 42)
        let countdownID = WarmAlarmAlarmKitPlan.id(for: 43)
        let snapshot = WarmAlarmAlarmKitSnapshot(states: [
            alertingID: .alerting,
            countdownID: .countdown,
        ])

        XCTAssertTrue(snapshot.isRinging(alarmId: nil))
        XCTAssertTrue(snapshot.isRinging(alarmId: 42))
        XCTAssertFalse(snapshot.isRinging(alarmId: 43))
        XCTAssertFalse(snapshot.isRinging(alarmId: 44))
    }

    func testAlarmKitCancellationStopsAlertingAlarmsAndCancelsOtherStates() {
        XCTAssertEqual(WarmAlarmAlarmKitCancellationAction.forState(.alerting), .stopThenCancel)
        XCTAssertEqual(WarmAlarmAlarmKitCancellationAction.forState(.scheduled), .cancel)
        XCTAssertEqual(WarmAlarmAlarmKitCancellationAction.forState(.countdown), .cancel)
        XCTAssertEqual(WarmAlarmAlarmKitCancellationAction.forState(.paused), .cancel)
    }

    func testAlarmKitCountdownSynchronizesItsNativeFireDateIntoStoredSnapshot() {
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        )
        let fireDate = Date(timeIntervalSince1970: 1_900_000_300)
        let snapshot = WarmAlarmAlarmKitSnapshot(
            states: [WarmAlarmAlarmKitPlan.id(for: schedule.id): .countdown],
            nextTriggerDates: [WarmAlarmAlarmKitPlan.id(for: schedule.id): fireDate]
        )

        var saved = [WarmAlarmScheduleData]()
        let synchronized = WarmAlarmPlugin.synchronizeAlarmKitCountdowns(
            schedules: [schedule],
            snapshot: snapshot,
            save: { saved.append($0) }
        )

        XCTAssertEqual(synchronized.first?.activeSnoozeUntilMillis, 1_900_000_300_000)
        XCTAssertEqual(saved.first?.activeSnoozeUntilMillis, 1_900_000_300_000)
        XCTAssertEqual(
            synchronized.first?.snapshotScheduledAtMillis(nowMillis: 1_900_000_200_000),
            1_900_000_300_000
        )
    }

    func testAlarmKitSnoozeRequiresLiveActivityHostOptIn() {
        let snoozingPlan = WarmAlarmAlarmKitPlan(
            schedule: WarmAlarmScheduleData.from(wire: WarmAlarmScheduleWire(
                id: 42,
                scheduledAtMillis: 1_900_000_000_000,
                notification: WarmAlarmNotificationWire(
                    title: "Wake up",
                    body: "Alarm",
                    keepNotificationAfterAlarmEnds: false
                ),
                audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
                snooze: WarmAlarmSnoozeWire(durationMillis: 300_000)
            ))
        )
        let plainPlan = WarmAlarmAlarmKitPlan(
            schedule: WarmAlarmScheduleData.from(
                wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
            )
        )

        XCTAssertFalse(WarmAlarmPlugin.canUseAlarmKit(
            for: snoozingPlan,
            liveActivityConfigured: false
        ))
        XCTAssertTrue(WarmAlarmPlugin.canUseAlarmKit(
            for: snoozingPlan,
            liveActivityConfigured: true
        ))
        XCTAssertTrue(WarmAlarmPlugin.canUseAlarmKit(
            for: plainPlan,
            liveActivityConfigured: false
        ))
    }

    func testInitializationSelectsManagedSnoozeAlarmForCleanupWhenHostOptInIsRemoved() {
        let schedule = WarmAlarmScheduleData.from(wire: WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            snooze: WarmAlarmSnoozeWire(durationMillis: 300_000)
        )).withAlarmKitManaged(true)
        let alarmKitID = WarmAlarmAlarmKitPlan.id(for: schedule.id)
        let snapshot = WarmAlarmAlarmKitSnapshot(states: [alarmKitID: .scheduled])

        XCTAssertEqual(
            WarmAlarmPlugin.incompatibleAlarmKitScheduleIDs(
                schedules: [schedule],
                snapshot: snapshot,
                liveActivityConfigured: false
            ),
            [alarmKitID]
        )
    }

    func testMissingAlarmKitManagedScheduleIsNoLongerReportedAsScheduled() {
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)

        XCTAssertEqual(
            WarmAlarmPlugin.missingAlarmKitManagedScheduleIDs(
                schedules: [schedule],
                snapshot: WarmAlarmAlarmKitSnapshot(states: [:])
            ),
            [schedule.id]
        )
    }

    func testFallbackCapacityFailurePreservesCallerSoundAndCleansInternalConversion() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("AlarmKit requires iOS 26") }
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        let input = try makeSoundLifecycleRecording()
        defer {
            try? FileManager.default.removeItem(at: input)
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        let pending = (0..<64).map { index in
            UNNotificationRequest(identifier: "unrelated-\(index)", content: UNMutableNotificationContent(), trigger: nil)
        }
        for inputKind in ["explicit", "legacyExternal", "legacyOwned"] {
            WarmAlarmStore.shared.clear()
            let staged = try WarmAlarmSoundFiles.prepare(primary: input, background: nil)
            defer { WarmAlarmSoundFiles.remove(named: staged.lastPathComponent) }
            let backend = RecordingAlarmKitBackend(scheduleError: NSError(domain: "NativeScheduleFailure", code: 1))
            let queue = WarmAlarmMutationQueue(label: "warm_alarm_tests.fallback_sound_failure")
            let delegate = WarmAlarmDelegate(eventsApi: RecordingWarmAlarmEventsApi(), notificationMutationQueue: queue)
            var inventoryReads = 0
            let plugin = WarmAlarmPlugin(
                delegate: delegate,
                notificationMutationQueue: queue,
                notificationCenter: UNUserNotificationCenter.current(),
                notificationCenterDelegate: WarmAlarmNotificationCenterDelegate(
                    warmAlarmDelegate: delegate, forwardingDelegate: nil
                ),
                pendingNotificationReader: { completion in
                    inventoryReads += 1
                    completion(pending)
                },
                alarmKitBackend: backend,
                alarmKitUsageDescription: "Wake up",
                alarmKitLiveActivityEnabled: true
            )
            var wire = makeWireSchedule(id: 4_242_424_282, scheduledAtMillis: 1_900_000_000_000)
            wire.audio.filePath = inputKind == "legacyOwned" ? staged.path : input.path
            wire.audio.systemSoundFilePath = inputKind == "explicit" ? staged.path : nil
            for attempt in 1...2 {
                let completed = expectation(description: "failed fallback keeps caller input for retry")
                plugin.scheduleAlarm(schedule: wire) { result in
                    switch result {
                    case .success: XCTFail("Full notification capacity must reject fallback")
                    case let .failure(error):
                        XCTAssertEqual((error as? PigeonError)?.code, "pending-notification-limit")
                    }
                    completed.fulfill()
                }
                wait(for: [completed], timeout: 10)
                XCTAssertEqual(inventoryReads, attempt)
                XCTAssertEqual(backend.scheduledPlans.count, attempt)
                XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
                if inputKind == "legacyExternal", let generated = backend.scheduledPlans.last?.preparedSoundName {
                    XCTAssertNotEqual(generated, staged.lastPathComponent)
                    let generatedURL = try XCTUnwrap(WarmAlarmSoundFiles.ownedURL(named: generated))
                    XCTAssertFalse(FileManager.default.fileExists(atPath: generatedURL.path))
                }
                XCTAssertNil(WarmAlarmStore.shared.load(id: wire.id))
            }
            withExtendedLifetime(plugin) {}
        }
    }

    func testAlarmKitQueryRemovesMissingRecurrenceAndKeepsNativeScheduledRecurrence() {
        let previous = Array(WarmAlarmStore.shared.loadAll().values)
        defer {
            WarmAlarmStore.shared.clear()
            previous.forEach { WarmAlarmStore.shared.save($0) }
        }
        for nativeScheduleExists in [false, true] {
            WarmAlarmStore.shared.clear()
            var wire = makeWireSchedule(id: 4_242_424_283, scheduledAtMillis: 1_900_000_000_000)
            wire.recurrence = WarmAlarmRecurrenceWire(weekdays: [1, 3])
            WarmAlarmStore.shared.save(WarmAlarmScheduleData.from(wire: wire).withAlarmKitManaged(true))
            let alarmKitID = WarmAlarmAlarmKitPlan.id(for: wire.id)
            let backend = RecordingAlarmKitBackend(
                scheduleError: nil,
                snapshot: WarmAlarmAlarmKitSnapshot(states: nativeScheduleExists ? [alarmKitID: .scheduled] : [:])
            )
            let plugin = makeSoundLifecyclePlugin(backend: backend)
            let completed = expectation(description: "query distinguishes missing and scheduled recurrence")
            plugin.getScheduledAlarms { result in
                switch result {
                case let .success(schedules):
                    XCTAssertEqual(schedules.map(\.id), nativeScheduleExists ? [wire.id] : [])
                case let .failure(error): XCTFail("Query failed: \(error)")
                }
                completed.fulfill()
            }
            wait(for: [completed], timeout: 10)
            XCTAssertEqual(WarmAlarmStore.shared.load(id: wire.id) != nil, nativeScheduleExists)
            withExtendedLifetime(plugin) {}
        }
    }

    func testFallbackCapacityFailurePreservesExistingNativeAlarmBeforeCancellation() {
        let previousRecords = Array(WarmAlarmStore.shared.loadAll().values)
        defer {
            WarmAlarmStore.shared.clear()
            previousRecords.forEach { WarmAlarmStore.shared.save($0) }
        }
        let alarmId: Int64 = 4_242_424_275
        let previous = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        var replacement = makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_100_000)
        replacement.snooze = WarmAlarmSnoozeWire(durationMillis: 60_000)
        let pending = (0..<64).map { index in
            UNNotificationRequest(identifier: "unrelated-\(index)", content: UNMutableNotificationContent(), trigger: nil)
        }
        for capacityIsFull in [true, false] {
            WarmAlarmStore.shared.clear()
            WarmAlarmStore.shared.save(previous)
            let cancellationError = NSError(domain: "FallbackCancellation", code: 1)
            let backend = RecordingAlarmKitBackend(
                scheduleError: nil, cancelError: capacityIsFull ? nil : cancellationError
            )
            let events = RecordingWarmAlarmEventsApi()
            let queue = WarmAlarmMutationQueue(label: "warm_alarm_tests.fallback_preflight")
            let delegate = WarmAlarmDelegate(eventsApi: events, notificationMutationQueue: queue)
            var inventoryReads = 0
            let plugin = WarmAlarmPlugin(
                delegate: delegate,
                notificationMutationQueue: queue,
                notificationCenter: UNUserNotificationCenter.current(),
                notificationCenterDelegate: WarmAlarmNotificationCenterDelegate(
                    warmAlarmDelegate: delegate, forwardingDelegate: nil
                ),
                pendingNotificationReader: { completion in
                    inventoryReads += 1
                    XCTAssertTrue(backend.cancelledIDs.isEmpty)
                    completion(capacityIsFull ? pending : [])
                },
                alarmKitBackend: backend,
                alarmKitUsageDescription: "Wake up",
                alarmKitLiveActivityEnabled: false
            )
            let completed = expectation(description: "fallback preflight preserves the working native alarm")

            plugin.scheduleAlarm(schedule: replacement) { result in
                switch result {
                case .success: XCTFail("Capacity or cancellation failure must reject replacement")
                case let .failure(error):
                    if capacityIsFull {
                        XCTAssertEqual((error as? PigeonError)?.code, "pending-notification-limit")
                    } else {
                        XCTAssertEqual((error as NSError).domain, cancellationError.domain)
                    }
                }
                completed.fulfill()
            }

            wait(for: [completed], timeout: 10)
            XCTAssertEqual(inventoryReads, 1)
            XCTAssertEqual(backend.cancelledIDs, capacityIsFull ? [] : [WarmAlarmAlarmKitPlan.id(for: alarmId)])
            XCTAssertTrue(backend.scheduledPlans.isEmpty)
            XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.alarmKitManaged, true)
            XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.scheduledAtMillis, previous.scheduledAtMillis)
            withExtendedLifetime(plugin) {}
        }
    }

    func testFallbackPreflightDoesNotSuppressUserStopWhileInventoryIsPending() {
        let previousRecords = Array(WarmAlarmStore.shared.loadAll().values)
        WarmAlarmStore.shared.clear()
        defer {
            WarmAlarmStore.shared.clear()
            previousRecords.forEach { WarmAlarmStore.shared.save($0) }
        }
        let alarmId: Int64 = 4_242_424_276
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        WarmAlarmStore.shared.save(schedule)
        let backend = RecordingAlarmKitBackend(scheduleError: nil)
        let events = RecordingWarmAlarmEventsApi()
        let queue = WarmAlarmMutationQueue(label: "warm_alarm_tests.preflight_user_stop")
        let delegate = WarmAlarmDelegate(eventsApi: events, notificationMutationQueue: queue)
        let inventoryRequested = expectation(description: "fallback waits for notification inventory")
        var finishInventory: (([UNNotificationRequest]) -> Void)?
        let plugin = WarmAlarmPlugin(
            delegate: delegate,
            notificationMutationQueue: queue,
            notificationCenter: UNUserNotificationCenter.current(),
            notificationCenterDelegate: WarmAlarmNotificationCenterDelegate(
                warmAlarmDelegate: delegate, forwardingDelegate: nil
            ),
            pendingNotificationReader: { completion in
                finishInventory = completion
                inventoryRequested.fulfill()
            },
            alarmKitBackend: backend,
            alarmKitUsageDescription: "Wake up",
            alarmKitLiveActivityEnabled: false
        )
        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [WarmAlarmAlarmKitPlan.id(for: alarmId): .alerting]))
        drainMutationQueue(queue)
        var replacement = makeWireSchedule(id: alarmId, scheduledAtMillis: 1_900_000_100_000)
        replacement.snooze = WarmAlarmSnoozeWire(durationMillis: 60_000)
        let completed = expectation(description: "full inventory rejects replacement")
        plugin.scheduleAlarm(schedule: replacement) { result in
            if case .success = result { XCTFail("Full inventory must reject replacement") }
            completed.fulfill()
        }
        wait(for: [inventoryRequested], timeout: 10)

        backend.emitSnapshot(WarmAlarmAlarmKitSnapshot(states: [:]))
        finishInventory?((0..<64).map {
            UNNotificationRequest(identifier: "unrelated-\($0)", content: UNMutableNotificationContent(), trigger: nil)
        })

        wait(for: [completed], timeout: 10)
        drainMutationQueue(queue)
        XCTAssertTrue(backend.cancelledIDs.isEmpty)
        XCTAssertEqual(events.events.map(\.type), [.fired, .failed, .stopped])
        XCTAssertNil(WarmAlarmStore.shared.load(id: alarmId))
        withExtendedLifetime(plugin) {}
    }

    func testNativeToNotificationPreflightFailureRemovesStaleManagedRecord() {
        let previousSchedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        ).withAlarmKitManaged(true)
        var saved = [WarmAlarmScheduleData]()
        var removedIDs = [Int64]()

        WarmAlarmPlugin.reconcileFallbackPreflightFailure(
            alarmId: previousSchedule.id,
            previousSchedule: previousSchedule,
            attemptedAlarmKit: false,
            removedPreviousAlarmKit: true,
            save: { saved.append($0) },
            remove: { removedIDs.append($0) }
        )

        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(removedIDs, [previousSchedule.id])
    }

    private func makeAlarmKitPlan() -> WarmAlarmAlarmKitPlan {
        WarmAlarmAlarmKitPlan(
            schedule: WarmAlarmScheduleData.from(
                wire: makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
            ),
            calendar: utcCalendar()
        )
    }

    func testListsEveryFallbackIdentifierForCancellation() {
        XCTAssertEqual(
            WarmAlarmPlugin.fallbackIdentifiers(for: 42),
            [
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
    }

    func testListsEveryRequestIdentifierForCancellation() {
        XCTAssertEqual(
            WarmAlarmPlugin.requestIdentifiers(for: 42, recurrenceWeekdays: [2, 4]),
            [
                "42",
                "42#2",
                "42#4",
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
    }

    func testBuildsActionableFallbackChainForOneShotAlarm() {
        let schedule = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false)
        )
        let content = UNMutableNotificationContent()
        content.title = "Wake up"
        content.body = "Alarm"
        content.userInfo = ["alarmId": "42"]
        content.categoryIdentifier = "WARM_ALARM"

        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )

        XCTAssertEqual(
            requests.map(\.identifier),
            [
                "42",
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.count, 7)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(
            triggers.compactMap { utcCalendar().date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970.rounded()) },
            [1_900_000_000, 1_900_000_030, 1_900_000_060, 1_900_000_090, 1_900_000_120, 1_900_000_150,
             1_900_000_180]
        )
        for request in requests {
            XCTAssertEqual(request.content.title, "Wake up")
            XCTAssertEqual(request.content.body, "Alarm")
            XCTAssertEqual(request.content.userInfo["alarmId"] as? String, "42")
            XCTAssertEqual(request.content.categoryIdentifier, "WARM_ALARM")
        }
    }

    func testFallbackChainCarriesOneStableOccurrenceTokenWithIsolatedOrdinals() {
        let scheduledAtMillis = Int64(1_900_000_000_000)
        let schedule = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let content = UNMutableNotificationContent()
        content.userInfo = ["alarmId": "42", "hostPayload": "preserved"]

        let firstRequests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: utcCalendar()
        )
        let secondRequests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: utcCalendar()
        )

        let firstMetadata = firstRequests.compactMap { occurrenceMetadata(from: $0.content) }
        let secondMetadata = secondRequests.compactMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(firstMetadata.count, 7)
        XCTAssertEqual(Set(firstMetadata.compactMap { $0["token"] as? String }).count, 1)
        XCTAssertEqual(firstMetadata.compactMap { $0["ordinal"] as? Int }, Array(0...6))
        XCTAssertTrue(firstRequests.allSatisfy { $0.content.userInfo["alarmId"] as? String == "42" })
        XCTAssertTrue(firstRequests.allSatisfy { $0.content.userInfo["hostPayload"] as? String == "preserved" })
        XCTAssertTrue(firstRequests.allSatisfy {
            PropertyListSerialization.propertyList($0.content.userInfo, isValidFor: .binary)
        })
        XCTAssertEqual(
            firstMetadata.first?["token"] as? String,
            secondMetadata.first?["token"] as? String
        )
    }

    func testBuildsSnoozeFallbackChainWithRelativeIntervals() {
        let fireAtMillis = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: fireAtMillis),
            fallbackAnchorMillis: nil
        )
        let content = UNMutableNotificationContent()
        content.userInfo = ["alarmId": "42"]
        content.categoryIdentifier = "WARM_ALARM"

        let requests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: fireAtMillis,
            nowMillis: fireAtMillis - 60_000,
            content: content
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        XCTAssertEqual(
            requests.compactMap { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval },
            [60, 90, 120, 150, 180, 210, 240]
        )
        XCTAssertTrue(requests.allSatisfy { $0.content.userInfo["alarmId"] as? String == "42" })
        XCTAssertTrue(requests.allSatisfy { $0.content.categoryIdentifier == "WARM_ALARM" })
        let metadata = requests.compactMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(metadata.count, 7)
        XCTAssertEqual(Set(metadata.compactMap { $0["token"] as? String }).count, 1)
        XCTAssertEqual(metadata.compactMap { $0["ordinal"] as? Int }, Array(0...6))
    }

    func testSnoozeOccurrenceMetadataKeepsFixedEpochAcrossTimeZoneChanges() {
        let fireAtMillis = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: fireAtMillis),
            fallbackAnchorMillis: nil
        )
        let requests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: fireAtMillis,
            nowMillis: fireAtMillis - 60_000,
            content: UNMutableNotificationContent()
        )
        var deliveryCalendar = Calendar(identifier: .gregorian)
        deliveryCalendar.timeZone = TimeZone(secondsFromGMT: -7 * 60 * 60)!

        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["floating"] as? Bool == false
        })
        XCTAssertEqual(
            WarmAlarmPlugin.foregroundOccurrenceToken(
                content: requests[0].content,
                identifier: requests[0].identifier,
                alarmId: 42,
                deliveredAtMillis: fireAtMillis,
                calendar: deliveryCalendar,
                schedule: schedule
            ),
            "warm-alarm-v1:42#\(fireAtMillis)"
        )
    }

    func testBuildsFiniteFallbackChainAlongsideRecurringRequests() {
        let calendar = utcCalendar()
        let schedule = WarmAlarmScheduleWire(
            id: 42,
            scheduledAtMillis: 1_900_000_000_000,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            recurrence: WarmAlarmRecurrenceWire(weekdays: [2, 4])
        )
        let content = UNMutableNotificationContent()
        content.userInfo = ["alarmId": "42"]
        content.categoryIdentifier = "WARM_ALARM"

        let fallbackAnchorMillis = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: 1_899_996_400_000,
            calendar: calendar
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: content,
            fallbackAnchorMillis: fallbackAnchorMillis,
            calendar: calendar
        )

        XCTAssertEqual(
            requests.map(\.identifier),
            [
                "42#2",
                "42#4",
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
        XCTAssertTrue(requests.prefix(2).allSatisfy {
            ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == true
        })
        let fallbackTriggers = requests.dropFirst(2).compactMap {
            $0.trigger as? UNCalendarNotificationTrigger
        }
        XCTAssertEqual(fallbackTriggers.count, 6)
        XCTAssertTrue(fallbackTriggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(
            fallbackTriggers.compactMap { calendar.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970.rounded()) },
            [1_900_172_790, 1_900_172_820, 1_900_172_850, 1_900_172_880, 1_900_172_910, 1_900_172_940]
        )
        for request in requests {
            XCTAssertEqual(request.content.userInfo["alarmId"] as? String, "42")
            XCTAssertEqual(request.content.categoryIdentifier, "WARM_ALARM")
        }
    }

    func testRecurringPrimaryMetadataKeepsRequestedTimeAcrossDstGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduledAtMillis = millis(2030, 3, 3, 2, 30, calendar: calendar)
        let schedule = makeWireSchedule(
            scheduledAtMillis: scheduledAtMillis,
            recurrenceWeekdays: [7]
        )
        let fallbackAnchorMillis = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 1, 0, calendar: calendar),
            calendar: calendar
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: fallbackAnchorMillis,
            calendar: calendar
        )

        let fallbackTime = calendar.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: Double(fallbackAnchorMillis) / 1_000)
        )
        XCTAssertEqual(fallbackTime.hour, 3)
        XCTAssertEqual(fallbackTime.minute, 0)
        let metadata = occurrenceMetadata(from: requests[0].content)
        XCTAssertEqual(metadata?["hour"] as? Int, 2)
        XCTAssertEqual(metadata?["minute"] as? Int, 30)
    }

    func testRecurringFallbackAnchorMovesPastCurrentTime() {
        let calendar = utcCalendar()
        let schedule = makeWireSchedule(
            scheduledAtMillis: millis(2030, 3, 17, 17, 46, calendar: calendar),
            recurrenceWeekdays: [2, 4]
        )

        let anchor = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 3, 20, 18, 0, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(anchor, millis(2030, 3, 21, 17, 46, calendar: calendar))
    }

    func testRecurringFallbackAnchorMatchesNativeTriggerBeforeFutureScheduledDate() {
        let calendar = utcCalendar()
        let schedule = makeWireSchedule(
            scheduledAtMillis: millis(2030, 1, 28, 7, 0, calendar: calendar),
            recurrenceWeekdays: [1]
        )

        let anchor = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 1, 6, 8, 0, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(anchor, millis(2030, 1, 7, 7, 0, calendar: calendar))
    }

    func testRecurringFallbackAnchorPreservesLocalTimeAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let schedule = makeWireSchedule(
            scheduledAtMillis: millis(2030, 3, 10, 1, 30, calendar: calendar),
            recurrenceWeekdays: [1]
        )

        let anchor = WarmAlarmPlugin.fallbackAnchorMillis(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 3, 30, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(anchor, millis(2030, 3, 11, 1, 30, calendar: calendar))
    }

    func testPendingLimitKeepsCoreAndTrimsOnlyNewestFallbackSuffix() {
        let schedule = makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )
        let pending = Set((0..<58).map { "existing-\($0)" })

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
        ])
        XCTAssertEqual(selection?.omittedFallbackCount, 1)
        XCTAssertNotNil(WarmAlarmPlugin.fallbackCapacityWarning(
            omittedCount: selection?.omittedFallbackCount ?? 0
        ))
    }

    func testSnoozeCapacityPreservesCoreAndKillWarningReservation() {
        let fireAtMillis = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: fireAtMillis),
            fallbackAnchorMillis: nil
        )
        let requests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: fireAtMillis,
            nowMillis: fireAtMillis - 60_000,
            content: UNMutableNotificationContent()
        )
        let fullCoreCapacity = Set((0..<63).map { "existing-\($0)" } + ["42#2"])

        XCTAssertNil(WarmAlarmPlugin.selectSnoozeRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: fullCoreCapacity,
            isKillWarningConfigured: false,
            limit: 64
        ))

        let killWarningReserved = WarmAlarmPlugin.selectSnoozeRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: Set((0..<62).map { "existing-\($0)" }),
            isKillWarningConfigured: true,
            limit: 64
        )
        XCTAssertEqual(killWarningReserved?.requests.map(\.identifier), ["42"])
        XCTAssertEqual(killWarningReserved?.omittedFallbackCount, 6)

        let pendingWithFallbacks = Set((0..<58).map { "existing-\($0)" })
            .union(WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let replacingFallbacks = WarmAlarmPlugin.selectSnoozeRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pendingWithFallbacks,
            isKillWarningConfigured: false,
            limit: 64
        )
        XCTAssertEqual(replacingFallbacks?.requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
        ])
        XCTAssertEqual(replacingFallbacks?.omittedFallbackCount, 1)
    }

    func testPendingLimitRefusesScheduleWhenCoreDoesNotFit() {
        let schedule = makeWireSchedule(
            scheduledAtMillis: 1_900_000_000_000,
            recurrenceWeekdays: [2, 4]
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: 1_900_172_760_000,
            calendar: utcCalendar()
        )
        let pending = Set((0..<63).map { "existing-\($0)" })

        XCTAssertNil(WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            limit: 64
        ))
    }

    func testPendingLimitReusesSlotsFromTheAlarmBeingReplaced() {
        let schedule = makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )
        let replacing = Set(WarmAlarmPlugin.requestIdentifiers(for: 42, recurrenceWeekdays: nil))
        let pending = replacing.union((0..<57).map { "existing-\($0)" })

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: replacing,
            limit: 64
        )

        XCTAssertEqual(selection?.requests.count, 7)
        XCTAssertEqual(selection?.omittedFallbackCount, 0)
    }

    func testPendingLimitDeduplicatesRepeatedCoreIdentifiers() {
        let schedule = makeWireSchedule(
            scheduledAtMillis: 1_900_000_000_000,
            recurrenceWeekdays: [2, 2, 2]
        )
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: 1_900_172_760_000,
            calendar: utcCalendar()
        )
        let pending = Set((0..<62).map { "existing-\($0)" })

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), ["42#2", "42#fallback#1"])
        XCTAssertEqual(selection?.omittedFallbackCount, 5)
    }

    func testPendingLimitReservesConfiguredKillWarningSlot() {
        let schedule = makeWireSchedule(scheduledAtMillis: 1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: schedule,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: schedule.scheduledAtMillis,
            calendar: utcCalendar()
        )
        let pending = Set((0..<57).map { "existing-\($0)" })
        let reservedSlotCount = WarmAlarmPlugin.killWarningReservedSlotCount(
            isConfigured: true,
            pendingIdentifiers: pending
        )

        let selection = WarmAlarmPlugin.selectRequestsWithinPendingLimit(
            requests,
            pendingIdentifiers: pending,
            replacingIdentifiers: [],
            reservedSlotCount: reservedSlotCount,
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), [
            "42",
            "42#fallback#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
        ])
        XCTAssertEqual(selection?.omittedFallbackCount, 1)
        XCTAssertEqual(WarmAlarmPlugin.killWarningReservedSlotCount(
            isConfigured: false,
            pendingIdentifiers: pending
        ), 0)
        XCTAssertEqual(WarmAlarmPlugin.killWarningReservedSlotCount(
            isConfigured: true,
            pendingIdentifiers: pending.union(["warm_alarm_kill_warning_notif"])
        ), 0)
    }

    func testKillWarningRequiresAProcessOwnedScheduleOrActivePlayback() {
        let nowMillis: Int64 = 1_900_000_000_000
        let future = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: nowMillis + 60_000)
        )
        let expired = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: nowMillis - 60_000)
        )
        XCTAssertFalse(WarmAlarmPlugin.needsKillWarningOnTerminate(
            schedules: [future.withAlarmKitManaged(true)], currentlyPlayingAlarmId: nil, nowMillis: nowMillis
        ))
        XCTAssertTrue(WarmAlarmPlugin.needsKillWarningOnTerminate(
            schedules: [future.withAlarmKitManaged(true), future], currentlyPlayingAlarmId: nil, nowMillis: nowMillis
        ))
        XCTAssertTrue(WarmAlarmPlugin.needsKillWarningOnTerminate(
            schedules: [], currentlyPlayingAlarmId: future.id, nowMillis: nowMillis
        ))
        XCTAssertFalse(WarmAlarmPlugin.needsKillWarningOnTerminate(
            schedules: [expired], currentlyPlayingAlarmId: nil, nowMillis: nowMillis
        ))
    }

    func testKillWarningConfigurationRequiresAnAvailableSlot() {
        XCTAssertFalse(WarmAlarmPlugin.canConfigureKillWarning(
            pendingIdentifiers: Set((0..<64).map { "existing-\($0)" }),
            limit: 64
        ))
        XCTAssertTrue(WarmAlarmPlugin.canConfigureKillWarning(
            pendingIdentifiers: Set((0..<63).map { "existing-\($0)" }),
            limit: 64
        ))
        XCTAssertTrue(WarmAlarmPlugin.canConfigureKillWarning(
            pendingIdentifiers: Set((0..<63).map { "existing-\($0)" })
                .union(["warm_alarm_kill_warning_notif"]),
            limit: 64
        ))
    }

    func testRecoveryRestoresOnlyStillFutureFallbacksWithRemainingIntervals() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor)
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )
        let content = UNMutableNotificationContent()

        XCTAssertTrue(WarmAlarmPlugin.shouldRecover(
            schedule: schedule,
            nowMillis: anchor + 45_000
        ))

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 45_000,
            pendingIdentifiers: ["42#fallback#1"],
            content: content,
            calendar: utcCalendar()
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        let triggers = requests.compactMap { $0.trigger as? UNTimeIntervalNotificationTrigger }
        XCTAssertEqual(triggers.count, 5)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(triggers.map(\.timeInterval), [15, 45, 75, 105, 135])
    }

    func testRecoveryKeepsScheduledFallbacksAlignedToCalendar() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor
        )
        let calendar = utcCalendar()

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 45_000,
            pendingIdentifiers: ["42#fallback#1"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.count, 5)
        XCTAssertTrue(triggers.allSatisfy { !$0.repeats })
        XCTAssertEqual(
            triggers.compactMap { calendar.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970 * 1_000) },
            [anchor + 60_000, anchor + 90_000, anchor + 120_000, anchor + 150_000, anchor + 180_000]
        )
    }

    func testRecoveryPreservesRecurringWallTimeAfterTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let wire = makeWireSchedule(
            scheduledAtMillis: millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar),
            recurrenceWeekdays: [1]
        )
        let fallbackAnchorMillis = WarmAlarmPlugin.fallbackAnchorMillis(
            for: wire,
            nowMillis: millis(2030, 3, 11, 6, 0, calendar: schedulingCalendar),
            calendar: schedulingCalendar
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: fallbackAnchorMillis,
            calendar: schedulingCalendar
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 11, 7, 0, calendar: recoveryCalendar) + 45_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#1",
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        let primaryTrigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(primaryTrigger?.dateComponents.hour, 7)
        XCTAssertEqual(primaryTrigger?.dateComponents.minute, 0)
        let fallbackTriggers = requests.dropFirst().compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(fallbackTriggers.map(\.dateComponents.hour), [7, 7, 7, 7, 7])
        XCTAssertEqual(fallbackTriggers.map(\.dateComponents.minute), [1, 1, 2, 2, 3])
        XCTAssertEqual(fallbackTriggers.map(\.dateComponents.second), [0, 30, 0, 30, 0])
    }

    func testRecoveryDetectsDateLineChangeWhenRecurringHourIsUnchanged() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(secondsFromGMT: 14 * 60 * 60)!
        let anchor = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: schedulingCalendar
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(secondsFromGMT: -10 * 60 * 60)!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 7, 0, calendar: recoveryCalendar) + 45_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let firstFallback = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(firstFallback?.dateComponents.year, 2030)
        XCTAssertEqual(firstFallback?.dateComponents.month, 3)
        XCTAssertEqual(firstFallback?.dateComponents.day, 11)
        XCTAssertEqual(firstFallback?.dateComponents.hour, 7)
        XCTAssertEqual(firstFallback?.dateComponents.minute, 0)
        XCTAssertEqual(firstFallback?.dateComponents.second, 30)
    }

    func testRecoveryDoesNotAdvanceAnExpiredRecurringFallbackChainWithoutTimeZoneChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let anchor = millis(2030, 3, 11, 7, 0, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 181_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertTrue(requests.isEmpty)
    }

    func testRecoveryRebuildsFallbacksAfterRecurringStopClearsAnchor() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let nextOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).clearingFallbackAnchor()

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 1, 8, 12, 0, calendar: calendar),
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(requests.map(\.identifier), WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let firstFallbackTrigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(
            firstFallbackTrigger.flatMap { calendar.date(from: $0.dateComponents) }
                .map { Int64($0.timeIntervalSince1970 * 1_000) },
            nextOccurrenceMillis + 30_000
        )
    }

    func testRecoveryAdvancesPastAnExpiredSnoozeAfterTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let anchor = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: schedulingCalendar
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 11, 7, 0, calendar: recoveryCalendar) + 45_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), [
            "42#fallback#2",
            "42#fallback#3",
            "42#fallback#4",
            "42#fallback#5",
            "42#fallback#6",
        ])
        XCTAssertEqual(requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }.count, 5)
        XCTAssertTrue(requests.compactMap { $0.trigger as? UNTimeIntervalNotificationTrigger }.isEmpty)
    }

    func testRecoveryDoesNotReuseAnExpiredSnoozeAnchorThatMatchesCurrentWallTime() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let scheduledAtMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let snoozeAnchorMillis = scheduledAtMillis + 3 * 60 * 60 * 1_000
        let wire = makeWireSchedule(
            scheduledAtMillis: scheduledAtMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        ).withActiveSnooze(
            untilMillis: snoozeAnchorMillis,
            fallbackAnchorMillis: snoozeAnchorMillis
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: snoozeAnchorMillis + 181_000,
            pendingIdentifiers: ["42#1"],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(requests.map(\.identifier), WarmAlarmPlugin.fallbackIdentifiers(for: 42))
        let firstTrigger = requests.first?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(firstTrigger?.dateComponents.year, 2030)
        XCTAssertEqual(firstTrigger?.dateComponents.month, 3)
        XCTAssertEqual(firstTrigger?.dateComponents.day, 18)
        XCTAssertEqual(firstTrigger?.dateComponents.hour, 7)
        XCTAssertEqual(firstTrigger?.dateComponents.minute, 0)
        XCTAssertEqual(firstTrigger?.dateComponents.second, 30)
    }

    func testRecoveryKeepsSnoozedPrimaryRelativeToFallbacks() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor)
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: Set(WarmAlarmPlugin.fallbackIdentifiers(for: 42)),
            content: UNMutableNotificationContent(),
            calendar: utcCalendar()
        )

        XCTAssertEqual(requests.map(\.identifier), ["42"])
        let trigger = requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(trigger?.timeInterval, 60)
        XCTAssertEqual(trigger?.repeats, false)
    }

    func testRecoveryBackfillsAnExpiredSelectedFallbackWithinItsSlot() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor)
        ).withActiveSnooze(
            untilMillis: anchor,
            fallbackAnchorMillis: anchor
        )

        let refreshedRequests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor + 31_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: utcCalendar()
        )
        let requests = WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
            [refreshedRequests],
            remainingRequestCount: 1
        )

        XCTAssertEqual(requests.map(\.identifier), ["42#fallback#2"])
        let trigger = requests.first?.trigger as? UNTimeIntervalNotificationTrigger
        XCTAssertEqual(trigger?.timeInterval, 29)
    }

    func testRecoveryReallocatesVacatedSlotsAcrossAlarmGroups() {
        let content = UNMutableNotificationContent()
        let laterFallback = UNNotificationRequest(
            identifier: "84#fallback#2",
            content: content,
            trigger: nil
        )

        XCTAssertEqual(
            WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
                [[], [laterFallback]],
                remainingRequestCount: 1
            ).map(\.identifier),
            []
        )
        XCTAssertEqual(
            WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
                [[laterFallback]],
                remainingRequestCount: 1
            ).map(\.identifier),
            ["84#fallback#2"]
        )
    }

    func testRecoveryReservesRemainingSlotsForFutureCoreRequests() {
        let content = UNMutableNotificationContent()
        let currentFallback = UNNotificationRequest(
            identifier: "42#fallback#2",
            content: content,
            trigger: nil
        )
        let futureCore = UNNotificationRequest(identifier: "84", content: content, trigger: nil)

        XCTAssertEqual(
            WarmAlarmPlugin.selectNextRecoveryRequestsWithinLimit(
                [[currentFallback], [futureCore]],
                remainingRequestCount: 1
            ).map(\.identifier),
            []
        )
    }

    func testRecoveryCapacityPreservesEveryMissingCoreBeforeFallbacks() {
        let anchor = Int64(1_900_000_000_000)
        let pending = Set((0..<60).map { "existing-\($0)" })
        let requestGroups = [Int64(42), 84].map { alarmId in
            let schedule = WarmAlarmScheduleData.from(
                wire: makeWireSchedule(id: alarmId, scheduledAtMillis: anchor),
                fallbackAnchorMillis: anchor
            )
            return WarmAlarmPlugin.makeRecoveryRequests(
                for: schedule,
                nowMillis: anchor - 60_000,
                pendingIdentifiers: pending,
                content: UNMutableNotificationContent(),
                calendar: utcCalendar()
            )
        }

        let selection = WarmAlarmPlugin.selectRecoveryRequestsWithinPendingLimit(
            requestGroups,
            pendingIdentifiers: pending,
            limit: 64
        )

        XCTAssertEqual(selection?.requests.map(\.identifier), [
            "42",
            "84",
            "42#fallback#1",
            "42#fallback#2",
        ])
        XCTAssertEqual(selection?.omittedFallbackCount, 10)
    }

    func testRecoveryOrdersTimeZoneShiftedSchedulesByReconstructedOccurrence() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let laterWire = makeWireSchedule(
            id: 42,
            scheduledAtMillis: millis(2030, 3, 5, 7, 0, calendar: schedulingCalendar),
            recurrenceWeekdays: [2]
        )
        let imminentWire = makeWireSchedule(
            id: 84,
            scheduledAtMillis: millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar),
            recurrenceWeekdays: [1]
        )
        let schedules = [laterWire, imminentWire].map {
            WarmAlarmScheduleData.from(
                wire: $0,
                fallbackAnchorMillis: $0.scheduledAtMillis,
                calendar: schedulingCalendar
            )
        }
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        let sorted = WarmAlarmPlugin.sortedRecoverableSchedules(
            schedules,
            nowMillis: millis(2030, 3, 11, 6, 0, calendar: recoveryCalendar),
            calendar: recoveryCalendar
        )

        XCTAssertEqual(sorted.map(\.id), [84, 42])
    }

    func testMigrationPersistsRecurringWallTimeFromPendingTrigger() throws {
        let legacyJSON = """
        {
          "id": 42,
          "scheduledAtMillis": 1900000000000,
          "notificationTitle": "Wake up",
          "notificationBody": "Alarm",
          "recurrenceWeekdays": [1]
        }
        """
        let schedule = try JSONDecoder().decode(
            WarmAlarmScheduleData.self,
            from: Data(legacyJSON.utf8)
        )
        var components = DateComponents()
        components.weekday = 2
        components.hour = 7
        components.minute = 30
        let pendingRequest = UNNotificationRequest(
            identifier: "42#1",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        var saved: [WarmAlarmScheduleData] = []

        let migrated = WarmAlarmPlugin.migrateRecurringWallTimes(
            [schedule],
            pendingRequests: [pendingRequest],
            save: { saved.append($0) }
        )

        XCTAssertEqual(migrated.first?.recurrenceHour, 7)
        XCTAssertEqual(migrated.first?.recurrenceMinute, 30)
        XCTAssertEqual(saved.map(\.id), [42])
        XCTAssertEqual(saved.first?.recurrenceHour, 7)
        XCTAssertEqual(saved.first?.recurrenceMinute, 30)
    }

    func testMigrationPreservesOneShotFallbackWallTimeFromPendingPrimary() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduledAtMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis
        )
        let components = schedulingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(scheduledAtMillis) / 1_000)
        )
        let pendingRequest = UNNotificationRequest(
            identifier: "42",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var saved = [WarmAlarmScheduleData]()

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingRequest],
            calendar: recoveryCalendar,
            save: { saved.append($0) }
        )

        let expectedAnchor = millis(2030, 3, 11, 7, 0, calendar: recoveryCalendar)
        XCTAssertEqual(migrated.first?.scheduledAtMillis, expectedAnchor)
        XCTAssertEqual(migrated.first?.fallbackAnchorMillis, expectedAnchor)
        XCTAssertEqual(
            migrated.first?.snapshotScheduledAtMillis(
                nowMillis: millis(2030, 3, 11, 6, 0, calendar: recoveryCalendar),
                calendar: recoveryCalendar
            ),
            expectedAnchor
        )
        XCTAssertEqual(saved.first?.scheduledAtMillis, expectedAnchor)
        XCTAssertEqual(saved.first?.fallbackAnchorMillis, expectedAnchor)
    }

    func testMigrationAcceptsMixedFallbackMetadataAfterSubsequentTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var firstRecoveryCalendar = Calendar(identifier: .gregorian)
        firstRecoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var secondRecoveryCalendar = Calendar(identifier: .gregorian)
        secondRecoveryCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let firstRecoveredAtMillis = millis(2030, 4, 1, 7, 0, calendar: firstRecoveryCalendar)
        let expectedAnchorMillis = millis(2030, 4, 1, 7, 0, calendar: secondRecoveryCalendar)
        let wire = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let initialSchedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )
        let survivingFallback = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar,
            occurrenceSeriesToken: initialSchedule.occurrenceSeriesToken
        )[1]
        let firstMigratedSchedule = initialSchedule.withOneShotAnchor(firstRecoveredAtMillis)
        let recoveredFallback = WarmAlarmPlugin.makeRecoveryRequests(
            for: firstMigratedSchedule,
            nowMillis: firstRecoveredAtMillis - 60_000,
            pendingIdentifiers: ["42", "42#fallback#1"],
            content: UNMutableNotificationContent(),
            calendar: firstRecoveryCalendar
        )[0]

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [firstMigratedSchedule],
            pendingRequests: [survivingFallback, recoveredFallback],
            calendar: secondRecoveryCalendar,
            save: { _ in }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, expectedAnchorMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, expectedAnchorMillis)
    }

    func testMigrationLeavesLegacyFallbackOnlyScheduleUnchanged() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let scheduledAtMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis
        )
        let fallbackFireAtMillis = scheduledAtMillis + 30_000
        let fallbackComponents = schedulingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: Double(fallbackFireAtMillis) / 1_000)
        )
        let pendingFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(dateMatching: fallbackComponents, repeats: false)
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let nowMillis = millis(2030, 3, 11, 6, 0, calendar: recoveryCalendar)
        var saved = [WarmAlarmScheduleData]()

        XCTAssertFalse(WarmAlarmPlugin.shouldRecover(schedule: schedule, nowMillis: nowMillis))

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingFallback],
            calendar: recoveryCalendar,
            save: { saved.append($0) }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, schedule.scheduledAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, schedule.fallbackAnchorMillis)
        XCTAssertTrue(saved.isEmpty)
    }

    func testMigrationLeavesInvalidOccurrenceDateUnchanged() {
        let calendar = utcCalendar()
        let scheduledAtMillis = millis(2030, 1, 1, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis
        )
        let content = makeOccurrenceContent(
            token: "invalid-occurrence",
            ordinal: 1,
            primaryDate: Date(timeIntervalSince1970: Double(scheduledAtMillis) / 1_000),
            calendar: calendar
        )
        var metadata = occurrenceMetadata(from: content)!
        metadata["month"] = 2
        metadata["day"] = 31
        content.userInfo = ["_warmAlarmOccurrenceV1": metadata]
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: 2030, month: 1, day: 1, hour: 7, minute: 0, second: 30),
                repeats: false
            )
        )
        var saved = [WarmAlarmScheduleData]()

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [fallback],
            calendar: calendar,
            save: { saved.append($0) }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, schedule.scheduledAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, schedule.fallbackAnchorMillis)
        XCTAssertTrue(saved.isEmpty)
    }

    func testMigrationLeavesConflictingPrimaryEpochUnchanged() {
        let calendar = utcCalendar()
        let storedAtMillis = millis(2030, 1, 1, 7, 0, calendar: calendar)
        let metadataAtMillis = millis(2030, 1, 2, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: storedAtMillis),
            fallbackAnchorMillis: storedAtMillis
        )
        let content = makeOccurrenceContent(
            token: "conflicting-occurrence",
            ordinal: 1,
            primaryDate: Date(timeIntervalSince1970: Double(metadataAtMillis) / 1_000),
            calendar: calendar
        )
        var metadata = occurrenceMetadata(from: content)!
        metadata["primaryEpochMillis"] = metadataAtMillis + 24 * 60 * 60 * 1_000
        content.userInfo = ["_warmAlarmOccurrenceV1": metadata]
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: 2030, month: 1, day: 2, hour: 7, minute: 0, second: 30),
                repeats: false
            )
        )
        var saved = [WarmAlarmScheduleData]()

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [fallback],
            calendar: calendar,
            save: { saved.append($0) }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, schedule.scheduledAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, schedule.fallbackAnchorMillis)
        XCTAssertTrue(saved.isEmpty)
    }

    func testMigrationUsesEmbeddedPrimaryWallTimeAcrossDstJump() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let primaryDate = schedulingCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        let scheduledAtMillis = Int64(primaryDate.timeIntervalSince1970 * 1_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis,
            occurrenceSeriesToken: "dst-occurrence"
        )
        let fallbackDate = primaryDate.addingTimeInterval(30)
        let fallbackComponents = schedulingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fallbackDate
        )
        let pendingFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "dst-occurrence",
                ordinal: 1,
                primaryDate: primaryDate,
                calendar: schedulingCalendar
            ),
            trigger: UNCalendarNotificationTrigger(dateMatching: fallbackComponents, repeats: false)
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Phoenix")!

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingFallback],
            calendar: recoveryCalendar,
            save: { _ in }
        )[0]

        let expectedPrimaryDate = recoveryCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        XCTAssertEqual(migrated.scheduledAtMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
        XCTAssertEqual(migrated.fallbackAnchorMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
    }

    func testMigrationKeepsGregorianWallTimeWhenPreferredCalendarChanges() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let primaryDate = schedulingCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        let scheduledAtMillis = Int64(primaryDate.timeIntervalSince1970 * 1_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis,
            occurrenceSeriesToken: "calendar-occurrence"
        )
        let fallbackDate = primaryDate.addingTimeInterval(30)
        let pendingFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "calendar-occurrence",
                ordinal: 1,
                primaryDate: primaryDate,
                calendar: schedulingCalendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: schedulingCalendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: fallbackDate
                ),
                repeats: false
            )
        )
        var recoveryCalendar = Calendar(identifier: .buddhist)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/Phoenix")!

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [pendingFallback],
            calendar: recoveryCalendar,
            save: { _ in }
        )[0]

        var expectedCalendar = Calendar(identifier: .gregorian)
        expectedCalendar.timeZone = recoveryCalendar.timeZone
        let expectedPrimaryDate = expectedCalendar.date(from: DateComponents(
            year: 2030,
            month: 3,
            day: 10,
            hour: 1,
            minute: 59,
            second: 50
        ))!
        XCTAssertEqual(migrated.scheduledAtMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
        XCTAssertEqual(migrated.fallbackAnchorMillis, Int64(expectedPrimaryDate.timeIntervalSince1970 * 1_000))
    }

    func testMigrationPreservesRepeatedHourSelectionFromPrimaryEpoch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = calendar.date(from: DateComponents(year: 2030, month: 11, day: 3, hour: 0))!
        let matchingComponents = DateComponents(hour: 1, minute: 30, second: 0)
        let firstOccurrence = calendar.nextDate(
            after: midnight,
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
        let lastOccurrence = calendar.nextDate(
            after: midnight,
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .last,
            direction: .forward
        )!
        XCTAssertNotEqual(firstOccurrence, lastOccurrence)
        let firstOccurrenceMillis = Int64(firstOccurrence.timeIntervalSince1970 * 1_000)
        let lastOccurrenceMillis = Int64(lastOccurrence.timeIntervalSince1970 * 1_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: firstOccurrenceMillis),
            fallbackAnchorMillis: firstOccurrenceMillis,
            occurrenceSeriesToken: "repeated-hour-occurrence"
        )
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "repeated-hour-occurrence",
                ordinal: 1,
                primaryDate: lastOccurrence,
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: lastOccurrence.addingTimeInterval(30)
                ),
                repeats: false
            )
        )

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [fallback],
            calendar: calendar,
            save: { _ in }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, lastOccurrenceMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, lastOccurrenceMillis)
    }

    func testRecoveryRequestsPreserveSurvivingOccurrenceToken() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor,
            occurrenceSeriesToken: "surviving-occurrence"
        )
        let calendar = utcCalendar()
        let primaryDate = Date(timeIntervalSince1970: Double(anchor) / 1_000)
        let fallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "surviving-occurrence",
                ordinal: 1,
                primaryDate: primaryDate,
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: primaryDate.addingTimeInterval(30)
                ),
                repeats: false
            )
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: [fallback.identifier],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == "surviving-occurrence"
        })
    }

    func testRecoveryRejectsPendingRequestsFromReplacedGeneration() {
        let anchor = Int64(1_900_000_000_000)
        let calendar = utcCalendar()
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor,
            occurrenceSeriesToken: "new-generation"
        )
        let oldFallback = UNNotificationRequest(
            identifier: "42#fallback#1",
            content: makeOccurrenceContent(
                token: "old-generation",
                ordinal: 1,
                primaryDate: Date(timeIntervalSince1970: Double(anchor) / 1_000),
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: Date(timeIntervalSince1970: Double(anchor + 30_000) / 1_000)
                ),
                repeats: false
            )
        )

        let staleIdentifiers = WarmAlarmPlugin.staleRecoveryRequestIdentifiers(
            for: [schedule],
            in: [oldFallback]
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: Set([oldFallback.identifier]).subtracting(staleIdentifiers),
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(staleIdentifiers, [oldFallback.identifier])
        XCTAssertTrue(requests.map(\.identifier).contains(oldFallback.identifier))
        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == "new-generation"
        })
    }

    func testSnapshotsRemainingSnoozeFallbacksAfterPrimaryFires() {
        let snoozeAtMillis = Int64(1_900_000_300_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: snoozeAtMillis - 300_000),
            fallbackAnchorMillis: snoozeAtMillis - 300_000,
            occurrenceSeriesToken: "current-generation"
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let fallbackRequests = Array(WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: snoozeAtMillis - 60_000,
            content: UNMutableNotificationContent()
        ).dropFirst())

        let snapshot = WarmAlarmPlugin.pendingSnoozeRequests(
            for: schedule,
            in: fallbackRequests
        )

        XCTAssertEqual(snapshot.map(\.identifier), fallbackRequests.map(\.identifier))
    }

    func testSnoozeRollbackRecalculatesRemainingFallbackDelay() {
        let snoozeAtMillis = Int64(1_900_000_300_000)
        let calendar = utcCalendar()
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: snoozeAtMillis - 300_000),
            fallbackAnchorMillis: snoozeAtMillis - 300_000,
            calendar: calendar,
            occurrenceSeriesToken: "current-generation"
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let originalRequests = Array(WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: snoozeAtMillis - 60_000,
            content: UNMutableNotificationContent()
        ).dropFirst())

        let rollbackRequests = WarmAlarmPlugin.makeSnoozeRollbackRequests(
            for: schedule,
            restoring: originalRequests,
            nowMillis: snoozeAtMillis + 30_000,
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertEqual(rollbackRequests.first?.identifier, "42#fallback#2")
        XCTAssertEqual(
            (rollbackRequests.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval,
            30
        )
    }

    func testSnoozeRollbackDoesNotAdvanceExpiredChainToNextRecurrence() {
        let calendar = utcCalendar()
        let snoozeAtMillis = millis(2030, 1, 7, 7, 5, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: millis(2030, 1, 7, 7, 0, calendar: calendar),
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: wire.scheduledAtMillis,
            calendar: calendar,
            occurrenceSeriesToken: "current-generation"
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let originalFallbacks = Array(WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: snoozeAtMillis - 60_000,
            content: UNMutableNotificationContent()
        ).dropFirst())

        let rollbackRequests = WarmAlarmPlugin.makeSnoozeRollbackRequests(
            for: schedule,
            restoring: originalFallbacks,
            nowMillis: snoozeAtMillis + 181_000,
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertTrue(rollbackRequests.isEmpty)
    }

    func testOneShotMigrationIgnoresPendingRequestsFromReplacedGeneration() {
        let calendar = utcCalendar()
        let storedAtMillis = millis(2030, 1, 1, 7, 0, calendar: calendar)
        let oldAtMillis = millis(2030, 1, 2, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: storedAtMillis),
            fallbackAnchorMillis: storedAtMillis,
            occurrenceSeriesToken: "new-generation"
        )
        let oldPrimary = UNNotificationRequest(
            identifier: "42",
            content: makeOccurrenceContent(
                token: "old-generation",
                ordinal: 0,
                primaryDate: Date(timeIntervalSince1970: Double(oldAtMillis) / 1_000),
                calendar: calendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: Date(timeIntervalSince1970: Double(oldAtMillis) / 1_000)
                ),
                repeats: false
            )
        )

        let migrated = WarmAlarmPlugin.migrateOneShotFallbackAnchors(
            [schedule],
            pendingRequests: [oldPrimary],
            calendar: calendar,
            save: { _ in }
        )[0]

        XCTAssertEqual(migrated.scheduledAtMillis, storedAtMillis)
        XCTAssertEqual(migrated.fallbackAnchorMillis, storedAtMillis)
    }

    func testRecoveryRetainsSeriesTokenWhenRepeatingPrimaryUsesPreviousAnchorMetadata() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let previousAnchorMillis = millis(2030, 3, 11, 7, 0, calendar: schedulingCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: previousAnchorMillis,
                recurrenceWeekdays: [1]
            ),
            fallbackAnchorMillis: previousAnchorMillis,
            calendar: schedulingCalendar,
            occurrenceSeriesToken: "recurring-series"
        )
        let repeatingPrimary = UNNotificationRequest(
            identifier: "42#1",
            content: makeOccurrenceContent(
                token: "recurring-series",
                ordinal: 0,
                primaryDate: Date(timeIntervalSince1970: Double(previousAnchorMillis) / 1_000),
                calendar: schedulingCalendar
            ),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: 7, minute: 0, weekday: 2),
                repeats: true
            )
        )
        var recoveryCalendar = Calendar(identifier: .gregorian)
        recoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let nowMillis = millis(2030, 3, 18, 7, 0, calendar: recoveryCalendar) + 45_000
        let firstRecovery = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: nowMillis,
            pendingIdentifiers: [repeatingPrimary.identifier],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )
        let survivingFallback = firstRecovery[0]

        let secondRecovery = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: nowMillis,
            pendingIdentifiers: [repeatingPrimary.identifier, survivingFallback.identifier],
            content: UNMutableNotificationContent(),
            calendar: recoveryCalendar
        )

        XCTAssertFalse(secondRecovery.isEmpty)
        XCTAssertTrue(secondRecovery.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == "recurring-series"
        })
    }

    func testRecoveryAddsStableMetadataWhenOnlyLegacyPrimaryIsPending() {
        let calendar = utcCalendar()
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: anchor),
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )
        let legacyPrimary = UNNotificationRequest(
            identifier: "42",
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: Date(timeIntervalSince1970: Double(anchor) / 1_000)
                ),
                repeats: false
            )
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: [legacyPrimary.identifier],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        XCTAssertFalse(requests.isEmpty)
        XCTAssertEqual(requests.compactMap { occurrenceMetadata(from: $0.content) }.count, requests.count)
        let legacyPrimaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: legacyPrimary.content,
            identifier: legacyPrimary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 5_000,
            calendar: calendar,
            schedule: schedule
        )
        let recoveredFallbackToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: requests[0].content,
            identifier: requests[0].identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 35_000,
            calendar: calendar,
            schedule: schedule
        )
        XCTAssertEqual(legacyPrimaryToken, recoveredFallbackToken)
    }

    func testRecoveryUsesStableMetadataAcrossRecurringAndSnoozeRequests() {
        let calendar = utcCalendar()
        let anchor = Int64(1_900_000_000_000)
        let wire = makeWireSchedule(
            scheduledAtMillis: anchor,
            recurrenceWeekdays: [1]
        )
        let snoozeAtMillis = anchor + 60_000
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )
        let snoozeRequests = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeAtMillis,
            nowMillis: anchor,
            content: UNMutableNotificationContent()
        )
        let pendingRequests = [snoozeRequests[0], snoozeRequests[1]]

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor,
            pendingIdentifiers: Set(pendingRequests.map(\.identifier)),
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        let snoozeToken = occurrenceMetadata(from: snoozeRequests[0].content)?["token"] as? String
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == snoozeToken
        })
        let recurrenceTime = calendar.dateComponents(
            [.hour, .minute],
            from: Date(timeIntervalSince1970: Double(anchor) / 1_000)
        )
        let recoveredRecurrenceMetadata = requests.first { $0.identifier == "42#1" }
            .flatMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(recoveredRecurrenceMetadata?["hour"] as? Int, recurrenceTime.hour)
        XCTAssertEqual(recoveredRecurrenceMetadata?["minute"] as? Int, recurrenceTime.minute)
    }

    func testRecoveredRecurrenceMetadataKeepsRequestedTimeAcrossDstGap() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let scheduledAtMillis = millis(2030, 3, 3, 2, 30, calendar: calendar)
        let snoozeAtMillis = millis(2030, 3, 10, 1, 5, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: scheduledAtMillis,
                recurrenceWeekdays: [7]
            ),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeAtMillis,
            fallbackAnchorMillis: snoozeAtMillis
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: millis(2030, 3, 10, 1, 0, calendar: calendar),
            pendingIdentifiers: ["42"],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        let metadata = requests.first { $0.identifier == "42#7" }
            .flatMap { occurrenceMetadata(from: $0.content) }
        XCTAssertEqual(metadata?["hour"] as? Int, 2)
        XCTAssertEqual(metadata?["minute"] as? Int, 30)
    }

    func testRecoveryReusesInitialTokenWhenNoRequestsRemainPending() {
        let calendar = utcCalendar()
        let anchor = Int64(1_900_000_000_000)
        let wire = makeWireSchedule(scheduledAtMillis: anchor)
        let initialRequests = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )

        let recoveredRequests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: calendar
        )

        let initialToken = occurrenceMetadata(from: initialRequests[0].content)?["token"] as? String
        XCTAssertFalse(recoveredRequests.isEmpty)
        XCTAssertTrue(recoveredRequests.allSatisfy {
            occurrenceMetadata(from: $0.content)?["token"] as? String == initialToken
        })
    }

    func testForegroundOccurrenceTrackerScopesSuppressionToResettableOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))

        tracker.clear(alarmId: 42)

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
    }

    func testDelayedPrimaryDoesNotRepeatFallbackAlreadyHandledForSameOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
    }

    func testOlderOccurrenceRemainsSuppressedAfterNewerOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#2000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#2000"))
    }

    func testOldestOccurrenceRemainsSuppressedAfterMoreThanPendingLimitOccurrences() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        for occurrence in 1...65 {
            XCTAssertTrue(tracker.shouldHandleAndMark(
                alarmId: 42,
                occurrenceToken: "series#\(occurrence)"
            ))
        }

        XCTAssertFalse(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1"))
    }

    func testStopSuppressesLateFallbackUntilNextPrimaryOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        XCTAssertTrue(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000", perform: {}))
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})

        XCTAssertFalse(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000", perform: {}))
        XCTAssertTrue(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#2000", perform: {}))
        XCTAssertFalse(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#2000", perform: {}))
    }

    func testStopOnFallbackAbsorbsDelayedPrimaryBeforeNextOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})

        XCTAssertFalse(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000", perform: {}))
        XCTAssertTrue(tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#2000", perform: {}))
    }

    func testStopRejectsOlderOccurrenceButAllowsCurrentOccurrenceAction() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        var stoppedOccurrences = [String]()

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#2000"))
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000") {
            stoppedOccurrences.append("older")
        }
        tracker.stop(alarmId: 42, occurrenceToken: "series#2000") {
            stoppedOccurrences.append("current")
        }

        XCTAssertEqual(stoppedOccurrences, ["current"])
    }

    func testStopConsumesCurrentOccurrenceOnlyOnce() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        var actionCount = 0

        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000"))
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000") {
            actionCount += 1
        }
        tracker.stop(alarmId: 42, occurrenceToken: "series#1000") {
            actionCount += 1
        }

        XCTAssertEqual(actionCount, 1)
    }

    func testConsumedOccurrenceSurvivesTrackerReinitialization() {
        let suiteName = "WarmAlarmConsumedOccurrenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WarmAlarmConsumedOccurrenceStore(defaults: defaults)
        var actionCount = 0

        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ) {
            actionCount += 1
        }
        let reinitializedTracker = WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store)
        reinitializedTracker.stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ) {
            actionCount += 1
        }

        XCTAssertEqual(actionCount, 1)

        reinitializedTracker.clear(alarmId: 42)
        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ) {
            actionCount += 1
        }

        XCTAssertEqual(actionCount, 2)
    }

    func testConsumedOccurrenceSuppressesRetainedNotificationAfterTrackerReinitialization() {
        let suiteName = "WarmAlarmConsumedOccurrenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WarmAlarmConsumedOccurrenceStore(defaults: defaults)

        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#1000"
        )
        let reinitializedTracker = WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store)

        XCTAssertFalse(reinitializedTracker.shouldHandleAndMark(
            alarmId: 42,
            occurrenceToken: "series#1000"
        ))
        XCTAssertTrue(reinitializedTracker.shouldHandleAndMark(
            alarmId: 42,
            occurrenceToken: "series#2000"
        ))
    }

    func testStopRejectsOccurrenceBeforePersistedScheduleAnchorAfterTrackerReinitialization() {
        let calendar = utcCalendar()
        let currentAnchorMillis = Int64(2_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: currentAnchorMillis),
            fallbackAnchorMillis: currentAnchorMillis,
            calendar: calendar
        )
        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            nowMillis: currentAnchorMillis,
            calendar: calendar
        )
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        var didRunAction = false

        tracker.stop(
            alarmId: 42,
            occurrenceToken: "series#1000",
            minimumOccurrenceMillis: minimumOccurrenceMillis
        ) {
            didRunAction = true
        }

        XCTAssertFalse(didRunAction)
    }

    func testRecurringActionRejectsRetainedOccurrenceAfterFallbackAnchorCleared() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let retainedOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let latestOccurrenceMillis = millis(2030, 1, 21, 7, 0, calendar: calendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: firstOccurrenceMillis,
                recurrenceWeekdays: [1]
            ),
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).clearingFallbackAnchor()
        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            nowMillis: latestOccurrenceMillis + 1_000,
            calendar: calendar
        )
        let suiteName = "WarmAlarmConsumedOccurrenceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WarmAlarmConsumedOccurrenceStore(defaults: defaults)
        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#\(firstOccurrenceMillis)"
        )
        var didRunAction = false

        WarmAlarmForegroundOccurrenceTracker(consumedOccurrenceStore: store).stop(
            alarmId: 42,
            occurrenceToken: "series#\(retainedOccurrenceMillis)",
            minimumOccurrenceMillis: minimumOccurrenceMillis
        ) {
            didRunAction = true
        }

        XCTAssertEqual(minimumOccurrenceMillis, latestOccurrenceMillis)
        XCTAssertFalse(didRunAction)
    }

    func testRecurringActionBoundIgnoresLaterActiveSnoozeChain() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let interveningOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let snoozeOccurrenceMillis = millis(2030, 1, 21, 7, 30, calendar: calendar)
        let wire = makeWireSchedule(
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeOccurrenceMillis,
            fallbackAnchorMillis: snoozeOccurrenceMillis
        )
        let recurringContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        )[0].content

        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            content: recurringContent,
            nowMillis: interveningOccurrenceMillis + 1_000,
            calendar: calendar
        )

        XCTAssertEqual(minimumOccurrenceMillis, interveningOccurrenceMillis)
    }

    func testRecurringActionBoundKeepsExpiredSnoozeNotificationWithinItsOccurrence() {
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let snoozeOccurrenceMillis = firstOccurrenceMillis + 5 * 60 * 1_000
        let wire = makeWireSchedule(
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeOccurrenceMillis,
            fallbackAnchorMillis: snoozeOccurrenceMillis
        )
        let snoozeContent = WarmAlarmPlugin.makeSnoozeRequests(
            for: schedule,
            fireAtMillis: snoozeOccurrenceMillis,
            nowMillis: firstOccurrenceMillis,
            content: UNMutableNotificationContent()
        )[0].content

        let minimumOccurrenceMillis = WarmAlarmPlugin.actionOccurrenceLowerBound(
            for: schedule,
            content: snoozeContent,
            nowMillis: snoozeOccurrenceMillis + 181_000,
            calendar: calendar
        )

        XCTAssertEqual(minimumOccurrenceMillis, snoozeOccurrenceMillis)
    }

    func testStoppingRecurringOccurrencePreservesLaterSnoozeFallbackChain() {
        let alarmId = Int64(4_242_424_244)
        let calendar = utcCalendar()
        let firstOccurrenceMillis = millis(2030, 1, 7, 7, 0, calendar: calendar)
        let interveningOccurrenceMillis = millis(2030, 1, 14, 7, 0, calendar: calendar)
        let snoozeOccurrenceMillis = millis(2030, 1, 21, 7, 30, calendar: calendar)
        let wire = makeWireSchedule(
            id: alarmId,
            scheduledAtMillis: firstOccurrenceMillis,
            recurrenceWeekdays: [1]
        )
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        ).withActiveSnooze(
            untilMillis: snoozeOccurrenceMillis,
            fallbackAnchorMillis: snoozeOccurrenceMillis
        )
        let recurringContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: firstOccurrenceMillis,
            calendar: calendar
        )[0].content
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)
        let delegate = WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.recurring_stop_snooze")
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }

        delegate.handleStop(
            alarmId: alarmId,
            occurrenceToken: "warm-alarm-v1:\(alarmId)#\(interveningOccurrenceMillis)",
            deliveredIdentifier: "\(alarmId)#1",
            content: recurringContent
        )

        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.activeSnoozeUntilMillis, snoozeOccurrenceMillis)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.fallbackAnchorMillis, snoozeOccurrenceMillis)
    }

    func testRejectedReplacedOccurrenceStillStopsMatchingPlayingAudio() {
        let alarmId = Int64(4_242_424_242)
        let oldOccurrenceMillis = Int64(1_000)
        let replacementOccurrenceMillis = Int64(2_000)
        let oldWire = makeWireSchedule(id: alarmId, scheduledAtMillis: oldOccurrenceMillis)
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: oldWire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: oldOccurrenceMillis,
            calendar: utcCalendar()
        )[0].content
        let replacement = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                id: alarmId,
                scheduledAtMillis: replacementOccurrenceMillis
            ),
            fallbackAnchorMillis: replacementOccurrenceMillis,
            calendar: utcCalendar()
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(replacement)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.replaced_occurrence"),
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "series#\(oldOccurrenceMillis)"
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }

        delegate.handleStop(
            alarmId: alarmId,
            occurrenceToken: "series#\(oldOccurrenceMillis)",
            content: oldContent
        )

        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        XCTAssertNil(delegate.currentlyPlayingOccurrenceToken)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.fallbackAnchorMillis, replacementOccurrenceMillis)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testRejectedReplacedOccurrenceSnoozeStopsMatchingPlayingAudio() {
        let alarmId = Int64(4_242_424_243)
        let oldOccurrenceMillis = Int64(1_000)
        let replacementOccurrenceMillis = Int64(2_000)
        let oldWire = makeWireSchedule(id: alarmId, scheduledAtMillis: oldOccurrenceMillis)
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: oldWire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: oldOccurrenceMillis,
            calendar: utcCalendar()
        )[0].content
        let replacement = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                id: alarmId,
                scheduledAtMillis: replacementOccurrenceMillis
            ),
            fallbackAnchorMillis: replacementOccurrenceMillis,
            calendar: utcCalendar()
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(replacement)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.replaced_snooze_occurrence"),
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "series#\(oldOccurrenceMillis)"
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        var didComplete = false

        delegate.handleSnooze(
            alarmId: alarmId,
            occurrenceToken: "series#\(oldOccurrenceMillis)",
            content: oldContent
        ) {
            didComplete = true
        }

        XCTAssertTrue(didComplete)
        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        XCTAssertNil(delegate.currentlyPlayingOccurrenceToken)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.fallbackAnchorMillis, replacementOccurrenceMillis)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testReplacedGenerationRejectsOldNotificationAtSameOccurrence() {
        let alarmId = Int64(4_242_424_245)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "old-generation"
        )[0].content
        let replacement = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "new-generation"
        )
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(replacement)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.replaced_generation"),
            currentlyPlayingAlarmId: alarmId,
            currentlyPlayingOccurrenceToken: "old-generation#\(occurrenceMillis)"
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }

        delegate.handleStop(
            alarmId: alarmId,
            occurrenceToken: "old-generation#\(occurrenceMillis)",
            content: oldContent
        )

        XCTAssertNil(delegate.currentlyPlayingAlarmId)
        XCTAssertEqual(WarmAlarmStore.shared.load(id: alarmId)?.occurrenceSeriesToken, "new-generation")
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testForegroundDeliveryWaitsForQueuedScheduleReplacement() {
        let alarmId = Int64(4_242_424_246)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let oldSchedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "old-generation"
        )
        let replacement = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "new-generation"
        )
        let oldContent = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: oldSchedule.occurrenceSeriesToken
        )[0].content
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(oldSchedule)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.foreground_delivery_replacement")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: mutationQueue
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        let replacementCompleted = expectation(description: "replacement completes")
        let deliveryCompleted = expectation(description: "delivery completes")
        var didHandle = true

        mutationQueue.enqueueOnMain { finish in
            WarmAlarmStore.shared.save(replacement)
            replacementCompleted.fulfill()
            finish()
        }
        delegate.handleForegroundDelivery(
            alarmId: alarmId,
            identifier: String(alarmId),
            content: oldContent,
            deliveredAtMillis: occurrenceMillis
        ) { handled in
            didHandle = handled
            deliveryCompleted.fulfill()
        }

        wait(for: [replacementCompleted, deliveryCompleted], timeout: 1)
        XCTAssertFalse(didHandle)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testSceneLaunchDefaultActionEmitsFiredEvent() {
        let alarmId = Int64(4_242_424_248)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar()
        )
        let eventEmitted = expectation(description: "fired event emitted")
        let eventsApi = RecordingWarmAlarmEventsApi { _ in eventEmitted.fulfill() }
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.scene_launch")
        )
        let content = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: delegate.makeContent(from: schedule),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: schedule.occurrenceSeriesToken
        )[0].content
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)
        let responseCompleted = expectation(description: "notification response completed")
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }

        let handled = delegate.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            deliveredIdentifier: String(alarmId),
            content: content,
            deliveredAtMillis: occurrenceMillis,
            completionHandler: { responseCompleted.fulfill() }
        )

        wait(for: [eventEmitted, responseCompleted], timeout: 1)
        XCTAssertTrue(handled)
        XCTAssertEqual(eventsApi.events.map(\.type), [.fired])
    }

    func testForegroundNotificationMatchesAfterSecureCodingRoundTrip() throws {
        let alarmId = Int64(4_242_424_249)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: "secure-coding-round-trip"
        )
        let delegate = WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.secure_coding")
        )
        let request = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: delegate.makeContent(from: schedule),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: schedule.occurrenceSeriesToken
        )[0]
        let data = try NSKeyedArchiver.archivedData(withRootObject: request, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(ofClass: UNNotificationRequest.self, from: data)
        )

        let metadata = try XCTUnwrap(decoded.content.userInfo["_warmAlarmOccurrenceV1"] as? [String: Any])

        XCTAssertTrue(
            WarmAlarmPlugin.notificationContent(schedule, matches: decoded.content),
            "Decoded metadata types: \(metadata.mapValues { String(reflecting: type(of: $0)) })"
        )
    }

    func testSceneLaunchLeavesUnrelatedNotificationUnclaimed() {
        let delegate = WarmAlarmDelegate(
            eventsApi: RecordingWarmAlarmEventsApi(),
            notificationMutationQueue: WarmAlarmMutationQueue(label: "warm_alarm_tests.unrelated_scene_launch")
        )
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "OTHER_ALARM"
        content.userInfo["alarmId"] = "42"
        var didComplete = false

        let handled = delegate.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            deliveredIdentifier: "unrelated",
            content: content,
            deliveredAtMillis: 1_000,
            completionHandler: { didComplete = true }
        )

        XCTAssertFalse(handled)
        XCTAssertFalse(didComplete)
    }

    func testForegroundDeliveryRejectsCanceledAlarmAfterQueuedCancellation() {
        let alarmId = Int64(4_242_424_247)
        let occurrenceMillis = Int64(1_000)
        let wire = makeWireSchedule(id: alarmId, scheduledAtMillis: occurrenceMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar()
        )
        let content = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: occurrenceMillis,
            calendar: utcCalendar(),
            occurrenceSeriesToken: schedule.occurrenceSeriesToken
        )[1].content
        WarmAlarmStore.shared.remove(id: alarmId)
        WarmAlarmStore.shared.save(schedule)
        let eventsApi = RecordingWarmAlarmEventsApi()
        let mutationQueue = WarmAlarmMutationQueue(label: "warm_alarm_tests.foreground_delivery_cancellation")
        let delegate = WarmAlarmDelegate(
            eventsApi: eventsApi,
            notificationMutationQueue: mutationQueue
        )
        defer {
            delegate.stopIfPlaying(alarmId: alarmId)
            WarmAlarmStore.shared.remove(id: alarmId)
        }
        let cancellationCompleted = expectation(description: "cancellation completes")
        let deliveryCompleted = expectation(description: "delivery completes")
        var didHandle = true

        mutationQueue.enqueueOnMain { finish in
            WarmAlarmStore.shared.remove(id: alarmId)
            cancellationCompleted.fulfill()
            finish()
        }
        delegate.handleForegroundDelivery(
            alarmId: alarmId,
            identifier: "\(alarmId)#fallback#1",
            content: content,
            deliveredAtMillis: occurrenceMillis
        ) { handled in
            didHandle = handled
            deliveryCompleted.fulfill()
        }

        wait(for: [cancellationCompleted, deliveryCompleted], timeout: 1)
        XCTAssertFalse(didHandle)
        XCTAssertTrue(eventsApi.events.isEmpty)
    }

    func testOccurrenceGenerationsAreUniqueForTheSameAlarm() {
        let first = WarmAlarmPlugin.newOccurrenceSeriesToken(for: 42)
        let second = WarmAlarmPlugin.newOccurrenceSeriesToken(for: 42)

        XCTAssertTrue(first.hasPrefix("warm-alarm-v1:42:"))
        XCTAssertTrue(second.hasPrefix("warm-alarm-v1:42:"))
        XCTAssertNotEqual(first, second)
    }

    func testFloatingOneShotActionBoundFollowsNotificationAcrossTimeZones() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var deliveryCalendar = Calendar(identifier: .gregorian)
        deliveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let deliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: deliveryCalendar)
        let wire = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )
        let primaryRequest = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )[0]
        let occurrenceToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: primaryRequest.content,
            identifier: primaryRequest.identifier,
            alarmId: 42,
            deliveredAtMillis: deliveredOccurrenceMillis,
            calendar: deliveryCalendar,
            schedule: schedule
        )

        XCTAssertEqual(occurrenceToken, "warm-alarm-v1:42#\(deliveredOccurrenceMillis)")
        XCTAssertEqual(
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: schedule,
                content: primaryRequest.content,
                nowMillis: deliveredOccurrenceMillis,
                calendar: deliveryCalendar
            ),
            deliveredOccurrenceMillis
        )
    }

    func testFloatingOneShotActionBoundFollowsNotificationAcrossSubsequentTimeZoneChanges() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var firstDeliveryCalendar = Calendar(identifier: .gregorian)
        firstDeliveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var secondDeliveryCalendar = Calendar(identifier: .gregorian)
        secondDeliveryCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let firstDeliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: firstDeliveryCalendar)
        let secondDeliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: secondDeliveryCalendar)
        let wire = makeWireSchedule(scheduledAtMillis: scheduledAtMillis)
        let schedule = WarmAlarmScheduleData.from(
            wire: wire,
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        ).withOneShotAnchor(firstDeliveredOccurrenceMillis)
        let primaryRequest = WarmAlarmPlugin.makeRequests(
            for: wire,
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        )[0]
        let occurrenceToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: primaryRequest.content,
            identifier: primaryRequest.identifier,
            alarmId: 42,
            deliveredAtMillis: secondDeliveredOccurrenceMillis,
            calendar: secondDeliveryCalendar,
            schedule: schedule
        )

        XCTAssertEqual(occurrenceToken, "warm-alarm-v1:42#\(secondDeliveredOccurrenceMillis)")
        XCTAssertEqual(
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: schedule,
                content: primaryRequest.content,
                nowMillis: secondDeliveredOccurrenceMillis,
                calendar: secondDeliveryCalendar
            ),
            secondDeliveredOccurrenceMillis
        )
    }

    func testRecoveredOneShotActionBoundFollowsNotificationAcrossSubsequentTimeZoneChange() {
        var schedulingCalendar = Calendar(identifier: .gregorian)
        schedulingCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var firstRecoveryCalendar = Calendar(identifier: .gregorian)
        firstRecoveryCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        var deliveryCalendar = Calendar(identifier: .gregorian)
        deliveryCalendar.timeZone = TimeZone(identifier: "Europe/London")!
        let scheduledAtMillis = millis(2030, 4, 1, 7, 0, calendar: schedulingCalendar)
        let recoveredAtMillis = millis(2030, 4, 1, 7, 0, calendar: firstRecoveryCalendar)
        let deliveredOccurrenceMillis = millis(2030, 4, 1, 7, 0, calendar: deliveryCalendar)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(scheduledAtMillis: scheduledAtMillis),
            fallbackAnchorMillis: scheduledAtMillis,
            calendar: schedulingCalendar
        ).withOneShotAnchor(recoveredAtMillis)
        let recoveredRequest = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: recoveredAtMillis - 60_000,
            pendingIdentifiers: [],
            content: UNMutableNotificationContent(),
            calendar: firstRecoveryCalendar
        )[0]

        XCTAssertEqual(
            WarmAlarmPlugin.actionOccurrenceLowerBound(
                for: schedule,
                content: recoveredRequest.content,
                nowMillis: deliveredOccurrenceMillis,
                calendar: deliveryCalendar
            ),
            deliveredOccurrenceMillis
        )
    }

    func testStoppedOccurrenceDoesNotSuppressFallbackFromNextOccurrence() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()

        tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})

        XCTAssertTrue(tracker.handleIfAllowed(
            alarmId: 42,
            occurrenceToken: "series#2000",
            perform: {}
        ))
    }

    func testForegroundOccurrenceTokenEncodesFallbackAnchor() {
        XCTAssertEqual(
            WarmAlarmPlugin.foregroundOccurrenceToken(
                identifier: "42#fallback#3",
                alarmId: 42,
                deliveredAtMillis: 91_000
            ),
            "1000"
        )
        XCTAssertEqual(
            WarmAlarmPlugin.foregroundOccurrenceToken(
                identifier: "42#1",
                alarmId: 42,
                deliveredAtMillis: 91_000
            ),
            "91000"
        )
    }

    func testForegroundOccurrenceTokenIgnoresNotificationDeliveryLatency() {
        let anchor = Int64(1_900_000_000_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: makeWireSchedule(scheduledAtMillis: anchor),
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: anchor,
            calendar: utcCalendar()
        )
        let primary = requests[0]
        let fallback = requests[1]

        let primaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: primary.content,
            identifier: primary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 1_000
        )
        let fallbackToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: fallback.content,
            identifier: fallback.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 35_000
        )

        XCTAssertEqual(primaryToken, fallbackToken)
    }

    func testRecurringPrimaryUsesAStableTokenForEachWallOccurrence() {
        let calendar = utcCalendar()
        let primaryDate = calendar.date(from: DateComponents(
            year: 2030,
            month: 1,
            day: 7,
            hour: 7,
            minute: 0
        ))!
        let appleWeekday = calendar.component(.weekday, from: primaryDate)
        let isoWeekday = Int64(appleWeekday == 1 ? 7 : appleWeekday - 1)
        let anchor = Int64(primaryDate.timeIntervalSince1970 * 1_000)
        let requests = WarmAlarmPlugin.makeRequests(
            for: makeWireSchedule(
                scheduledAtMillis: anchor,
                recurrenceWeekdays: [isoWeekday]
            ),
            content: UNMutableNotificationContent(),
            fallbackAnchorMillis: anchor,
            calendar: calendar
        )
        let recurringPrimary = requests[0]
        let fallback = requests[1]

        let initialPrimaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: recurringPrimary.content,
            identifier: recurringPrimary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 5_000,
            calendar: calendar
        )
        let initialFallbackToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: fallback.content,
            identifier: fallback.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 35_000,
            calendar: calendar
        )
        let nextPrimaryToken = WarmAlarmPlugin.foregroundOccurrenceToken(
            content: recurringPrimary.content,
            identifier: recurringPrimary.identifier,
            alarmId: 42,
            deliveredAtMillis: anchor + 7 * 24 * 60 * 60 * 1_000 + 5_000,
            calendar: calendar
        )

        XCTAssertEqual(initialPrimaryToken, initialFallbackToken)
        XCTAssertNotEqual(nextPrimaryToken, initialFallbackToken)
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: initialFallbackToken))
        XCTAssertTrue(tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: nextPrimaryToken))
    }

    func testForegroundOccurrenceTrackerAtomicallyHandlesOneConcurrentFallback() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        let resultLock = NSLock()
        var handledCount = 0

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            guard tracker.shouldHandleAndMark(alarmId: 42, occurrenceToken: "series#1000") else { return }
            resultLock.lock()
            handledCount += 1
            resultLock.unlock()
        }

        XCTAssertEqual(handledCount, 1)
    }

    func testStopWaitsForAdmittedFallbackWorkBeforeCompleting() {
        let tracker = WarmAlarmForegroundOccurrenceTracker()
        let fallbackEntered = DispatchSemaphore(value: 0)
        let releaseFallback = DispatchSemaphore(value: 0)
        let fallbackCompleted = DispatchSemaphore(value: 0)
        let stopStarted = DispatchSemaphore(value: 0)
        let stopCompleted = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = tracker.handleIfAllowed(alarmId: 42, occurrenceToken: "series#1000") {
                fallbackEntered.signal()
                releaseFallback.wait()
            }
            fallbackCompleted.signal()
        }
        XCTAssertEqual(fallbackEntered.wait(timeout: .now() + 1), .success)

        DispatchQueue.global().async {
            stopStarted.signal()
            tracker.stop(alarmId: 42, occurrenceToken: "series#1000", perform: {})
            stopCompleted.signal()
        }
        XCTAssertEqual(stopStarted.wait(timeout: .now() + 1), .success)
        let stopResultBeforeRelease = stopCompleted.wait(timeout: .now() + 0.1)

        releaseFallback.signal()
        XCTAssertEqual(fallbackCompleted.wait(timeout: .now() + 1), .success)
        if stopResultBeforeRelease == .timedOut {
            XCTAssertEqual(stopCompleted.wait(timeout: .now() + 1), .success)
        }
        XCTAssertEqual(stopResultBeforeRelease, .timedOut)
    }

    func testRecoveryRequestsDeduplicateRepeatedWeekdays() {
        let anchor = Int64(1_900_000_000_000)
        let schedule = WarmAlarmScheduleData.from(
            wire: makeWireSchedule(
                scheduledAtMillis: anchor,
                recurrenceWeekdays: [2, 2, 2]
            ),
            fallbackAnchorMillis: anchor
        )

        let requests = WarmAlarmPlugin.makeRecoveryRequests(
            for: schedule,
            nowMillis: anchor - 60_000,
            pendingIdentifiers: Set(WarmAlarmPlugin.fallbackIdentifiers(for: 42)),
            content: UNMutableNotificationContent(),
            calendar: utcCalendar()
        )

        XCTAssertEqual(requests.map(\.identifier), ["42#2"])
    }

    func testDismissalRemovesEveryDeliveredIdentifierForTheExactAlarm() {
        XCTAssertEqual(
            WarmAlarmDelegate.deliveredIdentifiersToRemove(
                alarmId: 42,
                recurrenceWeekdays: [2, 4],
                deliveredIdentifier: "42#fallback#3"
            ),
            [
                "42",
                "42#2",
                "42#4",
                "42#fallback#1",
                "42#fallback#2",
                "42#fallback#3",
                "42#fallback#4",
                "42#fallback#5",
                "42#fallback#6",
            ]
        )
    }

    private func makeWireSchedule(
        id: Int64 = 42,
        scheduledAtMillis: Int64,
        recurrenceWeekdays: [Int64]? = nil
    ) -> WarmAlarmScheduleWire {
        WarmAlarmScheduleWire(
            id: id,
            scheduledAtMillis: scheduledAtMillis,
            notification: WarmAlarmNotificationWire(
                title: "Wake up",
                body: "Alarm",
                keepNotificationAfterAlarmEnds: false
            ),
            audio: WarmAlarmAudioWire(loop: true, vibrate: true, volumeEnforced: false),
            recurrence: recurrenceWeekdays.map { WarmAlarmRecurrenceWire(weekdays: $0) }
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeOccurrenceContent(
        token: String,
        ordinal: Int,
        primaryDate: Date,
        calendar: Calendar
    ) -> UNMutableNotificationContent {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: primaryDate
        )
        let content = UNMutableNotificationContent()
        content.userInfo = [
            "_warmAlarmOccurrenceV1": [
                "token": token,
                "ordinal": ordinal,
                "year": components.year!,
                "month": components.month!,
                "day": components.day!,
                "hour": components.hour!,
                "minute": components.minute!,
                "second": components.second!,
                "calendar": "gregorian",
                "floating": true,
                "timeZone": calendar.timeZone.identifier,
                "primaryEpochMillis": Int64(primaryDate.timeIntervalSince1970 * 1_000),
            ],
        ]
        return content
    }

    private func occurrenceMetadata(from content: UNNotificationContent) -> [String: Any]? {
        content.userInfo["_warmAlarmOccurrenceV1"] as? [String: Any]
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
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
        return Int64(date.timeIntervalSince1970 * 1_000)
    }
}

private final class RecordingAlarmKitBackend: WarmAlarmAlarmKitScheduling {
    private let scheduleError: Error?
    private let cancelError: Error?
    private let currentSnapshot: WarmAlarmAlarmKitSnapshot
    private(set) var scheduledPlans = [WarmAlarmAlarmKitPlan]()
    private(set) var cancelledIDs = [UUID]()
    private(set) var cancelAllCount = 0
    private var snapshotObserver: ((WarmAlarmAlarmKitSnapshot) -> Void)?
    var onCancel: ((UUID) -> Void)?
    var onCancelAll: (() -> Void)?
    var authorizationState: WarmAlarmAlarmKitAuthorization

    init(
        scheduleError: Error?,
        cancelError: Error? = nil,
        authorizationState: WarmAlarmAlarmKitAuthorization = .authorized,
        snapshot: WarmAlarmAlarmKitSnapshot = WarmAlarmAlarmKitSnapshot(states: [:])
    ) {
        self.scheduleError = scheduleError
        self.cancelError = cancelError
        self.authorizationState = authorizationState
        currentSnapshot = snapshot
    }

    func schedule(_ plan: WarmAlarmAlarmKitPlan, completion: @escaping (Error?) -> Void) {
        scheduledPlans.append(plan)
        completion(scheduleError)
    }

    func cancel(id: UUID, completion: @escaping (Error?) -> Void) {
        cancelledIDs.append(id)
        onCancel?(id)
        completion(cancelError)
    }

    func cancelAll(completion: @escaping (Error?) -> Void) {
        cancelAllCount += 1
        onCancelAll?()
        completion(cancelError)
    }

    func snapshot(completion: @escaping (Result<WarmAlarmAlarmKitSnapshot, Error>) -> Void) {
        completion(.success(currentSnapshot))
    }

    func observe(_ observer: @escaping (WarmAlarmAlarmKitSnapshot) -> Void) {
        snapshotObserver = observer
    }

    func emitSnapshot(_ snapshot: WarmAlarmAlarmKitSnapshot) {
        snapshotObserver?(snapshot)
    }
}

private final class ExistingNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {}

private final class RecordingWarmAlarmEventsApi: WarmAlarmEventsApiProtocol {
    private(set) var events = [WarmAlarmEventWire]()
    private let onEmit: ((WarmAlarmEventWire) -> Void)?

    init(onEmit: ((WarmAlarmEventWire) -> Void)? = nil) {
        self.onEmit = onEmit
    }

    func emitEvent(
        event: WarmAlarmEventWire,
        completion: @escaping (Result<Void, PigeonError>) -> Void
    ) {
        events.append(event)
        onEmit?(event)
        completion(.success(()))
    }
}
