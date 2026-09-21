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
