import Foundation
import UserNotifications

final class WarmAlarmNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    private final class WeakDelegateReference {
        weak var delegate: WarmAlarmNotificationCenterDelegate?

        init(_ delegate: WarmAlarmNotificationCenterDelegate) {
            self.delegate = delegate
        }
    }

    private static let installationLock = NSLock()
    private let warmAlarmDelegate: WarmAlarmDelegate
    private let previousWarmAlarmDelegates: [WeakDelegateReference]
    weak var forwardingDelegate: UNUserNotificationCenterDelegate?

    init(
        warmAlarmDelegate: WarmAlarmDelegate,
        forwardingDelegate: UNUserNotificationCenterDelegate?,
        previousWarmAlarmDelegate: WarmAlarmNotificationCenterDelegate? = nil
    ) {
        self.warmAlarmDelegate = warmAlarmDelegate
        self.forwardingDelegate = forwardingDelegate
        previousWarmAlarmDelegates = previousWarmAlarmDelegate.map {
            [WeakDelegateReference($0)] + $0.previousWarmAlarmDelegates
        } ?? []
    }

    var restorationDelegate: UNUserNotificationCenterDelegate? {
        previousWarmAlarmDelegates.lazy.compactMap(\.delegate).first ?? forwardingDelegate
    }

    static func install(
        warmAlarmDelegate: WarmAlarmDelegate,
        on notificationCenter: UNUserNotificationCenter
    ) -> WarmAlarmNotificationCenterDelegate {
        installationLock.lock()
        defer { installationLock.unlock() }

        let installedDelegate = notificationCenter.delegate
        let previousWarmAlarmDelegate = installedDelegate as? WarmAlarmNotificationCenterDelegate
        let forwardingDelegate = if let previousWarmAlarmDelegate {
            previousWarmAlarmDelegate.forwardingDelegate
        } else {
            installedDelegate
        }
        let delegate = WarmAlarmNotificationCenterDelegate(
            warmAlarmDelegate: warmAlarmDelegate,
            forwardingDelegate: forwardingDelegate,
            previousWarmAlarmDelegate: previousWarmAlarmDelegate
        )
        notificationCenter.delegate = delegate
        return delegate
    }

    func uninstall(from notificationCenter: UNUserNotificationCenter) {
        Self.installationLock.lock()
        defer { Self.installationLock.unlock() }

        guard notificationCenter.delegate === self else { return }
        notificationCenter.delegate = restorationDelegate
    }

    func target(for content: UNNotificationContent) -> UNUserNotificationCenterDelegate? {
        if content.categoryIdentifier == WarmAlarmDelegate.categoryIdentifier {
            return warmAlarmDelegate
        }
        return forwardingDelegate
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard let target = target(for: notification.request.content),
              target.userNotificationCenter?(
                  center,
                  willPresent: notification,
                  withCompletionHandler: completionHandler
              ) != nil else {
            completionHandler([])
            return
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let target = target(for: response.notification.request.content),
              target.userNotificationCenter?(
                  center,
                  didReceive: response,
                  withCompletionHandler: completionHandler
              ) != nil else {
            completionHandler()
            return
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        forwardingDelegate?.userNotificationCenter?(center, openSettingsFor: notification)
    }
}
