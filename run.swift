#!/usr/bin/swift

import SwiftUI
import AppKit
import Foundation

// Simple Ping Service for demonstration
class SimplePingService: ObservableObject {
    @Published var latestPingTime: Double?
    @Published var status: String = "Good"
    private var timer: Timer?

    func startPinging() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.performPing()
        }
        performPing()
    }

    func stopPinging() {
        timer?.invalidate()
        timer = nil
    }

    private func performPing() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "5", "8.8.8.8"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if let pingTime = extractPingTime(from: output) {
                    DispatchQueue.main.async {
                        self.latestPingTime = pingTime
                        self.status = pingTime < 50 ? "Good" : pingTime < 150 ? "Warning" : "Error"
                    }
                } else {
                    DispatchQueue.main.async {
                        self.latestPingTime = nil
                        self.status = "Timeout"
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.latestPingTime = nil
                    self.status = "Error"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.latestPingTime = nil
                self.status = "Error"
            }
        }
    }

    private func extractPingTime(from output: String) -> Double? {
        let pattern = "time=([0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let timeRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[timeRange])
    }
}

// Menu Bar Controller
class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var pingService = SimplePingService()

    init() {
        setupMenuBar()
        pingService.startPinging()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateDisplay()

            // Set up timer to update display
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                self.updateDisplay()
            }

            // Simple click action
            button.action = #selector(showInfo)
            button.target = self
        }
    }

    private func updateDisplay() {
        guard let button = statusItem?.button else { return }

        let statusDot = getStatusDot()
        let pingText = pingService.latestPingTime != nil ?
            String(format: " %.0fms", pingService.latestPingTime!) : " --"

        button.title = statusDot + pingText
    }

    private func getStatusDot() -> String {
        switch pingService.status {
        case "Good": return "🟢"
        case "Warning": return "🟡"
        case "Error": return "🔴"
        default: return "⚫"
        }
    }

    @objc private func showInfo() {
        let alert = NSAlert()
        alert.messageText = "PingMonitor"
        alert.informativeText = "Status: \(pingService.status)\nPing: \(pingService.latestPingTime?.description ?? "N/A") ms\nHost: 8.8.8.8"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// Main App
struct PingMonitorApp: App {
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// Run the app
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // This makes it a menu bar app
let _ = MenuBarController()
app.run()