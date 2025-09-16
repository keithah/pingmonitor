#!/usr/bin/swift

//
//  PingMonitor.swift
//  A professional macOS menu bar application for real-time network monitoring
//
//  Features:
//  - Real-time ping monitoring of multiple hosts
//  - Beautiful menu bar status with colored indicators
//  - Interactive graphs and detailed history
//  - Smart default gateway detection
//
//  Created: 2024
//  License: MIT
//

import SwiftUI
import AppKit
import Foundation
import Combine
import Network
import SystemConfiguration

// MARK: - Utilities

/// Detects the default gateway IP address using SystemConfiguration (sandbox-compatible)
func getDefaultGateway() -> String {
    var gateway: String = "192.168.1.1" // Fallback

    // Create a reference to the dynamic store
    guard let store = SCDynamicStoreCreate(nil, "PingMonitor" as CFString, nil, nil) else {
        return gateway
    }

    // Get the global IPv4 key
    let globalIPv4Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)

    // Get the global IPv4 dictionary
    guard let globalIPv4Dict = SCDynamicStoreCopyValue(store, globalIPv4Key) as? [String: Any] else {
        return gateway
    }

    // Try to get router from global dict first
    if let primaryRouter = globalIPv4Dict[kSCPropNetIPv4Router as String] as? String {
        return primaryRouter
    }

    // Fallback: try to get from primary service
    guard let serviceKey = globalIPv4Dict[kSCDynamicStorePropNetPrimaryService as String] as? String else {
        return gateway
    }

    let serviceIPv4Key = SCDynamicStoreKeyCreateNetworkServiceEntity(nil, kSCDynamicStoreDomainState, serviceKey as CFString, kSCEntNetIPv4)

    guard let serviceIPv4Dict = SCDynamicStoreCopyValue(store, serviceIPv4Key) as? [String: Any],
          let routerIP = serviceIPv4Dict[kSCPropNetIPv4Router as String] as? String else {
        return gateway
    }

    return routerIP
}

// MARK: - Data Models

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
        case .timeout: return .black
        }
    }
}

enum PingType: String, CaseIterable, Codable {
    case icmp = "ICMP"
    case udp = "UDP"
    case tcp = "TCP"

    var description: String {
        switch self {
        case .icmp: return "ICMP (Traditional ping)"
        case .udp: return "UDP (User Datagram Protocol)"
        case .tcp: return "TCP (Transmission Control Protocol)"
        }
    }
}

enum GatewayMode: String, CaseIterable, Codable {
    case discovered = "Auto-discovered"
    case manual = "Manual Entry"
}

struct PingSettings: Codable {
    var interval: Double = 2.0 // seconds
    var timeout: Double = 3.0 // seconds
    var type: PingType = .icmp
    var goodThreshold: Double = 50.0 // ms
    var warningThreshold: Double = 200.0 // ms
    var port: Int? = nil // for UDP/TCP pings
}

struct Host: Identifiable, Codable {
    let id: UUID
    var name: String
    var address: String
    var isActive: Bool = false
    var isDefault: Bool = false
    var pingSettings: PingSettings = PingSettings()

    init(name: String, address: String, isActive: Bool = false, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.isActive = isActive
        self.isDefault = isDefault
        self.pingSettings = PingSettings()
    }
}

// MARK: - Ping Service

class PingService: ObservableObject {
    @Published var latestResult: PingResult?
    @Published var pingHistory: [PingResult] = []
    @Published var currentHost: Host?
    @Published var hosts: [Host] = []
    @Published var hostLatestResults: [String: PingResult] = [:] // Track latest result per host
    @Published var isCompactMode: Bool = false
    @Published var isStayOnTop: Bool = false
    private var timers: [String: Timer] = [:]
    private var gatewayRefreshTimer: Timer?

    func startPingingAllHosts(_ hosts: [Host]) {
        for host in hosts {
            startPinging(host: host)
        }
        startGatewayRefresh()
    }

    private func startGatewayRefresh() {
        gatewayRefreshTimer?.invalidate()
        gatewayRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.refreshDefaultGateway()
        }
    }

    private func refreshDefaultGateway() {
        let currentGateway = getDefaultGateway()

        // Find the default gateway host
        if let gatewayIndex = hosts.firstIndex(where: { $0.name == "Default Gateway" }) {
            let oldGateway = hosts[gatewayIndex].address

            // Only update if gateway has changed
            if oldGateway != currentGateway {
                print("Default gateway changed from \(oldGateway) to \(currentGateway)")

                // Stop pinging the old gateway
                timers[oldGateway]?.invalidate()
                timers.removeValue(forKey: oldGateway)

                // Update the host with new gateway address
                hosts[gatewayIndex].address = currentGateway

                // Start pinging the new gateway
                startPinging(host: hosts[gatewayIndex])

                // Clean up old ping history for the old gateway
                hostLatestResults.removeValue(forKey: oldGateway)
            }
        }
    }

    func startPinging(host: Host) {
        timers[host.address]?.invalidate()

        timers[host.address] = Timer.scheduledTimer(withTimeInterval: host.pingSettings.interval, repeats: true) { _ in
            self.performPing(host: host)
        }

        performPing(host: host)

        if host.isActive {
            currentHost = host
        }
    }

    func stopPinging() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        gatewayRefreshTimer?.invalidate()
        gatewayRefreshTimer = nil
    }

    private func performPing(host: Host) {
        DispatchQueue.global(qos: .background).async {
            let result: PingResult

            switch host.pingSettings.type {
            case .icmp:
                result = self.performICMPPing(host: host)
            case .udp:
                result = self.performUDPPing(host: host)
            case .tcp:
                result = self.performTCPPing(host: host)
            }

            DispatchQueue.main.async {
                self.addPingResult(result, for: host)
            }
        }
    }

    private func addPingResult(_ result: PingResult, for host: Host) {
        self.pingHistory.insert(result, at: 0)
        if self.pingHistory.count > 100 {
            self.pingHistory.removeLast()
        }

        // Store latest result for each host
        self.hostLatestResults[host.address] = result

        if host.isActive || self.currentHost?.address == host.address {
            self.latestResult = result
        }

        // Update widget data
        updateWidgetData()
    }

    private func updateWidgetData() {
        // Export data for widget consumption
        let widgetData = hosts.map { host -> [String: Any] in
            let result = hostLatestResults[host.address]
            return [
                "hostName": host.name,
                "address": host.address,
                "pingTime": result?.pingTime as Any,
                "status": statusToString(result?.status ?? .timeout)
            ]
        }

        // Save to shared container for widget
        guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pingmonitor.shared") else {
            print("Failed to get shared container URL")
            return
        }

        do {
            try FileManager.default.createDirectory(at: sharedURL, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: widgetData)
            try data.write(to: sharedURL.appendingPathComponent("pingdata.json"))
        } catch {
            print("Failed to save widget data: \(error)")
        }
    }

    private func statusToString(_ status: PingStatus) -> String {
        switch status {
        case .good: return "good"
        case .warning: return "warning"
        case .error: return "error"
        case .timeout: return "timeout"
        }
    }

    private func determineStatus(pingTime: Double, settings: PingSettings) -> PingStatus {
        if pingTime < settings.goodThreshold {
            return .good
        } else if pingTime < settings.warningThreshold {
            return .warning
        } else {
            return .error
        }
    }

    private func performICMPPing(host: Host) -> PingResult {
        let startTime = Date()

        // For sandbox compatibility, try multiple common ports as ICMP alternative
        // True ICMP requires raw sockets which need special entitlements not available in App Store
        let commonPorts: [UInt16] = [53, 80, 443, 22, 25] // DNS, HTTP, HTTPS, SSH, SMTP

        for port in commonPorts {
            let result = tryTCPConnection(host: host.address, port: port, timeout: host.pingSettings.timeout / Double(commonPorts.count), startTime: startTime, settings: host.pingSettings)

            if result.status != .timeout {
                return result
            }
        }

        return PingResult(host: host.address, pingTime: nil, status: .timeout)
    }

    private func tryTCPConnection(host: String, port: UInt16, timeout: TimeInterval, startTime: Date, settings: PingSettings) -> PingResult {
        var result: PingResult?
        let semaphore = DispatchSemaphore(value: 0)

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port),
            using: .tcp
        )

        connection.start(queue: .global())

        // Set timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            connection.cancel()
            if result == nil {
                result = PingResult(host: host, pingTime: nil, status: .timeout)
                semaphore.signal()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let pingTime = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
                let status = self.determineStatus(pingTime: pingTime, settings: settings)
                result = PingResult(host: host, pingTime: pingTime, status: status)
                connection.cancel()
                semaphore.signal()
            case .failed(_), .cancelled:
                if result == nil {
                    result = PingResult(host: host, pingTime: nil, status: .timeout)
                    semaphore.signal()
                }
            default:
                break
            }
        }

        semaphore.wait()
        return result ?? PingResult(host: host, pingTime: nil, status: .timeout)
    }

    private func performUDPPing(host: Host) -> PingResult {
        let port = host.pingSettings.port ?? 53 // Default to DNS port
        let startTime = Date()
        var result: PingResult?
        let semaphore = DispatchSemaphore(value: 0)

        let connection = NWConnection(
            host: NWEndpoint.Host(host.address),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .udp
        )

        connection.start(queue: .global())

        // Set timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + host.pingSettings.timeout) {
            connection.cancel()
            if result == nil {
                result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                semaphore.signal()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let pingTime = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
                let status = self.determineStatus(pingTime: pingTime, settings: host.pingSettings)
                result = PingResult(host: host.address, pingTime: pingTime, status: status)
                connection.cancel()
                semaphore.signal()
            case .failed(_), .cancelled:
                if result == nil {
                    result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                    semaphore.signal()
                }
            default:
                break
            }
        }

        semaphore.wait()
        return result ?? PingResult(host: host.address, pingTime: nil, status: .timeout)
    }

    private func performTCPPing(host: Host) -> PingResult {
        let port = host.pingSettings.port ?? 80 // Default to HTTP port
        let startTime = Date()
        var result: PingResult?
        let semaphore = DispatchSemaphore(value: 0)

        let connection = NWConnection(
            host: NWEndpoint.Host(host.address),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )

        connection.start(queue: .global())

        // Set timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + host.pingSettings.timeout) {
            connection.cancel()
            if result == nil {
                result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                semaphore.signal()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let pingTime = Date().timeIntervalSince(startTime) * 1000 // Convert to ms
                let status = self.determineStatus(pingTime: pingTime, settings: host.pingSettings)
                result = PingResult(host: host.address, pingTime: pingTime, status: status)
                connection.cancel()
                semaphore.signal()
            case .failed(_), .cancelled:
                if result == nil {
                    result = PingResult(host: host.address, pingTime: nil, status: .timeout)
                    semaphore.signal()
                }
            default:
                break
            }
        }

        semaphore.wait()
        return result ?? PingResult(host: host.address, pingTime: nil, status: .timeout)
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

// MARK: - SwiftUI Views

enum TimeFilter: String, CaseIterable {
    case oneMinute = "1 min"
    case fiveMinutes = "5 min"
    case tenMinutes = "10 min"
    case oneHour = "1 hour"

    var timeInterval: TimeInterval {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .tenMinutes: return 600
        case .oneHour: return 3600
        }
    }
}

struct CompactView: View {
    @ObservedObject var pingService: PingService
    @Binding var showingSettings: Bool
    @State private var selectedHostIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            // Host selection and controls
            HStack {
                // Host picker
                Picker("Host", selection: $selectedHostIndex) {
                    ForEach(Array(pingService.hosts.enumerated()), id: \.offset) { index, host in
                        Text(host.name)
                            .font(.system(size: 10, weight: .medium))
                            .tag(index)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 120)

                Spacer()

                // Settings button
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())

                // Expand button
                Button(action: {
                    pingService.isCompactMode = false
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            Divider()

            // Graph section (mini version)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ping History")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)

                CompactGraphView(pingService: pingService, selectedHostIndex: selectedHostIndex)
                    .frame(height: 60)
                    .padding(.horizontal, 8)
            }
            .padding(.top, 4)

            Divider()

            // Recent results (mini version)
            VStack(alignment: .leading, spacing: 4) {
                Text("Recent Results")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(compactFilteredHistory.prefix(6), id: \.id) { result in
                            CompactHistoryRow(result: result)
                        }
                    }
                }
                .frame(maxHeight: 80)
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 6)
        }
        .frame(width: 280, height: 220)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingSettings) {
            SettingsView(pingService: pingService)
                .frame(width: 500, height: 600)
        }
    }

    private var compactFilteredHistory: [PingResult] {
        guard selectedHostIndex < pingService.hosts.count else { return [] }
        let currentHostAddress = pingService.hosts[selectedHostIndex].address
        return pingService.pingHistory.filter { $0.host == currentHostAddress }
    }
}

struct CompactGraphView: View {
    @ObservedObject var pingService: PingService
    let selectedHostIndex: Int

    var body: some View {
        let filteredHistory = getFilteredHistory()
        let maxY = max(100.0, filteredHistory.compactMap { $0.pingTime }.max() ?? 100.0)

        GeometryReader { geometry in
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)

                if !filteredHistory.isEmpty {
                    // Grid lines
                    Path { path in
                        let step = geometry.size.height / 4
                        for i in 1..<4 {
                            let y = step * CGFloat(i)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)

                    // Data line
                    Path { path in
                        for (index, result) in filteredHistory.enumerated() {
                            guard let pingTime = result.pingTime else { continue }

                            let x = geometry.size.width * (1.0 - CGFloat(index) / CGFloat(max(filteredHistory.count - 1, 1)))
                            let y = geometry.size.height * (1.0 - CGFloat(pingTime) / CGFloat(maxY))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 1.5)

                    // Data points
                    ForEach(Array(filteredHistory.enumerated()), id: \.offset) { index, result in
                        if let pingTime = result.pingTime {
                            let x = geometry.size.width * (1.0 - CGFloat(index) / CGFloat(max(filteredHistory.count - 1, 1)))
                            let y = geometry.size.height * (1.0 - CGFloat(pingTime) / CGFloat(maxY))

                            Circle()
                                .fill(result.status.swiftUIColor)
                                .frame(width: 4, height: 4)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
        }
    }

    private func getFilteredHistory() -> [PingResult] {
        guard selectedHostIndex < pingService.hosts.count else { return [] }
        let currentHostAddress = pingService.hosts[selectedHostIndex].address
        return Array(pingService.pingHistory.filter { $0.host == currentHostAddress }.prefix(20))
    }
}

struct CompactHistoryRow: View {
    let result: PingResult

    var body: some View {
        HStack(spacing: 8) {
            // Time
            Text(result.timestamp, style: .time)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            // Host (shortened)
            Text(shortHostName)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)
                .lineLimit(1)

            Spacer()

            // Ping time
            HStack(spacing: 4) {
                Circle()
                    .fill(result.status.swiftUIColor)
                    .frame(width: 6, height: 6)

                Text(pingTimeText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(result.status.swiftUIColor)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }

    private var shortHostName: String {
        if result.host.contains("8.8.8.8") {
            return "Google"
        } else if result.host.contains("1.1.1.1") {
            return "Cloudflare"
        } else if result.host.hasPrefix("192.168") {
            return "Gateway"
        } else {
            return String(result.host.prefix(8))
        }
    }

    private var pingTimeText: String {
        guard let pingTime = result.pingTime else {
            return "-"
        }

        if pingTime < 1000 {
            return String(format: "%.0fms", pingTime)
        } else {
            return String(format: "%.1fs", pingTime / 1000)
        }
    }
}

struct ContentView: View {
    @ObservedObject var pingService: PingService
    @State private var selectedHostIndex = 0
    @State private var showingSettings = false
    @State private var showingExport = false
    @State private var selectedTimeFilter: TimeFilter = .fiveMinutes
    @State private var showingDetailedStats = false

    var body: some View {
        if pingService.isCompactMode {
            CompactView(pingService: pingService, showingSettings: $showingSettings)
        } else {
            VStack(spacing: 0) {
                hostTabsSection
                Divider()
                graphSection
                Divider()
                historySection
                Divider()
            }
            .frame(width: 450, height: showingDetailedStats ? 620 : 500)
            .background(Color(NSColor.windowBackgroundColor))
            .onAppear {
                updateActiveHost(selectedHostIndex)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(pingService: pingService)
                    .frame(width: 500, height: 600)
            }
            .sheet(isPresented: $showingExport) {
                ExportView(pingService: pingService)
                    .frame(width: 400, height: 300)
            }
        }
    }

    private var filteredHistory: [PingResult] {
        guard selectedHostIndex < pingService.hosts.count else { return [] }
        let currentHostAddress = pingService.hosts[selectedHostIndex].address
        let cutoffTime = Date().timeIntervalSince1970 - selectedTimeFilter.timeInterval
        return pingService.pingHistory.filter {
            $0.host == currentHostAddress && $0.timestamp.timeIntervalSince1970 >= cutoffTime
        }
    }

    private func formatDouble(_ value: Double, decimals: Int) -> String {
        guard value.isFinite && !value.isNaN else { return "0.000" }
        return String(format: "%.*f", decimals, value)
    }

    private var pingStatistics: (transmitted: Int, received: Int, packetLoss: Double, min: Double, avg: Double, max: Double, stddev: Double) {
        let successfulPings = filteredHistory.compactMap { $0.pingTime }
        let totalPings = filteredHistory.count
        let receivedPings = successfulPings.count

        // Handle case with no pings at all
        guard totalPings > 0 else {
            return (transmitted: 0, received: 0, packetLoss: 0.0, min: 0, avg: 0, max: 0, stddev: 0)
        }

        // Handle case with pings but no successful ones
        guard !successfulPings.isEmpty else {
            return (transmitted: totalPings, received: 0, packetLoss: 100.0, min: 0, avg: 0, max: 0, stddev: 0)
        }

        let packetLoss = Double(totalPings - receivedPings) / Double(totalPings) * 100.0
        let minPing = successfulPings.min() ?? 0
        let maxPing = successfulPings.max() ?? 0
        let avgPing = successfulPings.reduce(0, +) / Double(successfulPings.count)

        // Calculate standard deviation with safety check
        let variance = successfulPings.map { pow($0 - avgPing, 2) }.reduce(0, +) / Double(successfulPings.count)
        let stddev = variance.isFinite ? sqrt(variance) : 0.0

        return (transmitted: totalPings, received: receivedPings, packetLoss: packetLoss, min: minPing, avg: avgPing, max: maxPing, stddev: stddev)
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
                    ForEach(Array(pingService.hosts.enumerated()), id: \.element.id) { index, host in
                        hostTab(for: host, index: index)
                    }

                    Menu {
                        Button("Settings") {
                            showingSettings = true
                        }
                        Divider()
                        Button(action: { pingService.isCompactMode.toggle() }) {
                            HStack {
                                Text("Compact Mode")
                                Spacer()
                                if pingService.isCompactMode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        Button(action: { pingService.isStayOnTop.toggle() }) {
                            HStack {
                                Text("Stay on Top")
                                Spacer()
                                if pingService.isStayOnTop {
                                    Image(systemName: "checkmark")
                                }
                            }
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
                Menu {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            selectedTimeFilter = filter
                        }) {
                            HStack {
                                Text("Last \(filter.rawValue)")
                                if selectedTimeFilter == filter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Last \(selectedTimeFilter.rawValue)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)

            GraphView(history: filteredHistory)
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
                HStack(spacing: 8) {
                    Button(action: {
                        showingDetailedStats.toggle()
                    }) {
                        Image(systemName: showingDetailedStats ? "info.circle.fill" : "info.circle")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        showingExport = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)

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
                    ForEach(filteredHistory) { result in
                        HistoryRow(result: result)
                    }
                }
            }
            .frame(height: 160)

            if showingDetailedStats {
                detailedStatsSection
            }
        }
        .padding(.vertical, 8)
    }

    private func updateActiveHost(_ index: Int) {
        guard index < pingService.hosts.count else { return }

        for i in pingService.hosts.indices {
            pingService.hosts[i].isActive = (i == index)
        }

        let selectedHost = pingService.hosts[index]
        pingService.currentHost = selectedHost

        if let recentResult = pingService.pingHistory.first(where: { $0.host == selectedHost.address }) {
            pingService.latestResult = recentResult
        }
    }

    private func getHostStatusColor(host: Host) -> Color {
        if let result = pingService.hostLatestResults[host.address] {
            return result.status.swiftUIColor
        }
        return .gray
    }

    private var detailedStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let stats = pingStatistics
            let currentHost = selectedHostIndex < pingService.hosts.count ? pingService.hosts[selectedHostIndex] : nil

            VStack(alignment: .leading, spacing: 6) {
                Text("--- \(currentHost?.address ?? "unknown") ping statistics ---")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)

                Text("\(stats.transmitted) transmitted, \(stats.received) received, \(formatDouble(stats.packetLoss, decimals: 1))% packet loss")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)

                if stats.received > 0 {
                    Text("RTT min/avg/max/stddev = \(formatDouble(stats.min, decimals: 3))/\(formatDouble(stats.avg, decimals: 3))/\(formatDouble(stats.max, decimals: 3))/\(formatDouble(stats.stddev, decimals: 3)) ms")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                } else {
                    Text("No successful pings yet")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.orange)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .id(pingService.pingHistory.count) // Force refresh when ping data changes
    }
}

// MARK: - Graph View

struct GraphView: View {
    let history: [PingResult]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                gridLines(in: geometry.size)

                if !history.isEmpty {
                    dataVisualization(in: geometry.size)
                } else {
                    emptyState
                }

                yAxisLabels(in: geometry.size)
            }
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        Path { path in
            let padding: CGFloat = 30
            let graphWidth = size.width - padding
            let graphHeight = size.height - 20

            for i in 0...4 {
                let y = 10 + graphHeight * CGFloat(i) / 4
                path.move(to: CGPoint(x: padding, y: y))
                path.addLine(to: CGPoint(x: size.width - 10, y: y))
            }

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

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var pingService: PingService
    @Environment(\.presentationMode) var presentationMode
    @State private var showingAddHost = false
    @State private var editingHost: Host?
    @State private var newHostName = ""
    @State private var newHostAddress = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var editingPingType: PingType = .icmp
    @State private var editingInterval: Double = 2.0
    @State private var editingTimeout: Double = 3.0
    @State private var editingGoodThreshold: Double = 50.0
    @State private var editingWarningThreshold: Double = 200.0
    @State private var editingPort: String = ""
    @State private var gatewayMode: GatewayMode = .discovered
    @State private var manualGatewayAddress: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection

            hostListSection

            Spacer()

            bottomButtons
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingAddHost) {
            addHostSheet
        }
        .sheet(item: $editingHost) { host in
            editHostSheet(host: host)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PingMonitor Settings")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Manage hosts for network monitoring")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Compact Mode Toggle
            HStack {
                Image(systemName: "rectangle.compress.vertical")
                    .foregroundColor(.blue)
                Toggle("Compact Mode", isOn: $pingService.isCompactMode)
                    .font(.subheadline)
            }
            .padding(.top, 4)

            // Stay on Top Toggle
            HStack {
                Image(systemName: "pin.fill")
                    .foregroundColor(.orange)
                Toggle("Stay on Top", isOn: $pingService.isStayOnTop)
                    .font(.subheadline)
            }
        }
    }

    private var hostListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Monitored Hosts")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { showingAddHost = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Host")
                    }
                }
                .buttonStyle(.bordered)
            }

            if pingService.hosts.isEmpty {
                emptyHostsView
            } else {
                hostsList
            }
        }
    }

    private var emptyHostsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No hosts configured")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Add hosts to start monitoring network connectivity")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var hostsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(pingService.hosts) { host in
                    hostRow(host: host)
                }
            }
        }
        .frame(height: 300)
    }

    private func hostRow(host: Host) -> some View {
        HStack(spacing: 16) {
            Circle()
                .fill(getHostStatusColor(host: host))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(host.name)
                        .font(.system(size: 15, weight: .semibold))
                    if host.isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                Text(host.address)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Edit") {
                    editingHost = host
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Remove") {
                    removeHost(host)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }


    private var bottomButtons: some View {
        HStack {
            Button("Reset to Defaults") {
                resetToDefaults()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.bordered)
        }
    }

    private var addHostSheet: some View {
        VStack(spacing: 20) {
            Text("Add New Host")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Text("Host Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g., My Server", text: $newHostName)
                    .textFieldStyle(.roundedBorder)

                Text("IP Address or Hostname")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g., 192.168.1.1 or example.com", text: $newHostAddress)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    resetAddHostForm()
                    showingAddHost = false
                }
                .buttonStyle(.bordered)

                Button("Add Host") {
                    addNewHost()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newHostName.isEmpty || newHostAddress.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 250)
    }

    private func editHostSheet(host: Host) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Edit Host")
                    .font(.headline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 16) {
                    // Basic Info Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Basic Information")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Host Name")
                            .font(.caption)
                            .fontWeight(.medium)
                        TextField("Host name", text: .init(
                            get: { newHostName.isEmpty ? host.name : newHostName },
                            set: { newHostName = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        if host.name == "Default Gateway" {
                            Text("Gateway Mode")
                                .font(.caption)
                                .fontWeight(.medium)

                            VStack(alignment: .leading, spacing: 6) {
                                Button(action: { gatewayMode = .discovered }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: gatewayMode == .discovered ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(gatewayMode == .discovered ? .blue : .secondary)
                                        Text("Automatic Discovery")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)

                                Button(action: { gatewayMode = .manual }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: gatewayMode == .manual ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(gatewayMode == .manual ? .blue : .secondary)
                                        Text("Manual Entry")
                                            .font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("IP Address or Hostname")
                            .font(.caption)
                            .fontWeight(.medium)
                        TextField("IP address", text: .init(
                            get: { newHostAddress.isEmpty ? host.address : newHostAddress },
                            set: { newHostAddress = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .disabled(host.name == "Default Gateway" && gatewayMode == .discovered)
                        .opacity(host.name == "Default Gateway" && gatewayMode == .discovered ? 0.6 : 1.0)
                    }

                    Divider()

                    // Ping Configuration Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ping Configuration")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Ping Type")
                            .font(.caption)
                            .fontWeight(.medium)
                        Picker("Ping Type", selection: $editingPingType) {
                            ForEach(PingType.allCases, id: \.self) { type in
                                Text(type.description).tag(type)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Interval (seconds)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                TextField("2.0", value: $editingInterval, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading) {
                                Text("Timeout (seconds)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                TextField("3.0", value: $editingTimeout, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if editingPingType != .icmp {
                            Text("Port (optional)")
                                .font(.caption)
                                .fontWeight(.medium)
                            TextField(editingPingType == .udp ? "53 (DNS)" : "80 (HTTP)", text: $editingPort)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // Thresholds Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Response Time Thresholds (ms)")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Good (Green)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                TextField("50.0", value: $editingGoodThreshold, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading) {
                                Text("Warning (Yellow)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                                TextField("200.0", value: $editingWarningThreshold, format: .number)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Text("Above warning threshold = Error (Red)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        resetAddHostForm()
                        editingHost = nil
                    }
                    .buttonStyle(.bordered)

                    Button("Save Changes") {
                        saveHostChanges(host)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 450, height: 600)
        .onAppear {
            newHostName = host.name
            newHostAddress = host.address
            editingPingType = host.pingSettings.type
            editingInterval = host.pingSettings.interval
            editingTimeout = host.pingSettings.timeout
            editingGoodThreshold = host.pingSettings.goodThreshold
            editingWarningThreshold = host.pingSettings.warningThreshold
            editingPort = host.pingSettings.port?.description ?? ""

            // Initialize gateway mode for Default Gateway host
            if host.name == "Default Gateway" {
                gatewayMode = .discovered // Default to discovered mode
            }
        }
    }

    private func addNewHost() {
        guard !newHostName.isEmpty, !newHostAddress.isEmpty else {
            errorMessage = "Please fill in all fields"
            showError = true
            return
        }

        // Check for duplicate addresses
        if pingService.hosts.contains(where: { $0.address == newHostAddress }) {
            errorMessage = "A host with this address already exists"
            showError = true
            return
        }

        let newHost = Host(name: newHostName, address: newHostAddress, isActive: false, isDefault: false)
        pingService.hosts.append(newHost)
        pingService.startPinging(host: newHost)

        resetAddHostForm()
        showingAddHost = false
    }

    private func saveHostChanges(_ host: Host) {
        guard let index = pingService.hosts.firstIndex(where: { $0.id == host.id }) else { return }

        let updatedName = newHostName.isEmpty ? host.name : newHostName
        let updatedAddress = newHostAddress.isEmpty ? host.address : newHostAddress

        // Check for duplicate addresses (excluding the current host)
        if updatedAddress != host.address && pingService.hosts.contains(where: { $0.address == updatedAddress && $0.id != host.id }) {
            errorMessage = "A host with this address already exists"
            showError = true
            return
        }

        // Update basic info
        pingService.hosts[index].name = updatedName
        pingService.hosts[index].address = updatedAddress

        // Update ping settings
        var newSettings = pingService.hosts[index].pingSettings
        newSettings.type = editingPingType
        newSettings.interval = editingInterval
        newSettings.timeout = editingTimeout
        newSettings.goodThreshold = editingGoodThreshold
        newSettings.warningThreshold = editingWarningThreshold

        // Handle port setting
        if !editingPort.isEmpty, let port = Int(editingPort) {
            newSettings.port = port
        } else {
            newSettings.port = nil
        }

        pingService.hosts[index].pingSettings = newSettings

        // Restart pinging with new settings if this host is being monitored
        if pingService.hosts[index].isActive {
            pingService.stopPinging()
            pingService.startPingingAllHosts(pingService.hosts)
        }

        resetAddHostForm()
        editingHost = nil
    }

    private func removeHost(_ host: Host) {
        pingService.hosts.removeAll { $0.id == host.id }
    }

    private func resetToDefaults() {
        pingService.hosts = [
            Host(name: "Google", address: "8.8.8.8", isActive: true, isDefault: true),
            Host(name: "Cloudflare", address: "1.1.1.1", isActive: false, isDefault: true),
            Host(name: "Default Gateway", address: getDefaultGateway(), isActive: false, isDefault: true)
        ]
        pingService.startPingingAllHosts(pingService.hosts)
    }

    private func resetAddHostForm() {
        newHostName = ""
        newHostAddress = ""
    }

    private func getHostStatusColor(host: Host) -> Color {
        if let result = pingService.pingHistory.first(where: { $0.host == host.address }) {
            return result.status.swiftUIColor
        }
        return .gray
    }
}

// MARK: - Export View

struct ExportView: View {
    @ObservedObject var pingService: PingService
    @Environment(\.presentationMode) var presentationMode
    @State private var selectedFormat = ExportFormat.csv
    @State private var selectedTimeRange = TimeRange.lastHour
    @State private var includeAllHosts = true
    @State private var selectedHost = 0
    @State private var showingFilePicker = false
    @State private var exportMessage = ""
    @State private var showExportResult = false

    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
        case txt = "Text"
    }

    enum TimeRange: String, CaseIterable {
        case lastHour = "Last Hour"
        case last24Hours = "Last 24 Hours"
        case lastWeek = "Last Week"
        case all = "All Time"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Export Data")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .buttonStyle(.bordered)
                }

                Text("Export ping monitoring data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format")
                        .font(.headline)
                        .fontWeight(.medium)

                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Time Range")
                        .font(.headline)
                        .fontWeight(.medium)

                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hosts")
                        .font(.headline)
                        .fontWeight(.medium)

                    Toggle("Include all hosts", isOn: $includeAllHosts)

                    if !includeAllHosts && !pingService.hosts.isEmpty {
                        Picker("Select Host", selection: $selectedHost) {
                            ForEach(Array(pingService.hosts.enumerated()), id: \.element.id) { index, host in
                                Text("\(host.name) (\(host.address))").tag(index)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            Spacer()

            HStack {
                Text("\(filteredResults.count) records will be exported")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Export") {
                    exportData()
                }
                .buttonStyle(.borderedProminent)
                .disabled(filteredResults.isEmpty)
            }
        }
        .padding(20)
        .alert("Export Result", isPresented: $showExportResult) {
            Button("OK") {
                if exportMessage.contains("successfully") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } message: {
            Text(exportMessage)
        }
    }

    private var filteredResults: [PingResult] {
        var results = pingService.pingHistory

        // Filter by time range
        let cutoffDate: Date
        switch selectedTimeRange {
        case .lastHour:
            cutoffDate = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
        case .last24Hours:
            cutoffDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        case .lastWeek:
            cutoffDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        case .all:
            cutoffDate = Date.distantPast
        }

        results = results.filter { $0.timestamp >= cutoffDate }

        // Filter by host if needed
        if !includeAllHosts && selectedHost < pingService.hosts.count {
            let hostAddress = pingService.hosts[selectedHost].address
            results = results.filter { $0.host == hostAddress }
        }

        return results.reversed() // Chronological order for export
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: selectedFormat.rawValue.lowercased())!]
        panel.nameFieldStringValue = "pingmonitor_export_\(Date().timeIntervalSince1970).\(selectedFormat.rawValue.lowercased())"

        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                exportMessage = "Export cancelled"
                showExportResult = true
                return
            }

            do {
                let content = generateExportContent()
                try content.write(to: url, atomically: true, encoding: .utf8)
                exportMessage = "Data exported successfully to \(url.lastPathComponent)"
                showExportResult = true
            } catch {
                exportMessage = "Failed to export data: \(error.localizedDescription)"
                showExportResult = true
            }
        }
    }

    private func generateExportContent() -> String {
        let results = filteredResults

        switch selectedFormat {
        case .csv:
            var content = "Timestamp,Host,Ping Time (ms),Status\n"
            for result in results {
                let timestamp = ISO8601DateFormatter().string(from: result.timestamp)
                let pingTime = result.pingTime?.description ?? "--"
                let status = result.status == .good ? "Good" : result.status == .warning ? "Slow" : result.status == .error ? "High" : "Down"
                content += "\(timestamp),\(result.host),\(pingTime),\(status)\n"
            }
            return content

        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted

            let exportData = results.map { result in
                [
                    "timestamp": ISO8601DateFormatter().string(from: result.timestamp),
                    "host": result.host,
                    "pingTime": result.pingTime?.description ?? "null",
                    "status": result.status == .good ? "good" : result.status == .warning ? "warning" : result.status == .error ? "error" : "timeout"
                ]
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "[]"

        case .txt:
            var content = "PingMonitor Export\n"
            content += "Generated: \(Date())\n"
            content += "Time Range: \(selectedTimeRange.rawValue)\n"
            content += "Total Records: \(results.count)\n\n"

            for result in results {
                let timestamp = DateFormatter.localizedString(from: result.timestamp, dateStyle: .medium, timeStyle: .medium)
                let pingTime = result.pingTime.map { String(format: "%.1f ms", $0) } ?? "--"
                let status = result.status == .good ? "Good" : result.status == .warning ? "Slow" : result.status == .error ? "High" : "Down"
                content += "[\(timestamp)] \(result.host): \(pingTime) (\(status))\n"
            }

            return content
        }
    }
}

// MARK: - History Row

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

// MARK: - Menu Bar Controller

class MenuBarController: NSObject, ObservableObject, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var compactWindow: NSWindow?
    private var pingService = PingService()
    private var cancellables = Set<AnyCancellable>()
    private var isRecreatingWindow = false

    override init() {
        super.init()
        setupMenuBar()
        setupBindings()
        startMonitoring()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 40)

        guard let statusItem = statusItem, let button = statusItem.button else { return }

        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.toolTip = "PingMonitor"

        updateStatusDisplay()

        popover.contentSize = NSSize(width: 450, height: 500)
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

        pingService.$isCompactMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCompact in
                self?.handleCompactModeChange(isCompact: isCompact)
            }
            .store(in: &cancellables)

        pingService.$isStayOnTop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stayOnTop in
                self?.updateWindowStayOnTop(stayOnTop: stayOnTop)
            }
            .store(in: &cancellables)
    }

    private func startMonitoring() {
        pingService.hosts = [
            Host(name: "Google", address: "8.8.8.8", isActive: true, isDefault: true),
            Host(name: "Cloudflare", address: "1.1.1.1", isActive: false, isDefault: true),
            Host(name: "Default Gateway", address: getDefaultGateway(), isActive: false, isDefault: true)
        ]
        pingService.startPingingAllHosts(pingService.hosts)
    }

    private func createStatusImage(color: NSColor, pingText: String) -> NSImage {
        let size = NSSize(width: 40, height: 22)
        let image = NSImage(size: size)

        image.lockFocus()

        color.setFill()
        let dotRect = NSRect(x: 15, y: 13, width: 8, height: 8)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        dotPath.fill()

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

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command) {
            showRightClickMenu()
        } else {
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        // If stay-on-top is enabled, show right-click menu instead of popover
        if pingService.isStayOnTop {
            showRightClickMenu()
            return
        }

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

        let compactModeItem = NSMenuItem(title: "Compact Mode", action: #selector(toggleCompactMode), keyEquivalent: "")
        compactModeItem.target = self
        compactModeItem.state = pingService.isCompactMode ? .on : .off
        menu.addItem(compactModeItem)

        let stayOnTopItem = NSMenuItem(title: "Stay on Top", action: #selector(toggleStayOnTop), keyEquivalent: "")
        stayOnTopItem.target = self
        stayOnTopItem.state = pingService.isStayOnTop ? .on : .off
        menu.addItem(stayOnTopItem)

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
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "PingMonitor Settings"
        settingsWindow.contentViewController = NSHostingController(
            rootView: SettingsView(pingService: pingService)
        )
        settingsWindow.center()
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


    @objc private func toggleCompactMode() {
        pingService.isCompactMode.toggle()
    }

    @objc private func toggleStayOnTop() {
        pingService.isStayOnTop.toggle()
    }

    private func handleCompactModeChange(isCompact: Bool) {
        // Simple approach: always close floating window and recreate if needed
        closeAllFloatingWindows()

        if isCompact && pingService.isStayOnTop {
            // Only create floating window if both compact AND stay-on-top are enabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.createSimpleFloatingWindow(isCompact: true)
            }
        } else {
            // Use popover for all other cases
            updatePopoverSize()
        }
    }

    private func showCompactFloatingWindow() {
        // Ensure no existing window
        if compactWindow != nil {
            hideCompactFloatingWindow()
        }

        guard compactWindow == nil else { return }

        // Create window with appropriate style based on stay-on-top
        // Never include fullScreen in style mask to prevent crashes
        let styleMask: NSWindow.StyleMask = pingService.isStayOnTop ?
            [.borderless] :
            [.titled, .closable, .miniaturizable, .resizable]

        compactWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 220),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        guard let window = compactWindow else { return }

        if !pingService.isStayOnTop {
            window.title = "PingMonitor - Compact"
        }

        setupWindowContent()

        // Position window near status item
        if let button = statusItem?.button {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? NSRect.zero
            let windowOrigin = NSPoint(
                x: buttonFrame.midX - 140, // Center window under status item
                y: buttonFrame.minY - 240  // Position below status item
            )
            window.setFrameOrigin(windowOrigin)
        } else {
            window.center()
        }

        // Set window properties and prevent fullscreen
        if pingService.isStayOnTop {
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces]
            // Enable dragging for borderless windows
            window.isMovableByWindowBackground = true
        } else {
            window.level = .normal
            window.collectionBehavior = [.canJoinAllSpaces]
        }

        // Explicitly prevent all fullscreen behaviors
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)

        // Additional fullscreen prevention
        if window.responds(to: #selector(NSWindow.toggleFullScreen(_:))) {
            window.collectionBehavior.insert(.fullScreenDisallowsTiling)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateFloatingWindowToFullSize() {
        guard let window = compactWindow else {
            // No existing window, create a new full-size one
            createFullSizeFloatingWindow()
            return
        }

        // Update existing window to full size and content
        let currentFrame = window.frame
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y - (500 - currentFrame.height), // Adjust position for height change
            width: 450,
            height: 500
        )

        window.setFrame(newFrame, display: true, animate: true)

        // Update content to full ContentView
        window.contentViewController = NSHostingController(
            rootView: ContentView(pingService: pingService)
        )
    }

    private func createFullSizeFloatingWindow() {
        compactWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        guard let window = compactWindow else { return }

        window.contentViewController = NSHostingController(
            rootView: ContentView(pingService: pingService)
        )
        window.delegate = self

        // Position window
        if let button = statusItem?.button {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? NSRect.zero
            let windowOrigin = NSPoint(
                x: buttonFrame.midX - 225,
                y: buttonFrame.minY - 520
            )
            window.setFrameOrigin(windowOrigin)
        } else {
            window.center()
        }

        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]
        window.isMovableByWindowBackground = true

        // Prevent all fullscreen behaviors
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        if window.responds(to: #selector(NSWindow.toggleFullScreen(_:))) {
            window.collectionBehavior.insert(.fullScreenDisallowsTiling)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideCompactFloatingWindow() {
        if let window = compactWindow {
            window.delegate = nil
            window.close()
        }
        compactWindow = nil
        isRecreatingWindow = false
    }

    private func updateWindowStayOnTop(stayOnTop: Bool) {
        // Simple approach: close all windows and recreate if needed
        closeAllFloatingWindows()

        if stayOnTop && pingService.isCompactMode {
            // Only create floating window if both stay-on-top AND compact are enabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.createSimpleFloatingWindow(isCompact: true)
            }
        } else if stayOnTop && !pingService.isCompactMode {
            // Create full-size floating window for stay-on-top only
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.createSimpleFloatingWindow(isCompact: false)
            }
        } else {
            // Use popover for normal mode
            updatePopoverSize()
        }
    }

    private func updatePopoverSize() {
        if pingService.isCompactMode {
            popover.contentSize = NSSize(width: 280, height: 220)
        } else {
            popover.contentSize = NSSize(width: 450, height: 500)
        }
    }

    private func closeAllFloatingWindows() {
        if let window = compactWindow {
            window.delegate = nil
            window.close()
        }
        compactWindow = nil
        isRecreatingWindow = false
    }

    private func createSimpleFloatingWindow(isCompact: Bool) {
        // Ensure clean state
        closeAllFloatingWindows()

        let size = isCompact ? NSSize(width: 280, height: 220) : NSSize(width: 450, height: 500)

        compactWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], // Always borderless for floating windows
            backing: .buffered,
            defer: false
        )

        guard let window = compactWindow else { return }

        // Set content
        if isCompact {
            window.contentViewController = NSHostingController(
                rootView: CompactView(pingService: pingService, showingSettings: .constant(false))
            )
        } else {
            window.contentViewController = NSHostingController(
                rootView: ContentView(pingService: pingService)
            )
        }

        window.delegate = self

        // Position window
        if let button = statusItem?.button {
            let buttonFrame = button.window?.convertToScreen(button.frame) ?? NSRect.zero
            let windowOrigin = NSPoint(
                x: buttonFrame.midX - size.width / 2,
                y: buttonFrame.minY - size.height - 20
            )
            window.setFrameOrigin(windowOrigin)
        } else {
            window.center()
        }

        // Configure for stay-on-top
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]
        window.isMovableByWindowBackground = true

        // Prevent fullscreen completely
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func recreateWindowWithBorderlessStyle() {
        guard let oldWindow = compactWindow, !isRecreatingWindow else { return }
        isRecreatingWindow = true

        let frame = oldWindow.frame
        oldWindow.close()

        compactWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        guard let window = compactWindow else {
            isRecreatingWindow = false
            return
        }

        setupWindowContent()
        window.setFrame(frame, display: true)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]

        // Prevent all fullscreen behaviors
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        if window.responds(to: #selector(NSWindow.toggleFullScreen(_:))) {
            window.collectionBehavior.insert(.fullScreenDisallowsTiling)
        }

        // Enable dragging for borderless windows
        window.isMovableByWindowBackground = true

        window.makeKeyAndOrderFront(nil)
        isRecreatingWindow = false
    }

    private func recreateWindowWithTitleBar() {
        guard let oldWindow = compactWindow, !isRecreatingWindow else { return }
        isRecreatingWindow = true

        let frame = oldWindow.frame
        oldWindow.close()

        compactWindow = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        guard let window = compactWindow else {
            isRecreatingWindow = false
            return
        }

        setupWindowContent()
        window.title = "PingMonitor - Compact"
        window.setFrame(frame, display: true)
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces]

        // Prevent all fullscreen behaviors
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        if window.responds(to: #selector(NSWindow.toggleFullScreen(_:))) {
            window.collectionBehavior.insert(.fullScreenDisallowsTiling)
        }

        window.makeKeyAndOrderFront(nil)
        isRecreatingWindow = false
    }

    private func setupWindowContent() {
        guard let window = compactWindow else { return }

        window.contentViewController = NSHostingController(
            rootView: CompactView(pingService: pingService, showingSettings: .constant(false))
        )
        window.delegate = self
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === compactWindow {
            compactWindow = nil
            pingService.isCompactMode = false
        }
    }
}

// MARK: - Main App

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = MenuBarController()
app.run()