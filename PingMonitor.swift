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

// MARK: - Utilities

/// Detects the default gateway IP address for local network monitoring
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

    return "192.168.1.1" // Fallback
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
        case .timeout: return .gray
        }
    }
}

struct Host: Identifiable, Codable {
    let id: UUID
    var name: String
    var address: String
    var isActive: Bool = false
    var isDefault: Bool = false

    init(name: String, address: String, isActive: Bool = false, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.isActive = isActive
        self.isDefault = isDefault
    }
}

// MARK: - Ping Service

class PingService: ObservableObject {
    @Published var latestResult: PingResult?
    @Published var pingHistory: [PingResult] = []
    @Published var currentHost: Host?
    @Published var hosts: [Host] = []
    private var timers: [String: Timer] = [:]

    func startPingingAllHosts(_ hosts: [Host]) {
        for host in hosts {
            startPinging(host: host)
        }
    }

    func startPinging(host: Host) {
        timers[host.address]?.invalidate()

        timers[host.address] = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
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
                    self.pingHistory.insert(result, at: 0)
                    if self.pingHistory.count > 100 {
                        self.pingHistory.removeLast()
                    }

                    if host.isActive || self.currentHost?.address == host.address {
                        self.latestResult = result
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let result = PingResult(host: host.address, pingTime: nil, status: .error)
                    self.pingHistory.insert(result, at: 0)

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

// MARK: - SwiftUI Views

struct ContentView: View {
    @ObservedObject var pingService: PingService
    @State private var selectedHostIndex = 0
    @State private var showingSettings = false
    @State private var showingExport = false

    var body: some View {
        VStack(spacing: 0) {
            hostTabsSection
            Divider()
            graphSection
            Divider()
            historySection
            Divider()
        }
        .frame(width: 450, height: 500)
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

    private var filteredHistory: [PingResult] {
        guard selectedHostIndex < pingService.hosts.count else { return [] }
        let currentHostAddress = pingService.hosts[selectedHostIndex].address
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
                    ForEach(Array(pingService.hosts.enumerated()), id: \.element.id) { index, host in
                        hostTab(for: host, index: index)
                    }

                    Menu {
                        Button("Settings") {
                            showingSettings = true
                        }
                        Button("Export Data") {
                            showingExport = true
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
        if host.isActive, let result = pingService.latestResult {
            return result.status.swiftUIColor
        }
        return .gray
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
        VStack(spacing: 20) {
            Text("Edit Host")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 12) {
                Text("Host Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("Host name", text: .init(
                    get: { newHostName.isEmpty ? host.name : newHostName },
                    set: { newHostName = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Text("IP Address or Hostname")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("IP address", text: .init(
                    get: { newHostAddress.isEmpty ? host.address : newHostAddress },
                    set: { newHostAddress = $0 }
                ))
                .textFieldStyle(.roundedBorder)
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
        .padding(20)
        .frame(width: 400, height: 250)
        .onAppear {
            newHostName = host.name
            newHostAddress = host.address
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

        pingService.hosts[index].name = updatedName
        pingService.hosts[index].address = updatedAddress

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

class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover = NSPopover()
    private var pingService = PingService()
    private var cancellables = Set<AnyCancellable>()

    init() {
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

    @objc private func showExport() {
        let exportWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        exportWindow.title = "Export Data"
        exportWindow.contentViewController = NSHostingController(
            rootView: ExportView(pingService: pingService)
        )
        exportWindow.center()
        exportWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main App

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = MenuBarController()
app.run()