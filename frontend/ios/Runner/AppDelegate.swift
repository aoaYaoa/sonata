import Flutter
import ObjectiveC.runtime
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    disableTouchRateCorrectionVSyncCrashPath()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func disableTouchRateCorrectionVSyncCrashPath() {
    let selector = NSSelectorFromString("createTouchRateCorrectionVSyncClientIfNeeded")
    guard let method = class_getInstanceMethod(FlutterViewController.self, selector) else {
      return
    }

    // iOS 26.x can crash inside Flutter's touch-rate correction VSync client setup
    // on ProMotion devices. Replacing the setup hook with a no-op keeps startup stable.
    let replacement: @convention(block) (AnyObject) -> Void = { _ in }
    method_setImplementation(method, imp_implementationWithBlock(replacement))
  }
}
