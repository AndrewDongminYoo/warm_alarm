import XCTest

@testable import warm_alarm_macos

final class WarmAlarmEventQueueTests: XCTestCase {
    func testFileStorageSurvivesRecreationAndPersistsRemovalAfterAck() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("event-queue.json")
        let event = makeEvent(alarmID: 42)

        let initialStore = WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(fileURL: fileURL))
        XCTAssertTrue(initialStore.enqueue(event))

        let restoredStore = WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(fileURL: fileURL))
        XCTAssertEqual(restoredStore.loadAll().map(\.event.alarmId), [42])
        var replayed = [Int64]()
        let replay = WarmAlarmEventQueue(store: restoredStore) { replayedEvent, callback in
            replayed.append(replayedEvent.alarmId)
            callback(true)
        }
        replay.drain()

        XCTAssertEqual(replayed, [42])
        let afterAckStore = WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(fileURL: fileURL))
        XCTAssertTrue(afterAckStore.loadAll().isEmpty)
    }

    func testUnwritableDirectoryRejectsEnqueueWithoutReplacingPreviousDataOrEmitting() throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("event-queue.json")
        let store = WarmAlarmEventQueueStore(storage: FileWarmAlarmEventQueueStorage(fileURL: fileURL))
        XCTAssertTrue(store.enqueue(makeEvent(alarmID: 1)))
        let previousData = try Data(contentsOf: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        var emitted = [Int64]()
        let queue = WarmAlarmEventQueue(store: store) { event, _ in emitted.append(event.alarmId) }

        XCTAssertFalse(queue.enqueue(makeEvent(alarmID: 2)))

        XCTAssertTrue(emitted.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fileURL), previousData)
    }

    func testStorePreservesFIFOAndDuplicateOccurrencesAcrossRecreation() {
        let storage = MemoryWarmAlarmEventQueueStorage()
        var identifiers = ["occurrence-1", "occurrence-2"]
        let event = makeEvent(alarmID: 42)
        let store = WarmAlarmEventQueueStore(storage: storage, occurrenceID: { identifiers.removeFirst() })

        XCTAssertTrue(store.enqueue(event))
        XCTAssertTrue(store.enqueue(event))

        let restored = WarmAlarmEventQueueStore(storage: storage).loadAll()
        XCTAssertEqual(restored.map(\.occurrenceID), ["occurrence-1", "occurrence-2"])
        XCTAssertEqual(restored.map(\.event.alarmId), [42, 42])
    }

    func testStoreDropsOldestOccurrenceAtCapacity() {
        let storage = MemoryWarmAlarmEventQueueStorage()
        var identifiers = ["1", "2", "3"]
        let store = WarmAlarmEventQueueStore(
            storage: storage,
            capacity: 2,
            occurrenceID: { identifiers.removeFirst() }
        )

        XCTAssertTrue(store.enqueue(makeEvent(alarmID: 1)))
        XCTAssertTrue(store.enqueue(makeEvent(alarmID: 2)))
        XCTAssertTrue(store.enqueue(makeEvent(alarmID: 3)))

        XCTAssertEqual(store.loadAll().map(\.event.alarmId), [2, 3])
    }

    func testStoreRepairsCorruptRootAndCorruptRecords() throws {
        let corruptRoot = MemoryWarmAlarmEventQueueStorage(Data("not-json".utf8))
        XCTAssertTrue(WarmAlarmEventQueueStore(storage: corruptRoot).loadAll().isEmpty)
        XCTAssertEqual(String(data: try XCTUnwrap(corruptRoot.data), encoding: .utf8), "{\"events\":[],\"version\":1}")

        let records = MemoryWarmAlarmEventQueueStorage(Data("""
        {"version":1,"events":[{"occurrenceId":"bad"},{"occurrenceId":"good","alarmId":7,"type":"fired","occurredAtMillis":1000}]}
        """.utf8))
        let loaded = WarmAlarmEventQueueStore(storage: records).loadAll()
        XCTAssertEqual(loaded.map(\.occurrenceID), ["good"])
        XCTAssertEqual(loaded.map(\.event.alarmId), [7])
        XCTAssertFalse(String(data: try XCTUnwrap(records.data), encoding: .utf8)?.contains("bad") == true)
    }

    func testDrainRemovesOnlySuccessfulHeadAndRetriesFailureOnNextEnqueue() {
        let storage = MemoryWarmAlarmEventQueueStorage()
        var nextID = 0
        let store = WarmAlarmEventQueueStore(storage: storage, occurrenceID: {
            nextID += 1
            return "id-\(nextID)"
        })
        var callbacks = [(Bool) -> Void]()
        var emitted = [Int64]()
        let queue = WarmAlarmEventQueue(store: store) { event, callback in
            emitted.append(event.alarmId)
            callbacks.append(callback)
        }

        XCTAssertTrue(queue.enqueue(makeEvent(alarmID: 1)))
        XCTAssertTrue(queue.enqueue(makeEvent(alarmID: 2)))
        XCTAssertEqual(emitted, [1])

        callbacks.removeFirst()(false)
        XCTAssertEqual(store.loadAll().map(\.event.alarmId), [1, 2])

        XCTAssertTrue(queue.enqueue(makeEvent(alarmID: 3)))
        XCTAssertEqual(emitted, [1, 1])
        callbacks.removeFirst()(true)
        XCTAssertEqual(emitted, [1, 1, 2])
        callbacks.removeFirst()(true)
        XCTAssertEqual(emitted, [1, 1, 2, 3])
        callbacks.removeFirst()(true)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    func testSuccessfulCallbackReplaysAfterRemovalWriteFailsThenPersistsTheNextAck() {
        let storage = MemoryWarmAlarmEventQueueStorage()
        let initialStore = WarmAlarmEventQueueStore(storage: storage)
        let initialQueue = WarmAlarmEventQueue(store: initialStore) { _, callback in
            storage.rejectsWrites = true
            callback(true)
        }

        XCTAssertTrue(initialQueue.enqueue(makeEvent(alarmID: 42)))
        XCTAssertEqual(initialStore.loadAll().map(\.event.alarmId), [42])

        storage.rejectsWrites = false
        let restoredStore = WarmAlarmEventQueueStore(storage: storage)
        var replayed = [Int64]()
        let restoredQueue = WarmAlarmEventQueue(store: restoredStore) { event, callback in
            replayed.append(event.alarmId)
            callback(true)
        }
        restoredQueue.drain()

        XCTAssertEqual(replayed, [42])
        XCTAssertTrue(WarmAlarmEventQueueStore(storage: storage).loadAll().isEmpty)
    }

    func testSuccessfulAckContinuesAfterCapacityEvictsTheInFlightHead() {
        let store = WarmAlarmEventQueueStore(storage: MemoryWarmAlarmEventQueueStorage(), capacity: 2)
        var callbacks = [(Bool) -> Void]()
        var emitted = [Int64]()
        let queue = WarmAlarmEventQueue(store: store) { event, callback in
            emitted.append(event.alarmId)
            callbacks.append(callback)
        }

        XCTAssertTrue(queue.enqueue(makeEvent(alarmID: 1)))
        XCTAssertTrue(queue.enqueue(makeEvent(alarmID: 2)))
        XCTAssertTrue(queue.enqueue(makeEvent(alarmID: 3)))
        XCTAssertEqual(store.loadAll().map(\.event.alarmId), [2, 3])

        callbacks.removeFirst()(true)
        XCTAssertEqual(emitted, [1, 2])
        callbacks.removeFirst()(true)
        XCTAssertEqual(emitted, [1, 2, 3])
        callbacks.removeFirst()(true)
        XCTAssertTrue(store.loadAll().isEmpty)
    }

    private func makeEvent(alarmID: Int64) -> WarmAlarmEventWire {
        WarmAlarmEventWire(alarmId: alarmID, type: .fired, occurredAtMillis: 1_000, payload: "payload")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class MemoryWarmAlarmEventQueueStorage: WarmAlarmEventQueueStorage {
    var data: Data?
    var rejectsWrites = false

    init(_ data: Data? = nil) {
        self.data = data
    }

    func read() -> Data? { data }

    func write(_ data: Data) -> Bool {
        if rejectsWrites { return false }
        self.data = data
        return true
    }
}
