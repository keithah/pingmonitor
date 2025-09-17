import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct PingEntry: TimelineEntry {
    let date: Date
    let pingResults: [PingWidgetData]
}

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

// MARK: - Timeline Provider

struct PingProvider: TimelineProvider {
    func placeholder(in context: Context) -> PingEntry {
        PingEntry(
            date: Date(),
            pingResults: [
                PingWidgetData(hostName: "Google", address: "8.8.8.8", pingTime: 12.3, status: .good),
                PingWidgetData(hostName: "Cloudflare", address: "1.1.1.1", pingTime: 8.7, status: .good),
                PingWidgetData(hostName: "Gateway", address: "192.168.1.1", pingTime: 2.1, status: .good)
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PingEntry) -> ()) {
        let entry = placeholder(in: context)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        // Read ping data from shared container
        let pingData = loadPingData()
        let entry = PingEntry(date: Date(), pingResults: pingData)

        // Refresh every 5 seconds
        let nextUpdateDate = Calendar.current.date(byAdding: .second, value: 5, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdateDate))

        completion(timeline)
    }

    private func loadPingData() -> [PingWidgetData] {
        // Try to load data from App Group shared container
        guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.pingmonitor.shared"),
              let data = try? Data(contentsOf: sharedURL.appendingPathComponent("pingdata.json")),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return defaultPingData()
        }

        return jsonArray.compactMap { dict in
            guard let hostName = dict["hostName"] as? String,
                  let address = dict["address"] as? String else { return nil }

            let pingTime = dict["pingTime"] as? Double
            let statusString = dict["status"] as? String ?? "timeout"
            let status = PingWidgetStatus.fromString(statusString)

            return PingWidgetData(hostName: hostName, address: address, pingTime: pingTime, status: status)
        }
    }

    private func defaultPingData() -> [PingWidgetData] {
        return [
            PingWidgetData(hostName: "Google", address: "8.8.8.8", pingTime: nil, status: .timeout),
            PingWidgetData(hostName: "Cloudflare", address: "1.1.1.1", pingTime: nil, status: .timeout),
            PingWidgetData(hostName: "Gateway", address: "192.168.1.1", pingTime: nil, status: .timeout)
        ]
    }
}

extension PingWidgetStatus {
    static func fromString(_ string: String) -> PingWidgetStatus {
        switch string.lowercased() {
        case "good": return .good
        case "warning": return .warning
        case "error": return .error
        default: return .timeout
        }
    }
}

// MARK: - Widget Views

struct PingMonitorWidgetEntryView: View {
    var entry: PingProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget (Single Host)

struct SmallWidgetView: View {
    let entry: PingEntry

    var primaryHost: PingWidgetData {
        entry.pingResults.first ?? PingWidgetData(hostName: "Offline", address: "", pingTime: nil, status: .timeout)
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
            Text("Updated \(entry.date, style: .time)")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .containerBackground(.fill.tertiary, for: .widget)
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

// MARK: - Medium Widget (Multiple Hosts Horizontal)

struct MediumWidgetView: View {
    let entry: PingEntry

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(entry.pingResults.prefix(3).enumerated()), id: \.offset) { index, host in
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

                if index < min(entry.pingResults.count, 3) - 1 {
                    Divider()
                }
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
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

// MARK: - Large Widget (Detailed List)

struct LargeWidgetView: View {
    let entry: PingEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("PING MONITOR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Host list
            ForEach(Array(entry.pingResults.enumerated()), id: \.offset) { index, host in
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

                if index < entry.pingResults.count - 1 {
                    Divider()
                }
            }

            Spacer()
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
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

// MARK: - Widget Configuration

struct PingMonitorWidget: Widget {
    let kind: String = "PingMonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PingProvider()) { entry in
            PingMonitorWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ping Monitor")
        .description("Monitor network latency to key hosts")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct PingMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        PingMonitorWidget()
    }
}