import Flutter
import UIKit
import UserNotifications

public class WarmAlarmPlugin: NSObject, FlutterPlugin, WarmAlarmApi {
    private let delegate: WarmAlarmDelegate
    private static let killWarningNotifId = "warm_alarm_kill_warning_notif"
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(delegate: WarmAlarmDelegate) {
        self.delegate = delegate
        super.init()
        setupLifecycleObservers()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func setupLifecycleObservers() {
        let center = NotificationCenter.default
        // Scene-based apps (iOS 13+, UIApplicationSceneManifest declared): UIKit routes
        // foreground/background transitions through UISceneDelegate, not UIApplicationDelegate.
        lifecycleObservers.append(center.addObserver(
            forName: UIScene.willDeactivateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.postKillWarningIfNeeded() })
        lifecycleObservers.append(center.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelKillWarning() })
        // Legacy apps without UIApplicationSceneManifest.
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.postKillWarningIfNeeded() })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelKillWarning() })
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let binaryMessenger = registrar.messenger()
        let eventsApi = WarmAlarmEventsApi(binaryMessenger: binaryMessenger)
        let delegate = WarmAlarmDelegate(eventsApi: eventsApi)
        let instance = WarmAlarmPlugin(delegate: delegate)

        UNUserNotificationCenter.current().delegate = delegate
        WarmAlarmDelegate.registerCategories()
        WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
        registrar.publish(instance)
    }

    func initialize(completion: @escaping (Result<Void, Error>) -> Void) {
        let now = Date()
        let stored = WarmAlarmStore.shared.loadAll()
        let futureAlarms = stored.values.filter { data in
            Date(timeIntervalSince1970: Double(data.scheduledAtMillis) / 1000.0) > now
        }
        guard !futureAlarms.isEmpty else {
            completion(.success(()))
            return
        }
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let pendingIds = Set(pending.map { $0.identifier })
            for data in futureAlarms {
                let idStr = String(data.id)
                guard !pendingIds.contains(idStr) else { continue }
                let content = self.delegate.makeContent(from: data)
                let fireDate = Date(timeIntervalSince1970: Double(data.scheduledAtMillis) / 1000.0)
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: idStr, content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request) { _ in }
            }
            completion(.success(()))
        }
    }

    func getCapabilities(completion: @escaping (Result<WarmAlarmCapabilitiesWire, Error>) -> Void) {
        completion(.success(WarmAlarmCapabilitiesWire(
            exactScheduling: .limited,
            notificationScheduling: .supported,
            backgroundAudioPlayback: .limited,
            fullScreenPresentation: .unsupported,
            wakeCheck: .unsupported,
            liveActivity: .supported
        )))
    }

    func getPermissionState(completion: @escaping (Result<WarmAlarmPermissionStateWire, Error>) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            completion(.success(WarmAlarmPermissionStateWire(
                notificationsGranted: granted,
                exactAlarmGranted: false,
                fullScreenIntentGranted: false
            )))
        }
    }

    func getReadiness(completion: @escaping (Result<WarmAlarmReadinessWire, Error>) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            var reasons: [WarmAlarmReadinessReasonWire] = [.backgroundExecutionLimited]
            if !granted { reasons.insert(.notificationPermissionDenied, at: 0) }
            let level: WarmAlarmReadinessLevelWire = granted ? .limited : .blocked
            completion(.success(WarmAlarmReadinessWire(level: level, reasons: reasons)))
        }
    }

    func scheduleAlarm(
        schedule: WarmAlarmScheduleWire,
        completion: @escaping (Result<WarmAlarmScheduleResultWire, Error>) -> Void
    ) {
        WarmAlarmStore.shared.save(.from(wire: schedule))

        let content = delegate.makeContent(from: .from(wire: schedule))
        let fireDate = Date(timeIntervalSince1970: Double(schedule.scheduledAtMillis) / 1000.0)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: String(schedule.id), content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                WarmAlarmStore.shared.remove(id: schedule.id)
                self.delegate.emitFailure(alarmId: schedule.id, message: error.localizedDescription)
                completion(.success(WarmAlarmScheduleResultWire(
                    alarmId: schedule.id,
                    readiness: WarmAlarmReadinessWire(level: .limited, reasons: [.backgroundExecutionLimited]),
                    warning: WarmAlarmWarningWire(message: "Scheduling failed: \(error.localizedDescription)")
                )))
                return
            }
            self.delegate.emitScheduled(alarmId: schedule.id)
            self.getReadiness { result in
                let readiness = (try? result.get())
                    ?? WarmAlarmReadinessWire(level: .limited, reasons: [.backgroundExecutionLimited])
                completion(.success(WarmAlarmScheduleResultWire(
                    alarmId: schedule.id, readiness: readiness, warning: nil)))
            }
        }
    }

    func cancelAlarm(id: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
        WarmAlarmStore.shared.remove(id: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [String(id)])
        completion(.success(()))
    }

    func cancelAllAlarms(completion: @escaping (Result<Void, Error>) -> Void) {
        WarmAlarmStore.shared.clear()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        completion(.success(()))
    }

    func getScheduledAlarms(completion: @escaping (Result<[WarmAlarmSnapshotWire], Error>) -> Void) {
        let snapshots = WarmAlarmStore.shared.loadAll().map { _, data in
            WarmAlarmSnapshotWire(
                id: data.id,
                scheduledAtMillis: data.scheduledAtMillis,
                notification: WarmAlarmNotificationWire(
                    title: data.notificationTitle,
                    body: data.notificationBody,
                    stopActionTitle: data.stopActionTitle,
                    snoozeActionTitle: data.snoozeActionTitle,
                    keepNotificationAfterAlarmEnds: data.keepNotificationAfterAlarmEnds ?? false
                ),
                audio: WarmAlarmAudioWire(
                    filePath: data.filePath,
                    assetPath: data.assetPath,
                    loop: data.loop,
                    volume: data.volume,
                    fadeInDurationMillis: data.fadeInDurationMillis,
                    vibrate: data.vibrate,
                    volumeEnforced: data.volumeEnforced ?? false,
                    fadeSteps: data.fadeSteps?.map {
                        WarmAlarmVolumeFadeStepWire(timeMillis: $0.timeMillis, volume: $0.volume)
                    }
                ),
                recurrence: data.recurrenceWeekdays.map { WarmAlarmRecurrenceWire(weekdays: $0) },
                snooze: data.snoozeDurationMillis.map { WarmAlarmSnoozeWire(durationMillis: $0) },
                payload: data.payload
            )
        }
        completion(.success(snapshots))
    }

    func setKillWarning(
        title: String, body: String, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        UserDefaults.standard.setValue(["title": title, "body": body], forKey: "warm_alarm_kill_warning")
        completion(.success(()))
    }

    func clearKillWarning(completion: @escaping (Result<Void, Error>) -> Void) {
        UserDefaults.standard.removeObject(forKey: "warm_alarm_kill_warning")
        completion(.success(()))
    }

    func isRinging(alarmId: Int64?, completion: @escaping (Result<Bool, Error>) -> Void) {
        let playingId = delegate.currentlyPlayingAlarmId
        if let id = alarmId {
            completion(.success(playingId == id))
        } else {
            completion(.success(playingId != nil))
        }
    }

    private func postKillWarningIfNeeded() {
        guard delegate.currentlyPlayingAlarmId != nil,
              let dict = UserDefaults.standard.dictionary(forKey: "warm_alarm_kill_warning"),
              let title = dict["title"] as? String,
              let body = dict["body"] as? String
        else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(
            identifier: WarmAlarmPlugin.killWarningNotifId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private func cancelKillWarning() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [WarmAlarmPlugin.killWarningNotifId])
    }
}
