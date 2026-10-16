import AppKit
import FlutterMacOS
import UserNotifications
import XCTest

@testable import warm_alarm_macos

final class WarmAlarmNotificationCenterDelegateTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw XCTSkip("Notification registration requires bash tool/run_macos_native_tests.sh")
        }
    }

    func testRegistrationForwardsHostPresentationAndItsCompletion() throws {
        let center = UNUserNotificationCenter.current()
        let previous = center.delegate
        defer { center.delegate = previous }
        let host = RecordingHostNotificationDelegate()
        center.delegate = host
        let registrar = NotificationTestRegistrar()
        WarmAlarmPlugin.register(with: registrar)
        let installed = try XCTUnwrap(center.delegate)
        let notification = try makeNotification(category: "HOST_NOTIFICATION")
        var completions = [UNNotificationPresentationOptions]()

        installed.userNotificationCenter?(center, willPresent: notification) { completions.append($0) }

        XCTAssertEqual(host.presentedIdentifiers, ["host-notification"])
        XCTAssertTrue(completions.isEmpty, "Wait for the host's asynchronous completion")
        host.presentationCompletion?([.badge])
        XCTAssertEqual(completions, [[.badge]])
        withExtendedLifetime(registrar) {}
    }

    func testRegistrationForwardsHostResponseAndWaitsForItsCompletion() throws {
        try withRegistration { center, host, _ in
            let notification = try makeNotification(category: "HOST_NOTIFICATION")
            let response = try makeResponse(notification: notification, action: "STOP")
            var completions = 0
            center.delegate?.userNotificationCenter?(center, didReceive: response) { completions += 1 }
            XCTAssertEqual(host.receivedActions, ["STOP"])
            XCTAssertEqual(completions, 0)
            host.responseCompletion?()
            XCTAssertEqual(completions, 1)
        }
    }

    func testOwnedNotificationsDoNotReachHostAndCompleteOnce() throws {
        try withRegistration { center, host, _ in
            let notification = try makeNotification(category: "WARM_ALARM")
            var presentations = [UNNotificationPresentationOptions]()
            center.delegate?.userNotificationCenter?(center, willPresent: notification) { presentations.append($0) }
            XCTAssertEqual(presentations, [[]], "An unknown owned alarm must be suppressed")
            var completions = 0
            let response = try makeResponse(notification: notification, action: "UNRECOGNIZED")
            center.delegate?.userNotificationCenter?(center, didReceive: response) { completions += 1 }
            XCTAssertEqual(completions, 1)
            XCTAssertTrue(host.presentedIdentifiers.isEmpty)
            XCTAssertTrue(host.receivedActions.isEmpty)
        }
    }

    func testSettingsCallbacksIncludingNilReachHost() throws {
        try withRegistration { center, host, _ in
            let notification = try makeNotification(category: "HOST_NOTIFICATION")
            center.delegate?.userNotificationCenter?(center, openSettingsFor: notification)
            center.delegate?.userNotificationCenter?(center, openSettingsFor: nil)
            XCTAssertEqual(host.settingsIdentifiers, ["host-notification", nil])
        }
    }

    func testMissingHostAndMissingOptionalMethodsCompleteOnce() throws {
        let center = UNUserNotificationCenter.current()
        let previous = center.delegate
        defer { center.delegate = previous }
        let emptyHost = EmptyNotificationDelegate()
        for host: UNUserNotificationCenterDelegate? in [nil, emptyHost] {
            center.delegate = host
            let registrar = NotificationTestRegistrar()
            WarmAlarmPlugin.register(with: registrar)
            let notification = try makeNotification(category: "HOST_NOTIFICATION")
            var presentations = [UNNotificationPresentationOptions]()
            center.delegate?.userNotificationCenter?(center, willPresent: notification) { presentations.append($0) }
            XCTAssertEqual(presentations, [[]])
            var completions = 0
            let response = try makeResponse(notification: notification, action: "STOP")
            center.delegate?.userNotificationCenter?(center, didReceive: response) { completions += 1 }
            XCTAssertEqual(completions, 1)
            withExtendedLifetime(registrar) {}
        }
    }

    func testRepeatedRegistrationsForwardOnceAndRestoreInReverseOrder() throws {
        try withRegistration { center, host, first in
            weak var firstDelegate = center.delegate
            let second = NotificationTestRegistrar()
            WarmAlarmPlugin.register(with: second)
            weak var secondDelegate = center.delegate
            let third = NotificationTestRegistrar()
            WarmAlarmPlugin.register(with: third)
            let notification = try makeNotification(category: "HOST_NOTIFICATION")
            var completions = 0
            center.delegate?.userNotificationCenter?(center, willPresent: notification) { _ in completions += 1 }
            XCTAssertEqual(host.presentedIdentifiers, ["host-notification"])
            host.presentationCompletion?([.badge])
            XCTAssertEqual(completions, 1)
            third.published = nil
            XCTAssertTrue(center.delegate === secondDelegate)
            second.published = nil
            XCTAssertTrue(center.delegate === firstDelegate)
            first.published = nil
            XCTAssertTrue(center.delegate === host)
        }
    }

    func testOutOfOrderReleaseSkipsDeadPreviousDelegates() throws {
        try withRegistration { center, host, first in
            weak var firstDelegate = center.delegate
            let second = NotificationTestRegistrar()
            WarmAlarmPlugin.register(with: second)
            weak var secondDelegate = center.delegate
            let third = NotificationTestRegistrar()
            WarmAlarmPlugin.register(with: third)
            second.published = nil
            XCTAssertNil(secondDelegate)
            third.published = nil
            XCTAssertTrue(center.delegate === firstDelegate)
            first.published = nil
            XCTAssertTrue(center.delegate === host)
        }
    }

    func testReleaseDoesNotOverwriteExternalReplacement() throws {
        try withRegistration { center, _, registrar in
            let replacement = EmptyNotificationDelegate()
            center.delegate = replacement
            registrar.published = nil
            XCTAssertTrue(center.delegate === replacement)
        }
    }

    func testHostIsWeakAndDoesNotLeaveAChainAfterRepeatedRegistration() throws {
        let center = UNUserNotificationCenter.current()
        let previous = center.delegate
        defer { center.delegate = previous }
        var host: RecordingHostNotificationDelegate? = RecordingHostNotificationDelegate()
        weak var weakHost = host
        center.delegate = host
        let first = NotificationTestRegistrar()
        WarmAlarmPlugin.register(with: first)
        weak var firstDelegate = center.delegate
        host = nil
        XCTAssertNil(weakHost)
        let second = NotificationTestRegistrar()
        WarmAlarmPlugin.register(with: second)
        first.published = nil
        XCTAssertNil(firstDelegate)
        let notification = try makeNotification(category: "HOST_NOTIFICATION")
        var presentations = [UNNotificationPresentationOptions]()
        center.delegate?.userNotificationCenter?(center, willPresent: notification) { presentations.append($0) }
        XCTAssertEqual(presentations, [[]])
        second.published = nil
        XCTAssertNil(center.delegate)
    }

    private func withRegistration(
        _ body: (UNUserNotificationCenter, RecordingHostNotificationDelegate, NotificationTestRegistrar) throws -> Void
    ) throws {
        let center = UNUserNotificationCenter.current()
        let previous = center.delegate
        defer { center.delegate = previous }
        let host = RecordingHostNotificationDelegate()
        center.delegate = host
        let registrar = NotificationTestRegistrar()
        WarmAlarmPlugin.register(with: registrar)
        try body(center, host, registrar)
        withExtendedLifetime(registrar) {}
    }

    private func makeResponse(notification: UNNotification, action: String) throws -> UNNotificationResponse {
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode(notification, forKey: "notification")
        archive.encode(action, forKey: "actionIdentifier")
        archive.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        let response = try XCTUnwrap(UNNotificationResponse(coder: decoder))
        XCTAssertEqual(response.notification.request.identifier, notification.request.identifier)
        XCTAssertEqual(response.actionIdentifier, action)
        return response
    }

    private func makeNotification(category: String) throws -> UNNotification {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = category
        content.userInfo = ["alarmId": "7075001"]
        let request = UNNotificationRequest(identifier: "host-notification", content: content, trigger: nil)
        let archive = NSKeyedArchiver(requiringSecureCoding: true)
        archive.encode(request, forKey: "request")
        archive.encode(Date(), forKey: "date")
        archive.finishEncoding()
        let decoder = try NSKeyedUnarchiver(forReadingFrom: archive.encodedData)
        let notification = try XCTUnwrap(UNNotification(coder: decoder))
        XCTAssertEqual(notification.request.identifier, request.identifier)
        XCTAssertEqual(notification.request.content.categoryIdentifier, category)
        XCTAssertEqual(notification.request.content.userInfo["alarmId"] as? String, "7075001")
        return notification
    }
}

private final class RecordingHostNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var receivedActions = [String]()
    var responseCompletion: (() -> Void)?
    var settingsIdentifiers = [String?]()
    var presentedIdentifiers = [String]()
    var presentationCompletion: ((UNNotificationPresentationOptions) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        presentedIdentifiers.append(notification.request.identifier)
        presentationCompletion = completionHandler
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        receivedActions.append(response.actionIdentifier)
        responseCompletion = completionHandler
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        settingsIdentifiers.append(notification?.request.identifier)
    }
}

private final class EmptyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {}

private final class NotificationTestRegistrar: NSObject, FlutterPluginRegistrar {
    let messenger: FlutterBinaryMessenger = NotificationTestMessenger()
    var textures: FlutterTextureRegistry { fatalError("Texture registration is outside this fixture") }
    var view: NSView? { nil }
    var viewController: NSViewController? { nil }
    var published: NSObject?

    func publish(_ value: NSObject) { published = value }
    func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel) {}
    func addApplicationDelegate(_ delegate: FlutterAppLifecycleDelegate) {}
    func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String) {}
    func lookupKey(forAsset asset: String) -> String { asset }
    func lookupKey(forAsset asset: String, fromPackage package: String) -> String { asset }
}

private final class NotificationTestMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(
        _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
