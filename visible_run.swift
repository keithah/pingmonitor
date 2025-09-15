#!/usr/bin/swift

import SwiftUI
import AppKit
import Foundation

// Simple test to ensure menu bar visibility
class SimpleMenuBarController {
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var pingCount = 0

    init() {
        print("🚀 Starting PingMonitor...")
        setupMenuBar()
        startPinging()
    }

    private func setupMenuBar() {
        // Create status item with fixed length first
        statusItem = NSStatusBar.system.statusItem(withLength: 60)

        guard let statusItem = statusItem, let button = statusItem.button else {
            print("❌ Failed to create status item")
            return
        }

        print("✅ Status item created")

        // Set initial text to make sure it's visible
        button.title = "🟢 --"
        button.action = #selector(menuClicked)
        button.target = self

        // Make sure it's visible
        button.isEnabled = true
        button.toolTip = "PingMonitor - Click for details"

        print("✅ Menu bar button configured")
    }

    private func startPinging() {
        print("⚡ Starting ping timer...")
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            self.performPing()
        }
        performPing() // Do first ping immediately
    }

    private func performPing() {
        pingCount += 1
        print("📍 Performing ping #\(pingCount)...")

        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-t", "3", "8.8.8.8"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                var pingTime: Double?
                var status = "❌"

                if process.terminationStatus == 0 {
                    // Extract ping time
                    let pattern = "time=([0-9.]+)"
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
                       let range = Range(match.range(at: 1), in: output) {
                        pingTime = Double(output[range])

                        if let time = pingTime {
                            status = time < 50 ? "🟢" : time < 150 ? "🟡" : "🔴"
                            print("✅ Ping successful: \(time)ms")
                        }
                    }
                } else {
                    print("❌ Ping failed with exit code: \(process.terminationStatus)")
                }

                DispatchQueue.main.async {
                    self.updateDisplay(pingTime: pingTime, status: status)
                }
            } catch {
                print("❌ Ping error: \(error)")
                DispatchQueue.main.async {
                    self.updateDisplay(pingTime: nil, status: "❌")
                }
            }
        }
    }

    private func updateDisplay(pingTime: Double?, status: String) {
        guard let button = statusItem?.button else {
            print("❌ No button to update")
            return
        }

        let timeText = pingTime != nil ? String(format: "%.0fms", pingTime!) : "--"
        let displayText = "\(status)\n\(timeText)"

        // Create attributed string for vertical layout
        let attributedString = NSMutableAttributedString()

        // Add emoji with larger font
        let emojiAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12)
        ]
        attributedString.append(NSAttributedString(string: status, attributes: emojiAttributes))

        // Add newline
        attributedString.append(NSAttributedString(string: "\n"))

        // Add time with smaller font
        let timeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        ]
        attributedString.append(NSAttributedString(string: timeText, attributes: timeAttributes))

        button.attributedTitle = attributedString

        print("🔄 Display updated: \(status) \(timeText)")
    }

    @objc private func menuClicked() {
        print("👆 Menu clicked!")

        let alert = NSAlert()
        alert.messageText = "PingMonitor Status"
        alert.informativeText = """
        Host: 8.8.8.8 (Google DNS)
        Pings performed: \(pingCount)

        This is a simple version - click OK and check your menu bar!
        The status should show as: [emoji][newline][ping time]
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            print("👋 Quitting...")
            NSApplication.shared.terminate(nil)
        }
    }
}

// Main execution with detailed logging
print("🎯 PingMonitor Starting...")
print("📊 macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

print("🔧 Creating menu bar controller...")
let controller = SimpleMenuBarController()

print("▶️  Starting application run loop...")
app.run()