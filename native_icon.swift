#!/usr/bin/swift

import SwiftUI
import AppKit
import Foundation
import Combine

// Data Models
struct PingResult: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let host: String
    let pingTime: Double?
    let status: PingStatus
}

enum PingStatus {
    case good, warning, error, timeout

    var color: NSColor {
        switch self {
        case .good: return .systemGreen
        case .warning: return .systemYellow
        case .error: return .systemRed
        case .timeout: return .systemGray
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .good: return .green
        case .warning: return .yellow
        case .error: return .red
        case .timeout: return .gray
        }
    }
}

struct Host: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    var isActive: Bool = false
}

// Ping Service
class PingService: ObservableObject {
    @Published var latestResult: PingResult?
    @Published var pingHistory: [PingResult] = []
    @Published var currentHost: Host?
    private var timer: Timer?

    func startPinging(host: Host) {
        stopPinging()
        currentHost = host
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.performPing(host: host)
        }
        performPing(host: host)
    }

    func stopPinging() {
        timer?.invalidate()
        timer = nil
    }

    private func performPing(host: Host) {
        DispatchQueue.global(qos: .background).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-t", "3", host.address]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let result: PingResult
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if let pingTime = self.extractPingTime(from: output) {
                        let status: PingStatus = pingTime < 50 ? .good : pingTime < 150 ? .warning : .error
                        result = PingResult(host: host.address, pingTime: pingTime, status: status)
                    } else {
                        result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                    }
                } else {
                    result = PingResult(host: host.address, pingTime: nil, status: .error)
                }

                DispatchQueue.main.async {
                    self.latestResult = result
                    self.pingHistory.insert(result, at: 0)
                    if self.pingHistory.count > 100 {
                        self.pingHistory.removeLast()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let result = PingResult(host: host.address, pingTime: nil, status: .error)
                    self.latestResult = result
                    self.pingHistory.insert(result, at: 0)
                }
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

// SwiftUI Views (same as before, abbreviated for space)
struct ContentView: View {
    @ObservedObject var pingService: PingService
    @State private var selectedHostIndex = 0
    @State private var hosts = [
        Host(name: "Google", address: "8.8.8.8", isActive: true),
        Host(name: "Cloudflare", address: "1.1.1.1", isActive: false),
        Host(name: "Router", address: "192.168.1.1", isActive: false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Host Tabs
            HStack(spacing: 8) {
                ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                    Button(action: {
                        selectedHostIndex = index
                        updateActiveHost(index)
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(getHostStatusColor(host: host))
                                .frame(width: 10, height: 10)
                            Text(host.name)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedHostIndex == index ? Color.blue.opacity(0.2) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedHostIndex == index ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                Button(action: {}) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Simple status display for now
            VStack {
                Text("PingMonitor")
                    .font(.headline)
                    .padding()

                if let result = pingService.latestResult {
                    HStack {
                        Circle()
                            .fill(result.status.swiftUIColor)
                            .frame(width: 20, height: 20)

                        VStack(alignment: .leading) {
                            Text("Host: \(result.host)")
                            if let ping = result.pingTime {
                                Text("Ping: \(String(format: "%.1f ms", ping))")
                            } else {
                                Text("Ping: Timeout")
                            }
                        }
                    }
                    .padding()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .padding()
            }
        }
        .frame(width: 300, height: 200)
        .onAppear {
            updateActiveHost(selectedHostIndex)
        }
    }

    private func updateActiveHost(_ index: Int) {
        for i in hosts.indices {
            hosts[i].isActive = (i == index)
        }
        pingService.startPinging(host: hosts[index])
    }

    private func getHostStatusColor(host: Host) -> Color {
        if host.isActive, let result = pingService.latestResult {
            return result.status.swiftUIColor
        }
        return .gray
    }
}

// Menu Bar Controller with Native Dot Icon
class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var pingService = PingService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupMenuBar()
        setupBindings()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 40)

        guard let statusItem = statusItem, let button = statusItem.button else { return }

        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "PingMonitor"

        updateStatusDisplay()

        // Setup popover
        popover.contentSize = NSSize(width: 300, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView(pingService: pingService)
        )
    }

    private func setupBindings() {
        pingService.$latestResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusDisplay()
            }
            .store(in: &cancellables)
    }

    private func createStatusImage(color: NSColor, pingText: String) -> NSImage {
        let size = NSSize(width: 40, height: 22)
        let image = NSImage(size: size)

        image.lockFocus()

        // Draw colored dot (small, clean circle)
        color.setFill()
        let dotRect = NSRect(x: 15, y: 13, width: 8, height: 8)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        dotPath.fill()

        // Draw ping text below dot
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]

        let textSize = pingText.size(withAttributes: textAttributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: 2,
            width: textSize.width,
            height: textSize.height
        )

        pingText.draw(in: textRect, withAttributes: textAttributes)

        image.unlockFocus()

        // Make it template image so it adapts to dark mode
        image.isTemplate = false

        return image
    }

    private func updateStatusDisplay() {
        guard let button = statusItem?.button else { return }

        let (color, pingText): (NSColor, String)

        if let result = pingService.latestResult {
            color = result.status.color
            pingText = result.pingTime != nil ? String(format: "%.0fms", result.pingTime!) : "--"
        } else {
            color = .systemGray
            pingText = "--"
        }

        let image = createStatusImage(color: color, pingText: pingText)
        button.image = image
        button.title = ""  // Clear any text title
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// Main App
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = MenuBarController()
app.run()