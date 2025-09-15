import SwiftUI

struct PingGraphView: View {
    let pingHistory: [PingResult]
    let timeRange: Int

    private var maxPing: Double {
        pingHistory.compactMap { $0.pingTime }.max() ?? 100
    }

    private var chartData: [ChartDataPoint] {
        pingHistory.compactMap { result in
            guard let pingTime = result.pingTime else { return nil }
            return ChartDataPoint(
                timestamp: result.timestamp,
                value: pingTime,
                status: result.status
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chartData.isEmpty {
                emptyStateView
            } else {
                chartView
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No ping data available")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartView: some View {
        GeometryReader { geometry in
            ZStack {
                gridLines(in: geometry.size)
                dataLine(in: geometry.size)
                dataPoints(in: geometry.size)
            }
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        Path { path in
            for i in 0...4 {
                let y = size.height * CGFloat(i) / 4
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for i in 0...5 {
                let x = size.width * CGFloat(i) / 5
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
    }

    private func dataLine(in size: CGSize) -> some View {
        Path { path in
            let points = chartData.enumerated().map { index, data in
                CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(max(1, chartData.count - 1)),
                    y: size.height * (1 - CGFloat(data.value / maxPing))
                )
            }
            if let firstPoint = points.first {
                path.move(to: firstPoint)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
        }
        .stroke(Color.blue, lineWidth: 2)
    }

    private func dataPoints(in size: CGSize) -> some View {
        ForEach(chartData.indices, id: \.self) { index in
            let data = chartData[index]
            let point = CGPoint(
                x: size.width * CGFloat(index) / CGFloat(max(1, chartData.count - 1)),
                y: size.height * (1 - CGFloat(data.value / maxPing))
            )
            Circle()
                .fill(data.color)
                .frame(width: 4, height: 4)
                .position(point)
        }
    }
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let value: Double
    let status: PingStatus

    var color: Color {
        switch status {
        case .good: return .green
        case .warning: return .yellow
        case .error: return .red
        case .timeout: return .gray
        }
    }
}