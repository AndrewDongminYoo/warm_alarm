import Foundation

protocol WarmAlarmEventQueueStorage: AnyObject {
    func read() -> Data?
    func write(_ data: Data) -> Bool
}

/// Atomically replaces the queue file before reporting success. This covers process termination after return, not power loss.
final class FileWarmAlarmEventQueueStorage: WarmAlarmEventQueueStorage, @unchecked Sendable {
    private static let fileName = "event_queue_v1.json"
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    convenience init(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) {
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let namespace = bundle.bundleIdentifier ?? "dev.flutter.pigeon.warm_alarm.host"
        let fileURL = applicationSupportDirectory
            .appendingPathComponent(namespace, isDirectory: true)
            .appendingPathComponent("warm_alarm", isDirectory: true)
            .appendingPathComponent(Self.fileName)
        self.init(fileURL: fileURL, fileManager: fileManager)
    }

    func read() -> Data? {
        try? Data(contentsOf: fileURL)
    }

    func write(_ data: Data) -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: directory.path
            )
            try data.write(to: fileURL, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }
}

struct QueuedWarmAlarmEvent {
    let occurrenceID: String
    let event: WarmAlarmEventWire
}

/// A persistent FIFO. At 64 entries, enqueue drops the oldest occurrence.
final class WarmAlarmEventQueueStore: @unchecked Sendable {
    static let defaultCapacity = 64

    private let storage: WarmAlarmEventQueueStorage
    private let capacity: Int
    private let occurrenceID: () -> String
    private static let storageLock = NSLock()

    init(
        storage: WarmAlarmEventQueueStorage = FileWarmAlarmEventQueueStorage(),
        capacity: Int = defaultCapacity,
        occurrenceID: @escaping () -> String = { UUID().uuidString }
    ) {
        precondition(capacity > 0)
        self.storage = storage
        self.capacity = capacity
        self.occurrenceID = occurrenceID
    }

    func enqueue(_ event: WarmAlarmEventWire) -> Bool {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        var events = readAndRepair()
        events.append(QueuedWarmAlarmEvent(occurrenceID: occurrenceID(), event: event))
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
        return persist(events)
    }

    func loadAll() -> [QueuedWarmAlarmEvent] {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        return readAndRepair()
    }

    func remove(occurrenceID: String) -> Bool {
        Self.storageLock.lock()
        defer { Self.storageLock.unlock() }
        let events = readAndRepair()
        let retained = events.filter { $0.occurrenceID != occurrenceID }
        guard retained.count != events.count else { return true }
        return persist(retained)
    }

    private func readAndRepair() -> [QueuedWarmAlarmEvent] {
        guard let data = storage.read() else { return [] }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (root["version"] as? NSNumber)?.intValue == 1,
            let rawEvents = root["events"] as? [Any]
        else {
            _ = persist([])
            return []
        }

        let valid = rawEvents.compactMap { raw -> QueuedWarmAlarmEvent? in
            guard let dictionary = raw as? [String: Any] else { return nil }
            return decode(dictionary)
        }
        if valid.count != rawEvents.count {
            _ = persist(valid)
        }
        return valid
    }

    private func persist(_ events: [QueuedWarmAlarmEvent]) -> Bool {
        let root: [String: Any] = [
            "version": 1,
            "events": events.map(encode),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else {
            return false
        }
        return storage.write(data)
    }

    private func encode(_ queued: QueuedWarmAlarmEvent) -> [String: Any] {
        var value: [String: Any] = [
            "occurrenceId": queued.occurrenceID,
            "alarmId": queued.event.alarmId,
            "type": eventTypeName(queued.event.type),
            "occurredAtMillis": queued.event.occurredAtMillis,
        ]
        value["snoozeDurationMillis"] = queued.event.snoozeDurationMillis.map { $0 as Any } ?? NSNull()
        value["payload"] = queued.event.payload.map { $0 as Any } ?? NSNull()
        value["failureCode"] = queued.event.failure.map { $0.code.rawValue as Any } ?? NSNull()
        value["failureMessage"] = queued.event.failure?.message.map { $0 as Any } ?? NSNull()
        return value
    }

    private func decode(_ value: [String: Any]) -> QueuedWarmAlarmEvent? {
        guard
            let occurrenceID = value["occurrenceId"] as? String,
            !occurrenceID.isEmpty,
            let alarmID = (value["alarmId"] as? NSNumber)?.int64Value,
            let occurredAtMillis = (value["occurredAtMillis"] as? NSNumber)?.int64Value,
            let type = decodeEventType(value["type"])
        else {
            return nil
        }

        let failure: WarmAlarmFailureWire?
        if value["failureCode"] is NSNull || value["failureCode"] == nil {
            failure = nil
        } else {
            guard
                let rawCode = (value["failureCode"] as? NSNumber)?.intValue,
                let code = WarmAlarmFailureCodeWire(rawValue: rawCode)
            else {
                return nil
            }
            failure = WarmAlarmFailureWire(
                code: code,
                message: value["failureMessage"] as? String
            )
        }

        return QueuedWarmAlarmEvent(
            occurrenceID: occurrenceID,
            event: WarmAlarmEventWire(
                alarmId: alarmID,
                type: type,
                occurredAtMillis: occurredAtMillis,
                snoozeDurationMillis: (value["snoozeDurationMillis"] as? NSNumber)?.int64Value,
                failure: failure,
                payload: value["payload"] as? String
            )
        )
    }

    private func eventTypeName(_ type: WarmAlarmEventTypeWire) -> String {
        switch type {
        case .scheduled: "scheduled"
        case .fired: "fired"
        case .stopped: "stopped"
        case .snoozed: "snoozed"
        case .failed: "failed"
        }
    }

    private func decodeEventType(_ raw: Any?) -> WarmAlarmEventTypeWire? {
        if let rawValue = (raw as? NSNumber)?.intValue {
            return WarmAlarmEventTypeWire(rawValue: rawValue)
        }
        guard let name = raw as? String else { return nil }
        switch name {
        case "scheduled": return .scheduled
        case "fired": return .fired
        case "stopped": return .stopped
        case "snoozed": return .snoozed
        case "failed": return .failed
        default: return nil
        }
    }
}

final class WarmAlarmEventQueue: @unchecked Sendable {
    private let store: WarmAlarmEventQueueStore
    private let emit: (WarmAlarmEventWire, @escaping (Bool) -> Void) -> Void
    private let lock = NSLock()
    private var isDraining = false

    init(
        store: WarmAlarmEventQueueStore = WarmAlarmEventQueueStore(),
        emit: @escaping (WarmAlarmEventWire, @escaping (Bool) -> Void) -> Void
    ) {
        self.store = store
        self.emit = emit
    }

    @discardableResult
    func enqueue(_ event: WarmAlarmEventWire) -> Bool {
        guard store.enqueue(event) else { return false }
        drain()
        return true
    }

    func drain() {
        lock.lock()
        guard !isDraining else {
            lock.unlock()
            return
        }
        isDraining = true
        lock.unlock()
        emitNext()
    }

    private func emitNext() {
        guard let pending = store.loadAll().first else {
            stopDraining()
            return
        }
        emit(pending.event) { [weak self] succeeded in
            guard let self else { return }
            guard succeeded, self.store.remove(occurrenceID: pending.occurrenceID) else {
                self.stopDraining()
                return
            }
            self.emitNext()
        }
    }

    private func stopDraining() {
        lock.lock()
        isDraining = false
        lock.unlock()
    }
}
