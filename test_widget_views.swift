#!/usr/bin/swift

import SwiftUI
import AppKit

// Test application to preview widget views

// Widget data models (simplified)
struct PingWidgetData {
    let hostName: String
    let address: String
    let pingTime: Double?
    let status: PingWidgetStatus
}

enum PingWidgetStatus {
    case good, warning, error, timeout

    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .yellow
        case .error: return .red
        case .timeout: return .gray
        }
    }

    var description: String {
        switch self {
        case .good: return "Good"
        case .warning: return "Slow"
        case .error: return "Error"
        case .timeout: return "Timeout"
        }
    }
}

// Test data
let testPingData = [
    PingWidgetData(hostName: "Google", address: "8.8.8.8", pingTime: 12.3, status: .good),
    PingWidgetData(hostName: "Cloudflare", address: "1.1.1.1", pingTime: 8.7, status: .good),
    PingWidgetData(hostName: "Gateway", address: "192.168.1.1", pingTime: 2.1, status: .good)
]

// Small Widget View (matches our widget implementation)
struct SmallWidgetPreview: View {
    let pingData: [PingWidgetData]

    var primaryHost: PingWidgetData {
        pingData.first ?? PingWidgetData(hostName: "Offline", address: "", pingTime: nil, status: .timeout)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Status indicator
            Circle()
                .fill(primaryHost.status.color)
                .frame(width: 16, height: 16)

            // Host name
            Text(primaryHost.hostName)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)

            // Address
            Text(primaryHost.address)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Ping time
            Text(pingTimeText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(primaryHost.status.color)

            // Last update
            Text("Updated \(Date(), style: .time)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var pingTimeText: String {
        guard let pingTime = primaryHost.pingTime else {
            return primaryHost.status.description
        }

        if pingTime < 1000 {
            return String(format: "%.0fms", pingTime)
        } else {
            return String(format: "%.1fs", pingTime / 1000)
        }
    }
}

// Medium Widget View
struct MediumWidgetPreview: View {
    let pingData: [PingWidgetData]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(pingData.prefix(3).enumerated()), id: \.offset) { index, host in
                VStack(spacing: 3) {
                    // Status indicator
                    Circle()
                        .fill(host.status.color)
                        .frame(width: 12, height: 12)

                    // Host name
                    Text(shortHostName(host.hostName))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // Ping time
                    Text(pingTimeText(host))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(host.status.color)
                }
                .frame(maxWidth: .infinity)

                if index < min(pingData.count, 3) - 1 {
                    Divider()
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func shortHostName(_ name: String) -> String {
        switch name {
        case "Google": return "GGL"
        case "Cloudflare": return "CF"
        case "Default Gateway", "Gateway": return "GW"
        default: return String(name.prefix(3)).uppercased()
        }
    }

    private func pingTimeText(_ host: PingWidgetData) -> String {
        guard let pingTime = host.pingTime else {
            return "-"
        }

        if pingTime < 1000 {
            return String(format: "%.0f", pingTime)
        } else {
            return String(format: "%.1fs", pingTime / 1000)
        }
    }
}

// Large Widget View
struct LargeWidgetPreview: View {
    let pingData: [PingWidgetData]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("PING MONITOR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(Date(), style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Host list
            ForEach(Array(pingData.enumerated()), id: \.offset) { index, host in
                HStack(spacing: 8) {
                    // Status indicator
                    Circle()
                        .fill(host.status.color)
                        .frame(width: 8, height: 8)

                    // Host info
                    VStack(alignment: .leading, spacing: 1) {
                        Text(host.hostName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                        Text(host.address)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Ping time
                    Text(pingTimeText(host))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(host.status.color)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.vertical, 2)

                if index < pingData.count - 1 {
                    Divider()
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func pingTimeText(_ host: PingWidgetData) -> String {
        guard let pingTime = host.pingTime else {
            return host.status.description
        }

        if pingTime < 1000 {
            return String(format: "%.0fms", pingTime)
        } else {
            return String(format: "%.1fs", pingTime / 1000)
        }
    }
}

// Preview window
struct WidgetPreviewView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("PingMonitor Widget Previews")
                .font(.title)
                .fontWeight(.bold)

            HStack(spacing: 20) {
                VStack {
                    Text("Small Widget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SmallWidgetPreview(pingData: testPingData)
                        .frame(width: 120, height: 120)
                }

                VStack {
                    Text("Medium Widget")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    MediumWidgetPreview(pingData: testPingData)
                        .frame(width: 280, height: 120)
                }
            }

            VStack {
                Text("Large Widget")
                    .font(.caption)
                    .foregroundColor(.secondary)
                LargeWidgetPreview(pingData: testPingData)
                    .frame(width: 280, height: 200)
            }
        }
        .padding(20)
    }
}

// Main App
@main
struct WidgetPreviewApp: App {
    var body: some Scene {
        WindowGroup {
            WidgetPreviewView()
        }
    }
}