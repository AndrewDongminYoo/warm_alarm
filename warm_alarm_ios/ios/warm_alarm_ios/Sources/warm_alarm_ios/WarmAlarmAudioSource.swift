import Foundation

enum WarmAlarmAudioSource: Equatable {
    case file(String)
    case asset(String)
    case none

    static func select(filePath: String?, assetPath: String?) -> WarmAlarmAudioSource {
        if let filePath, !filePath.isEmpty {
            return .file(filePath)
        }
        if let assetPath, !assetPath.isEmpty {
            return .asset(assetPath)
        }
        return .none
    }
}

enum WarmAlarmFadeRamp {
    private static let maxSteps: Int64 = 10
    private static let minStepMillis: Int64 = 100

    /// Returns the volume points the plugin player plays.
    /// Explicit `fadeSteps` win. Otherwise a positive `fadeInDurationMillis` becomes a linear ramp from silence at 0 ms
    /// to `volume`, or to 1.0 when `volume` is nil. The ramp uses 10 steps or one step per 100 ms, whichever is fewer.
    static func resolve(fadeSteps: [FadeStep]?, fadeInDurationMillis: Int64?, volume: Double?) -> [FadeStep]? {
        if let fadeSteps { return fadeSteps }
        guard let duration = fadeInDurationMillis, duration > 0 else { return nil }
        let target = max(0.0, min(1.0, volume ?? 1.0))
        let count = max(1, min(maxSteps, duration / minStepMillis))
        return (0...count).map { index in
            FadeStep(
                timeMillis: duration * index / count,
                volume: index == count ? target : target * Double(index) / Double(count)
            )
        }
    }

    /// Returns when the volume enforcer starts, in milliseconds after playback starts.
    /// The enforcer sets the player volume to 1.0 every second, so it waits for the last fade step instead of
    /// interrupting the fade.
    static func volumeEnforcerStartMillis(for steps: [FadeStep]?) -> Int64 {
        max(0, steps?.last?.timeMillis ?? 0)
    }
}
