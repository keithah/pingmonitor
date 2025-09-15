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

    var emoji: String {
        switch self {
        case .good: return "🟢"
        case .warning: return "🟡"
        case .error: return "🔴"
        case .timeout: return "⚫"
        }
    }
}

struct Host {
    let name: String
    let address: String
    var isActive: Bool = false
}

// Enhanced Ping Service
class PingService: ObservableObject {
    @Published var latestResult: PingResult?
    @Published var pingHistory: [PingResult] = []
    private var timer: Timer?

    func startPinging(host: Host) {
        stopPinging()
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "5", host.address]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let result: PingResult
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if let pingTime = extractPingTime(from: output) {
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

// SwiftUI Views
struct ContentView: View {
    @ObservedObject var pingService: PingService
    @State private var selectedHost = 0
    @State private var hosts = [
        Host(name: "Google", address: "8.8.8.8", isActive: true),
        Host(name: "Cloudflare", address: "1.1.1.1", isActive: false),
        Host(name: "Router", address: "192.168.1.1", isActive: false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Host Tabs
            HStack(spacing: 8) {
                ForEach(0..<hosts.count, id: \.self) { index in
                    Button(action: {
                        selectedHost = index
                        hosts[selectedHost].isActive = true
                        for i in hosts.indices where i != selectedHost {
                            hosts[i].isActive = false
                        }
                        pingService.startPinging(host: hosts[selectedHost])
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(hosts[index].isActive && pingService.latestResult != nil ?
                                     Color(pingService.latestResult!.status.color) : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(hosts[index].name)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedHost == index ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Graph Area
            VStack {
                HStack {
                    Text("Ping History")
                        .font(.headline)
                    Spacer()
                    Text("Last 30 pings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)

                SimpleGraphView(history: Array(pingService.pingHistory.prefix(30)))
                    .frame(height: 120)
                    .padding(.horizontal)
            }

            Divider()

            // History Table
            VStack {
                HStack {
                    Text("Recent Results")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(pingService.pingHistory.prefix(20))) { result in
                            HistoryRow(result: result)
                        }
                    }
                }
                .frame(height: 160)
                .padding(.horizontal)
            }

            Divider()

            // Bottom Menu
            HStack {
                Button("Add Host") { }
                    .font(.system(size: 11))
                Spacer()
                Button("Settings") { }
                    .font(.system(size: 11))
                Spacer()
                Button("Export") { }
                    .font(.system(size: 11))
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 350, height: 450)
        .onAppear {
            pingService.startPinging(host: hosts[selectedHost])
        }
    }
}

struct SimpleGraphView: View {
    let history: [PingResult]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                Path { path in
                    let stepY = geometry.size.height / 4
                    for i in 0...4 {
                        let y = stepY * CGFloat(i)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)

                // Data line
                if !history.isEmpty {
                    let maxPing = history.compactMap(\.pingTime).max() ?? 100
                    let points = history.enumerated().compactMap { index, result -> CGPoint? in
                        guard let pingTime = result.pingTime else { return nil }
                        let x = geometry.size.width * CGFloat(history.count - 1 - index) / CGFloat(max(1, history.count - 1))
                        let y = geometry.size.height * (1 - CGFloat(pingTime / maxPing))
                        return CGPoint(x: x, y: y)
                    }

                    Path { path in
                        if let first = points.first {
                            path.move(to: first)
                            for point in points.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)

                    // Data points
                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4, height: 4)
                            .position(points[index])
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct HistoryRow: View {
    let result: PingResult

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: result.timestamp)
    }

    var body: some View {
        HStack {
            Text(timeString)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60, alignment: .leading)

            Text(result.host)
                .font(.system(size: 11))
                .frame(width: 80, alignment: .leading)

            if let pingTime = result.pingTime {
                Text(String(format: "%.1f ms", pingTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(result.status.color))
            } else {
                Text("Timeout")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(Color(result.status.color))
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }
}

// Enhanced Menu Bar Controller
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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusItemDisplay()
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 350, height: 450)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView(pingService: pingService)
        )
    }

    private func setupBindings() {
        pingService.$latestResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemDisplay()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemDisplay() {
        guard let button = statusItem?.button else { return }

        DispatchQueue.main.async {
            let attributedString = NSMutableAttributedString()

            // Status dot
            if let result = self.pingService.latestResult {
                let dotAttachment = NSTextAttachment()
                dotAttachment.image = self.createDotImage(color: result.status.color)
                dotAttachment.bounds = CGRect(x: 0, y: -1, width: 8, height: 8)
                attributedString.append(NSAttributedString(attachment: dotAttachment))

                // New line for ping time underneath
                attributedString.append(NSAttributedString(string: "\n"))

                // Ping time
                let pingText = result.pingTime != nil ?
                    String(format: "%.0fms", result.pingTime!) : "--"

                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                    .foregroundColor: NSColor.labelColor
                ]
                attributedString.append(NSAttributedString(string: pingText, attributes: textAttributes))
            } else {
                let dotAttachment = NSTextAttachment()
                dotAttachment.image = self.createDotImage(color: .systemGray)
                dotAttachment.bounds = CGRect(x: 0, y: -1, width: 8, height: 8)
                attributedString.append(NSAttributedString(attachment: dotAttachment))

                attributedString.append(NSAttributedString(string: "\n--"))
            }

            button.attributedTitle = attributedString
        }
    }

    private func createDotImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()

        color.setFill()
        let path = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 6, height: 6))
        path.fill()

        image.unlockFocus()
        return image
    }

    @objc private func togglePopover() {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

// Main execution
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let _ = MenuBarController()
app.run()