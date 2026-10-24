import Flutter
import UIKit
import Network
import AVFAudio

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var deviceConditions: DeviceConditionsBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let messenger = registrar(forPlugin: "DeviceConditionsBridge")?.messenger() {
      deviceConditions = DeviceConditionsBridge(messenger: messenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class DeviceConditionsBridge: NSObject, FlutterStreamHandler {
  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "hutube.device_conditions")
  private var sink: FlutterEventSink?
  private var routeObserver: NSObjectProtocol?
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var connected = false
  private var wifi = false

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "hutube/device_conditions", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "hutube/device_conditions/events", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      guard call.method == "snapshot" else { result(FlutterMethodNotImplemented); return }
      result(self?.snapshot())
    }
    events.setStreamHandler(self)
    monitor.pathUpdateHandler = { [weak self] path in
      DispatchQueue.main.async {
        self?.connected = path.status == .satisfied
        self?.wifi = path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.cellular)
        self?.emit()
      }
    }
    monitor.start(queue: queue)
    routeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.emit() }
  }
  private func snapshot() -> [String: Bool] {
    let external = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
      ![AVAudioSession.Port.builtInSpeaker, .builtInReceiver].contains($0.portType)
    }
    return ["connected": connected, "wifi": wifi, "externalAudio": external]
  }
  private func emit() { sink?(snapshot()) }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    emit()
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
  deinit {
    monitor.cancel()
    if let observer = routeObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
