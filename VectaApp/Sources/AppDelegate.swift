import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenuBuilder.build()
  }
}
