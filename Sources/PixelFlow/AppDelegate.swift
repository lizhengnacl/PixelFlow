import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MenuBarController()
        controller.start()
        menuBarController = controller
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
    }
}
