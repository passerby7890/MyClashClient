import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 強制啟用 macOS 深色外觀 (Dark Aqua)
    self.appearance = NSAppearance(named: .darkAqua)

    // 設定沉浸式透明標題列與科技深色背景
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.backgroundColor = NSColor(red: 0.04, green: 0.06, blue: 0.11, alpha: 1.0)

    // 鎖定初始視窗尺寸為 1200 x 780 並置中，設定最小邊界 1120 x 740
    self.setContentSize(NSSize(width: 1200, height: 780))
    self.minSize = NSSize(width: 1120, height: 740)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

