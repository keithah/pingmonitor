#!/usr/bin/swift

import SwiftUI
import AppKit
import Foundation

// Simple debug version to ensure visibility
class DebugMenuBarController {
    private var statusItem: NSStatusItem?
    private var pingTimer: Timer?
    private var pingCount = 0

    init() {
        print("🚀 Debug PingMonitor Starting...")
        setupMenuBar()
        startPinging()
        print("✅ Setup complete - check your menu bar!")
    }

    private func setupMenuBar() {
        print("📱 Creating status item...")

        // Try creating with variable length first
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else {
            print("❌ Failed to create status item")
            return
        }

        guard let button = statusItem.button else {
            print("❌ Failed to get status item button")
            return
        }

        print("✅ Status item and button created successfully")

        // Set a very visible initial title to ensure it appears
        button.title = "🟢TEST"
        button.action = #selector(menuClicked)
        button.target = self
        button.toolTip = "PingMonitor Debug - Working!"

        print("✅ Initial title set: 🟢TEST")

        // Force refresh
        statusItem.button?.needsDisplay = true

        print("🔄 Menu bar item should now be visible as '🟢TEST'")
    }

    private func startPinging() {
        print("⏰ Starting ping timer (every 3 seconds)...")
        pingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.performPing()
        }

        // Do first ping after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.performPing()
        }
    }

    private func performPing() {
        pingCount += 1
        print("🏓 Ping #\(pingCount) starting...")

        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-t", "3", "8.8.8.8"]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if let pingTime = self.extractPingTime(from: output) {
                        print("✅ Ping successful: \(pingTime)ms")
                        DispatchQueue.main.async {
                            self.updateDisplay(pingTime: pingTime)
                        }
                        return
                    }
                }

                print("❌ Ping failed")
                DispatchQueue.main.async {
                    self.updateDisplay(pingTime: nil)
                }
            } catch {
                print("❌ Ping error: \(error)")
                DispatchQueue.main.async {
                    self.updateDisplay(pingTime: nil)
                }
            }
        }
    }

    private func updateDisplay(pingTime: Double?) {
        guard let button = statusItem?.button else {
            print("❌ No button to update")
            return
        }

        let status = pingTime != nil ? (pingTime! < 50 ? "🟢" : pingTime! < 150 ? "🟡" : "🔴") : "⚫"
        let timeText = pingTime != nil ? String(format: "%.0fms", pingTime!) : "--"

        // Create the display exactly like your reference
        let attributedString = NSMutableAttributedString()

        // Add status emoji (slightly larger)
        let emojiAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .regular)
        ]
        attributedString.append(NSAttributedString(string: status, attributes: emojiAttributes))

        // Add newline
        attributedString.append(NSAttributedString(string: "\n"))

        // Add ping time (smaller, below)
        let timeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        attributedString.append(NSAttributedString(string: timeText, attributes: timeAttributes))

        // Center everything
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 0

        attributedString.addAttribute(.paragraphStyle,
                                    value: paragraphStyle,
                                    range: NSRange(location: 0, length: attributedString.length))

        button.attributedTitle = attributedString

        // Force update the display
        button.needsDisplay = true

        print("🔄 Display updated: \(status) \(timeText)")
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

    @objc private func menuClicked() {
        print("👆 Menu bar item clicked!")

        let alert = NSAlert()
        alert.messageText = "PingMonitor Debug"
        alert.informativeText = """
        ✅ App is working correctly!

        Pings completed: \(pingCount)
        Target: 8.8.8.8 (Google DNS)

        The menu bar should show:
        - Status emoji on top
        - Ping time below in smaller text

        Click 'Quit' to stop the app.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            print("👋 User chose to quit")
            NSApplication.shared.terminate(nil)
        }
    }
}

// Main execution
print("🎯 Starting Debug PingMonitor...")
print("💻 This version will show 'TEST' initially, then update with real ping data")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = DebugMenuBarController()

print("▶️  App is now running - look for '🟢TEST' in your menu bar")
print("📍 It will update to show real ping data within a few seconds")

app.run()