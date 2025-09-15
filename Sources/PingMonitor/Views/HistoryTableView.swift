import SwiftUI

struct HistoryTableView: View {
    let pingHistory: [PingResult]
    @State private var selectedResult: PingResult?

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            scrollableContent
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var headerView: some View {
        HStack {
            Text("Time")
                .frame(width: 100, alignment: .leading)
            Text("Host")
                .frame(width: 120, alignment: .leading)
            Text("Ping")
                .frame(width: 60, alignment: .trailing)
            Text("Status")
                .frame(width: 80, alignment: .center)
            Spacer()
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var scrollableContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pingHistory) { result in
                    HistoryRow(result: result, isSelected: selectedResult?.id == result.id)
                        .onTapGesture {
                            selectedResult = result
                        }
                        .contextMenu {
                            Button("Copy") {
                                copyToClipboard(result)
                            }
                            Button("View Details") {
                                selectedResult = result
                            }
                        }
                    Divider()
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private func copyToClipboard(_ result: PingResult) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: result.timestamp)
        let pingString = result.pingTime != nil ? String(format: "%.1fms", result.pingTime!) : "Timeout"
        let text = "\(timeString)\t\(result.host)\t\(pingString)\t\(result.status.rawValue)"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct HistoryRow: View {
    let result: PingResult
    let isSelected: Bool

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: result.timestamp)
    }

    private var pingString: String {
        if let pingTime = result.pingTime {
            return String(format: "%.1fms", pingTime)
        } else {
            return "Timeout"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .good: return .green
        case .warning: return .yellow
        case .error: return .red
        case .timeout: return .gray
        }
    }

    var body: some View {
        HStack {
            Text(timeString)
                .frame(width: 100, alignment: .leading)
                .font(.system(size: 11, design: .monospaced))

            Text(result.host)
                .frame(width: 120, alignment: .leading)
                .font(.system(size: 11))
                .lineLimit(1)

            Text(pingString)
                .frame(width: 60, alignment: .trailing)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(statusColor)

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(result.status.rawValue.capitalized)
                    .font(.system(size: 10))
            }
            .frame(width: 80, alignment: .center)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}