#!/usr/bin/swift

import SwiftUI
import AppKit
import Foundation
import Combine

// Helper function to get default gateway
func getDefaultGateway() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/sbin/route")
    process.arguments = ["-n", "get", "default"]

    let pipe = Pipe()
    process.standardOutput = pipe

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Parse for gateway line
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("gateway:") {
                let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if components.count >= 2 {
                    return components[1]
                }
            }
        }
    } catch {
        print("Error getting default gateway: \(error)")
    }

    // Fallback to common router IP
    return "192.168.1.1"
}

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
    private var timers: [String: Timer] = [:]

    func startPingingAllHosts(_ hosts: [Host]) {
        for host in hosts {
            startPinging(host: host)
        }
    }

    func startPinging(host: Host) {
        // Stop existing timer for this host if any
        timers[host.address]?.invalidate()

        // Start new timer for this host
        timers[host.address] = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.performPing(host: host)
        }

        // Do immediate ping
        performPing(host: host)

        // Set as current host if it's active
        if host.isActive {
            currentHost = host
        }
    }

    func stopPinging() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
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
                    // Always add to history
                    self.pingHistory.insert(result, at: 0)
                    if self.pingHistory.count > 100 {
                        self.pingHistory.removeLast()
                    }

                    // Only update latestResult if this is the active host
                    if host.isActive || self.currentHost?.address == host.address {
                        self.latestResult = result
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let result = PingResult(host: host.address, pingTime: nil, status: .error)

                    // Always add to history
                    self.pingHistory.insert(result, at: 0)

                    // Only update latestResult if this is the active host
                    if host.isActive || self.currentHost?.address == host.address {
                        self.latestResult = result
                    }
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

// Professional SwiftUI Interface
struct ContentView: View {
    @ObservedObject var pingService: PingService
    @State private var selectedHostIndex = 0
    @State private var hosts = [
        Host(name: "Google", address: "8.8.8.8", isActive: true),
        Host(name: "Cloudflare", address: "1.1.1.1", isActive: false),
        Host(name: "Default Gateway", address: getDefaultGateway(), isActive: false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Host Tabs Section
            hostTabsSection

            Divider()

            // Graph Section
            graphSection

            Divider()

            // History Section
            historySection

            Divider()

        }
        .frame(width: 450, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            updateActiveHost(selectedHostIndex)
        }
    }

    private var filteredHistory: [PingResult] {
        let currentHostAddress = hosts[selectedHostIndex].address
        return pingService.pingHistory.filter { $0.host == currentHostAddress }
    }

    private var hostTabsSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Monitored Hosts")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(hosts.enumerated()), id: \.element.id) { index, host in
                        hostTab(for: host, index: index)
                    }

                    Menu {
                        Button("Settings") {
                            print("Settings clicked")
                        }
                        Button("Export Data") {
                            print("Export clicked")
                        }
                        Divider()
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }

    private func hostTab(for host: Host, index: Int) -> some View {
        Button(action: {
            selectedHostIndex = index
            updateActiveHost(index)
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(getHostStatusColor(host: host))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(host.address)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(selectedHostIndex == index ? .white : .primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedHostIndex == index ? Color.accentColor : Color(NSColor.controlColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedHostIndex == index ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: selectedHostIndex == index ? Color.accentColor.opacity(0.3) : Color.clear, radius: 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ping History")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Real-time network latency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Last 30 results")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)

            GraphView(history: Array(filteredHistory.prefix(30)))
                .frame(height: 140)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent Results")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("Detailed ping log")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {}) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)

            // Header row
            HStack {
                Text("TIME")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                Text("HOST")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)

                Text("PING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)

                Text("STATUS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .center)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.separatorColor).opacity(0.1))

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(filteredHistory.prefix(20))) { result in
                        HistoryRow(result: result)
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(.vertical, 8)
    }


    private func updateActiveHost(_ index: Int) {
        for i in hosts.indices {
            hosts[i].isActive = (i == index)
        }

        // Set the current host and update latest result
        let selectedHost = hosts[index]
        pingService.currentHost = selectedHost

        // Find the most recent result for this host and set as latest
        if let recentResult = pingService.pingHistory.first(where: { $0.host == selectedHost.address }) {
            pingService.latestResult = recentResult
        }
    }

    private func getHostStatusColor(host: Host) -> Color {
        if host.isActive, let result = pingService.latestResult {
            return result.status.swiftUIColor
        }
        return .gray
    }
}

struct GraphView: View {
    let history: [PingResult]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with subtle border
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                // Grid lines
                gridLines(in: geometry.size)

                // Data visualization
                if !history.isEmpty {
                    dataVisualization(in: geometry.size)
                } else {
                    emptyState
                }

                // Y-axis labels
                yAxisLabels(in: geometry.size)
            }
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        Path { path in
            let padding: CGFloat = 30
            let graphWidth = size.width - padding
            let graphHeight = size.height - 20

            // Horizontal grid lines
            for i in 0...4 {
                let y = 10 + graphHeight * CGFloat(i) / 4
                path.move(to: CGPoint(x: padding, y: y))
                path.addLine(to: CGPoint(x: size.width - 10, y: y))
            }

            // Vertical grid lines
            for i in 0...5 {
                let x = padding + graphWidth * CGFloat(i) / 5
                path.move(to: CGPoint(x: x, y: 10))
                path.addLine(to: CGPoint(x: x, y: 10 + graphHeight))
            }
        }
        .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
    }

    private func dataVisualization(in size: CGSize) -> some View {
        let validData = history.compactMap { result -> (index: Int, ping: Double)? in
            guard let pingTime = result.pingTime else { return nil }
            return (history.firstIndex(where: { $0.id == result.id }) ?? 0, pingTime)
        }

        return Group {
            if !validData.isEmpty {
                let padding: CGFloat = 30
                let graphWidth = size.width - padding - 10
                let graphHeight = size.height - 30

                let maxPing = max(validData.map(\.ping).max() ?? 100, 50)
                let minPing = 0.0

                // Area under curve
                Path { path in
                    let points = validData.enumerated().map { dataIndex, data in
                        let x = padding + graphWidth * CGFloat(validData.count - 1 - dataIndex) / CGFloat(max(1, validData.count - 1))
                        let normalizedPing = (data.ping - minPing) / (maxPing - minPing)
                        let y = 10 + graphHeight * (1 - normalizedPing)
                        return CGPoint(x: x, y: y)
                    }

                    if let firstPoint = points.first, let lastPoint = points.last {
                        path.move(to: CGPoint(x: firstPoint.x, y: 10 + graphHeight))
                        path.addLine(to: firstPoint)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: lastPoint.x, y: 10 + graphHeight))
                        path.closeSubpath()
                    }
                }
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Data line
                Path { path in
                    let points = validData.enumerated().map { dataIndex, data in
                        let x = padding + graphWidth * CGFloat(validData.count - 1 - dataIndex) / CGFloat(max(1, validData.count - 1))
                        let normalizedPing = (data.ping - minPing) / (maxPing - minPing)
                        let y = 10 + graphHeight * (1 - normalizedPing)
                        return CGPoint(x: x, y: y)
                    }

                    if let firstPoint = points.first {
                        path.move(to: firstPoint)
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 2.5)

                // Data points
                ForEach(validData.indices, id: \.self) { dataIndex in
                    let data = validData[dataIndex]
                    let x = padding + graphWidth * CGFloat(validData.count - 1 - dataIndex) / CGFloat(max(1, validData.count - 1))
                    let normalizedPing = (data.ping - minPing) / (maxPing - minPing)
                    let y = 10 + graphHeight * (1 - normalizedPing)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                        .position(x: x, y: y)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title)
                .foregroundColor(.secondary)
            Text("Collecting ping data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func yAxisLabels(in size: CGSize) -> some View {
        let validData = history.compactMap { result -> Double? in result.pingTime }
        let maxPing = max(validData.max() ?? 100, 50)

        return VStack {
            ForEach(0..<5) { i in
                let value = maxPing * Double(4 - i) / 4
                Text("\(Int(value))")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(.secondary)
                if i < 4 { Spacer() }
            }
        }
        .frame(width: 25, height: size.height - 30)
        .position(x: 12, y: size.height / 2)
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
        HStack(spacing: 0) {
            Text(timeString)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)

            Text(result.host)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            if let pingTime = result.pingTime {
                Text(String(format: "%.1f ms", pingTime))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(result.status.swiftUIColor)
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("--")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }

            HStack(spacing: 4) {
                Circle()
                    .fill(result.status.swiftUIColor)
                    .frame(width: 6, height: 6)
                Text(result.status == .good ? "Good" : result.status == .warning ? "Slow" : result.status == .error ? "High" : "Down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(result.status.swiftUIColor)
            }
            .frame(width: 60, alignment: .center)

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

struct SettingsMenu: View {
    @State private var showingMenu = false
    @State private var showingSettings = false
    @State private var showingExport = false

    var body: some View {
        Button(action: {
            showingMenu.toggle()
        }) {
            Image(systemName: "gearshape.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showingMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: {
                    showingMenu = false
                    showingSettings = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .frame(width: 16)
                        Text("Settings")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())

                Button(action: {
                    showingMenu = false
                    showingExport = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 16)
                        Text("Export Data")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())

                Divider()
                    .padding(.horizontal, 8)

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "power")
                            .frame(width: 16)
                        Text("Quit")
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            }
            .frame(width: 140)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet()
        }
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Text("Host management and configuration options will be here.")
                .foregroundColor(.secondary)
                .padding()

            Spacer()
        }
        .frame(width: 400, height: 300)
    }
}

struct ExportSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Export Data")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            VStack(spacing: 12) {
                Button("Export as CSV") {
                    exportData(format: "CSV")
                }
                .buttonStyle(.borderedProminent)

                Button("Export as JSON") {
                    exportData(format: "JSON")
                }
                .buttonStyle(.bordered)

                Text("Export ping history data to a file")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Spacer()
        }
        .frame(width: 300, height: 200)
    }

    private func exportData(format: String) {
        // Export functionality placeholder
        print("Exporting data as \(format)")
    }
}

// Menu Bar Controller with Native Icon (same as before)
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

        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.toolTip = "PingMonitor"

        updateStatusDisplay()

        // Setup popover
        popover.contentSize = NSSize(width: 450, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView(pingService: pingService)
        )

        // Start pinging all hosts immediately
        let allHosts = [
            Host(name: "Google", address: "8.8.8.8", isActive: true),
            Host(name: "Cloudflare", address: "1.1.1.1", isActive: false),
            Host(name: "Default Gateway", address: getDefaultGateway(), isActive: false)
        ]
        pingService.startPingingAllHosts(allHosts)
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

        // Draw colored dot
        color.setFill()
        let dotRect = NSRect(x: 15, y: 13, width: 8, height: 8)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        dotPath.fill()

        // Draw ping text
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
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
        button.title = ""
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showRightClickMenu()
        } else {
            togglePopover()
        }
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

    private func showRightClickMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()

        // Host selection submenu
        let hostMenu = NSMenu()
        let googleItem = NSMenuItem(title: "Google (8.8.8.8)", action: #selector(selectGoogle), keyEquivalent: "")
        googleItem.target = self
        let cloudflareItem = NSMenuItem(title: "Cloudflare (1.1.1.1)", action: #selector(selectCloudflare), keyEquivalent: "")
        cloudflareItem.target = self
        let gatewayItem = NSMenuItem(title: "Default Gateway (\(getDefaultGateway()))", action: #selector(selectGateway), keyEquivalent: "")
        gatewayItem.target = self

        hostMenu.addItem(googleItem)
        hostMenu.addItem(cloudflareItem)
        hostMenu.addItem(gatewayItem)

        let selectHostItem = NSMenuItem(title: "Select Host", action: nil, keyEquivalent: "")
        selectHostItem.submenu = hostMenu
        menu.addItem(selectHostItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let exportItem = NSMenuItem(title: "Export Data", action: #selector(showExport), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.height), in: button)
    }

    @objc private func selectGoogle() {
        let host = Host(name: "Google", address: "8.8.8.8", isActive: true)
        pingService.currentHost = host
        if let recentResult = pingService.pingHistory.first(where: { $0.host == "8.8.8.8" }) {
            pingService.latestResult = recentResult
        }
    }

    @objc private func selectCloudflare() {
        let host = Host(name: "Cloudflare", address: "1.1.1.1", isActive: true)
        pingService.currentHost = host
        if let recentResult = pingService.pingHistory.first(where: { $0.host == "1.1.1.1" }) {
            pingService.latestResult = recentResult
        }
    }

    @objc private func selectGateway() {
        let gateway = getDefaultGateway()
        let host = Host(name: "Default Gateway", address: gateway, isActive: true)
        pingService.currentHost = host
        if let recentResult = pingService.pingHistory.first(where: { $0.host == gateway }) {
            pingService.latestResult = recentResult
        }
    }

    @objc private func showSettings() {
        print("Settings from right-click")
    }

    @objc private func showExport() {
        print("Export from right-click")
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// Main App
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = MenuBarController()
app.run()