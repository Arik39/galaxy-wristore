import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // The app is laid out for a phone, so it opens in a phone-shaped window that fits the screen.
    let available = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1280, height: 900)
    self.setContentSize(NSSize(width: 430, height: min(880, available.height - 60)))
    self.contentMinSize = NSSize(width: 360, height: 600)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
