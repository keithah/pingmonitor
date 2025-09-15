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

    var emoji: String {
        switch self {
        case .good: return "🟢"
        case .warning: return "🟡"
        case .error: return "🔴"
        case .timeout: return "⚫"
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

// SwiftUI Views
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

            // Graph Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ping History")
                        .font(.headline)
                    Spacer()
                    Text("Last 30 results")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)

                SimpleGraphView(history: Array(pingService.pingHistory.prefix(30)))
                    .frame(height: 120)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 8)

            Divider()

            // History Table
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent Results")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 12)

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(pingService.pingHistory.prefix(15))) { result in
                            HistoryRow(result: result)
                        }
                    }
                }
                .frame(height: 140)
            }
            .padding(.top, 4)

            Divider()

            // Bottom Menu
            HStack(spacing: 16) {
                Button("Add Host") {}
                    .font(.system(size: 11))
                    .foregroundColor(.blue)

                Button("Settings") {}
                    .font(.system(size: 11))
                    .foregroundColor(.blue)

                Button("Export") {}
                    .font(.system(size: 11))
                    .foregroundColor(.blue)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .foregroundColor(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 380, height: 420)
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

struct SimpleGraphView: View {
    let history: [PingResult]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))

                // Grid
                Path { path in
                    let stepY = geometry.size.height / 5
                    for i in 0...5 {
                        let y = stepY * CGFloat(i)
                        path.move(to: CGPoint(x: 8, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width - 8, y: y))
                    }

                    let stepX = (geometry.size.width - 16) / 5
                    for i in 0...5 {
                        let x = 8 + stepX * CGFloat(i)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                // Data visualization
                if !history.isEmpty {
                    let validData = history.compactMap { result -> (index: Int, ping: Double)? in
                        guard let pingTime = result.pingTime else { return nil }
                        return (history.firstIndex(where: { $0.id == result.id }) ?? 0, pingTime)
                    }

                    if !validData.isEmpty {
                        let maxPing = validData.map(\.ping).max() ?? 100
                        let minPing = validData.map(\.ping).min() ?? 0
                        let pingRange = max(maxPing - minPing, 10)

                        // Line path
                        Path { path in
                            let points = validData.enumerated().map { dataIndex, data in
                                let x = 8 + (geometry.size.width - 16) * CGFloat(validData.count - 1 - dataIndex) / CGFloat(max(1, validData.count - 1))
                                let normalizedPing = (data.ping - minPing) / pingRange
                                let y = geometry.size.height * (1 - normalizedPing) * 0.8 + geometry.size.height * 0.1
                                return CGPoint(x: x, y: y)
                            }

                            if let firstPoint = points.first {
                                path.move(to: firstPoint)
                                for point in points.dropFirst() {
                                    path.addLine(to: point)
                                }
                            }
                        }
                        .stroke(Color.blue, lineWidth: 2)

                        // Data points
                        ForEach(validData.indices, id: \.self) { dataIndex in
                            let data = validData[dataIndex]
                            let x = 8 + (geometry.size.width - 16) * CGFloat(validData.count - 1 - dataIndex) / CGFloat(max(1, validData.count - 1))
                            let normalizedPing = (data.ping - minPing) / pingRange
                            let y = geometry.size.height * (1 - normalizedPing) * 0.8 + geometry.size.height * 0.1

                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                                .position(x: x, y: y)
                        }
                    }
                }

                // Placeholder if no data
                if history.isEmpty {
                    VStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No data yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
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
        HStack(spacing: 8) {
            Text(timeString)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 55, alignment: .leading)

            Text(result.host)
                .font(.system(size: 10))
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)

            if let pingTime = result.pingTime {
                Text(String(format: "%.1f ms", pingTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(result.status.swiftUIColor)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("--")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            Spacer()

            Circle()
                .fill(result.status.swiftUIColor)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 12)
        .background(Color.clear)
    }
}

// Menu Bar Controller
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
        statusItem = NSStatusBar.system.statusItem(withLength: 50)

        guard let statusItem = statusItem, let button = statusItem.button else { return }

        button.action = #selector(togglePopover)
        button.target = self
        button.toolTip = "PingMonitor - Click to open"

        updateStatusDisplay()

        // Setup popover
        popover.contentSize = NSSize(width: 380, height: 420)
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

    private func updateStatusDisplay() {
        guard let button = statusItem?.button else { return }

        let attributedString = NSMutableAttributedString()

        if let result = pingService.latestResult {
            // Status emoji
            let emojiAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12)
            ]
            attributedString.append(NSAttributedString(string: result.status.emoji, attributes: emojiAttributes))

            // Newline
            attributedString.append(NSAttributedString(string: "\n"))

            // Ping time
            let timeText = result.pingTime != nil ? String(format: "%.0fms", result.pingTime!) : "--"
            let timeAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            attributedString.append(NSAttributedString(string: timeText, attributes: timeAttributes))
        } else {
            // Default state
            let emojiAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12)
            ]
            attributedString.append(NSAttributedString(string: "⚫", attributes: emojiAttributes))
            attributedString.append(NSAttributedString(string: "\n--"))
        }

        button.attributedTitle = attributedString
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
print("🚀 Starting Full-Featured PingMonitor...")

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let controller = MenuBarController()

print("✅ PingMonitor is ready!")
app.run()