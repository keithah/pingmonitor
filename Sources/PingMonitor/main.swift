import SwiftUI

@main
struct PingMonitorApp: App {
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}