import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DataStore.shared.prepareForTermination()
    }
}
