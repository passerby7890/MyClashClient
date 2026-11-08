import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    // Fail-safe cleanup: Reset system proxy and terminate engine
    let proxyResetScript = """
    for service in $(networksetup -listallnetworkservices | tail -n +2); do
      networksetup -setsocksfirewallproxystate "$service" off 2>/dev/null || true
      networksetup -setwebproxystate "$service" off 2>/dev/null || true
      networksetup -setsecurewebproxystate "$service" off 2>/dev/null || true
    done
    killall -9 tianhe_engine 2>/dev/null || true
    """
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", proxyResetScript]
    try? task.run()
    task.waitUntilExit()
  }
}
