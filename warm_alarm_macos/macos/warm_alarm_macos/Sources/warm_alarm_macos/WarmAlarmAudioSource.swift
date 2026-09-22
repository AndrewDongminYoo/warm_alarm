import Foundation

enum WarmAlarmAudioSource: Equatable {
    case file(String)
    case asset(String)
    case none

    static func assetURL(for asset: String, in bundle: Bundle = .main) -> URL? {
        if let frameworkAsset = bundle.privateFrameworksURL?
            .appendingPathComponent("App.framework/Resources/flutter_assets")
            .appendingPathComponent(asset),
            FileManager.default.fileExists(atPath: frameworkAsset.path)
        {
            return frameworkAsset
        }
        return bundle.url(forResource: "flutter_assets/\(asset)", withExtension: nil)
    }

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
