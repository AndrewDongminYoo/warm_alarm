import Foundation

public enum WarmAlarmLiveActivityDisplayStatus: String, Sendable {
    case scheduled
    case ringing
    case snoozed
}

public struct WarmAlarmLiveActivityState: Equatable, Sendable {
    public let alarmId: Int64
    public let title: String
    public let status: WarmAlarmLiveActivityDisplayStatus
    public let scheduledAt: Date?

    public init(
        alarmId: Int64,
        title: String,
        status: WarmAlarmLiveActivityDisplayStatus,
        scheduledAt: Date?
    ) {
        self.alarmId = alarmId
        self.title = title
        self.status = status
        self.scheduledAt = scheduledAt
    }
}

public protocol WarmAlarmLiveActivityAdapter: AnyObject {
    var activitiesEnabled: Bool { get }

    func start(
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<String, Error>) -> Void
    )

    func update(
        activityId: String,
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<Bool, Error>) -> Void
    )

    func end(
        activityId: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
}

private final class WarmAlarmLiveActivityRegistry: @unchecked Sendable {
    static let shared = WarmAlarmLiveActivityRegistry()

    private let lock = NSLock()
    private var registeredAdapter: WarmAlarmLiveActivityAdapter?

    func register(_ adapter: WarmAlarmLiveActivityAdapter) {
        lock.lock()
        registeredAdapter = adapter
        lock.unlock()
    }

    var adapter: WarmAlarmLiveActivityAdapter? {
        lock.lock()
        defer { lock.unlock() }
        return registeredAdapter
    }
}

public enum WarmAlarmLiveActivityHost {
    public static func register(adapter: WarmAlarmLiveActivityAdapter) {
        WarmAlarmLiveActivityRegistry.shared.register(adapter)
    }

    static var adapter: WarmAlarmLiveActivityAdapter? {
        WarmAlarmLiveActivityRegistry.shared.adapter
    }
}

enum WarmAlarmLiveActivityCapability: Equatable {
    case supported
    case limited
    case unsupported
}

enum WarmAlarmLiveActivityOperationStatus: Equatable {
    case completed
    case unsupported
    case disabled
    case notFound
}

struct WarmAlarmLiveActivityOperationResult: Equatable {
    let status: WarmAlarmLiveActivityOperationStatus
    let activityId: String?

    init(status: WarmAlarmLiveActivityOperationStatus, activityId: String? = nil) {
        self.status = status
        self.activityId = activityId
    }
}

final class WarmAlarmLiveActivityController {
    private let runtimeAvailable: Bool
    private let supportsLiveActivities: Bool
    private let liveActivityEnabled: Bool
    private let adapterProvider: () -> WarmAlarmLiveActivityAdapter?

    init(
        runtimeAvailable: Bool = WarmAlarmLiveActivityController.defaultRuntimeAvailable,
        supportsLiveActivities: Bool = Bundle.main.object(
            forInfoDictionaryKey: "NSSupportsLiveActivities"
        ) as? Bool ?? false,
        liveActivityEnabled: Bool = Bundle.main.object(
            forInfoDictionaryKey: "WarmAlarmLiveActivityEnabled"
        ) as? Bool ?? false,
        adapterProvider: @escaping () -> WarmAlarmLiveActivityAdapter? = { WarmAlarmLiveActivityHost.adapter }
    ) {
        self.runtimeAvailable = runtimeAvailable
        self.supportsLiveActivities = supportsLiveActivities
        self.liveActivityEnabled = liveActivityEnabled
        self.adapterProvider = adapterProvider
    }

    var capability: WarmAlarmLiveActivityCapability {
        switch route {
        case .unsupported:
            .unsupported
        case .disabled:
            .limited
        case .adapter:
            .supported
        }
    }

    func start(
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<WarmAlarmLiveActivityOperationResult, Error>) -> Void
    ) {
        switch route {
        case .unsupported:
            completion(.success(WarmAlarmLiveActivityOperationResult(status: .unsupported)))
        case .disabled:
            completion(.success(WarmAlarmLiveActivityOperationResult(status: .disabled)))
        case let .adapter(adapter):
            adapter.start(state: state) { result in
                completion(result.map {
                    WarmAlarmLiveActivityOperationResult(status: .completed, activityId: $0)
                })
            }
        }
    }

    func update(
        activityId: String,
        state: WarmAlarmLiveActivityState,
        completion: @escaping (Result<WarmAlarmLiveActivityOperationResult, Error>) -> Void
    ) {
        switch route {
        case .unsupported:
            completion(.success(WarmAlarmLiveActivityOperationResult(status: .unsupported)))
        case .disabled:
            completion(.success(WarmAlarmLiveActivityOperationResult(status: .disabled)))
        case let .adapter(adapter):
            adapter.update(activityId: activityId, state: state) { result in
                completion(result.map {
                    WarmAlarmLiveActivityOperationResult(status: $0 ? .completed : .notFound)
                })
            }
        }
    }

    func end(
        activityId: String,
        completion: @escaping (Result<WarmAlarmLiveActivityOperationResult, Error>) -> Void
    ) {
        switch route {
        case .unsupported:
            completion(.success(WarmAlarmLiveActivityOperationResult(status: .unsupported)))
        case .disabled:
            completion(.success(WarmAlarmLiveActivityOperationResult(status: .disabled)))
        case let .adapter(adapter):
            adapter.end(activityId: activityId) { result in
                completion(result.map {
                    WarmAlarmLiveActivityOperationResult(status: $0 ? .completed : .notFound)
                })
            }
        }
    }

    private var route: Route {
        guard runtimeAvailable, supportsLiveActivities, liveActivityEnabled, let adapter = adapterProvider() else {
            return .unsupported
        }
        return adapter.activitiesEnabled ? .adapter(adapter) : .disabled
    }

    private enum Route {
        case unsupported
        case disabled
        case adapter(WarmAlarmLiveActivityAdapter)
    }

    private static var defaultRuntimeAvailable: Bool {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.2, *) {
            return true
        }
        #endif
        return false
    }
}
