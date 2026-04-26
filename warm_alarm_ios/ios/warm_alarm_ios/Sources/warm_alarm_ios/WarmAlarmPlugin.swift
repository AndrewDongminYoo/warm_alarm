import Flutter

public class WarmAlarmPlugin: NSObject, FlutterPlugin, WarmAlarmApi {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let binaryMessenger = registrar.messenger()
    let instance = WarmAlarmPlugin()
    WarmAlarmApiSetup.setUp(binaryMessenger: binaryMessenger, api: instance)
    registrar.publish(instance)
  }

  func getPlatformName(completion: @escaping (Result<String?, Error>) -> Void) {
    completion(.success("iOS"))
  }
}
