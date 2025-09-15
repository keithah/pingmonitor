import SwiftUI

struct ContentView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @State private var selectedTimeRange: TimeRange = .oneHour
    @State private var showingSettings = false
    @State private var showingAddHost = false

    enum TimeRange: String, CaseIterable {
        case fiveMinutes = "5m"
        case fifteenMinutes = "15m"
        case oneHour = "1h"
        case sixHours = "6h"
        case twentyFourHours = "24h"

        var minutes: Int {
            switch self {
            case .fiveMinutes: return 5
            case .fifteenMinutes: return 15
            case .oneHour: return 60
            case .sixHours: return 360
            case .twentyFourHours: return 1440
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HostTabsView(hosts: menuBarController.hosts,
                        selectedHost: $menuBarController.selectedHost,
                        onSelectHost: { host in
                            menuBarController.selectHost(host)
                        },
                        onAddHost: {
                            showingAddHost = true
                        })
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            VStack(spacing: 10) {
                HStack {
                    Text("Ping History")
                        .font(.headline)
                    Spacer()
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                }
                .padding(.horizontal)
                .padding(.top, 10)

                PingGraphView(
                    pingHistory: filterHistory(menuBarController.pingHistory),
                    timeRange: selectedTimeRange.minutes
                )
                .frame(height: 200)
                .padding(.horizontal)

                Divider()

                HistoryTableView(pingHistory: Array(menuBarController.pingHistory.prefix(50)))
                    .frame(height: 200)
            }

            Divider()

            HStack(spacing: 15) {
                Button(action: {
                    showingAddHost = true
                }) {
                    Label("Add Host", systemImage: "plus.circle")
                }

                Button(action: {
                    showingSettings = true
                }) {
                    Label("Preferences", systemImage: "gear")
                }

                Button(action: {
                    menuBarController.exportHistory()
                }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("Quit", systemImage: "power")
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 500, height: 600)
        .sheet(isPresented: $showingSettings) {
            SettingsView(hosts: $menuBarController.hosts,
                        onUpdateHost: menuBarController.updateHost,
                        onRemoveHost: menuBarController.removeHost)
        }
        .sheet(isPresented: $showingAddHost) {
            AddHostView { host in
                menuBarController.addHost(host)
                showingAddHost = false
            }
        }
    }

    private func filterHistory(_ history: [PingResult]) -> [PingResult] {
        let cutoffDate = Date().addingTimeInterval(-Double(selectedTimeRange.minutes * 60))
        return history.filter { $0.timestamp > cutoffDate }
    }
}

struct AddHostView: View {
    @State private var name = ""
    @State private var address = ""
    @State private var pingMethod: PingMethod = .icmp
    @Environment(\.dismiss) var dismiss
    let onAdd: (Host) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Host")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("IP Address or Domain", text: $address)
                Picker("Ping Method", selection: $pingMethod) {
                    Text("ICMP").tag(PingMethod.icmp)
                    Text("HTTP HEAD").tag(PingMethod.httpHead)
                }
            }
            .padding()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Add") {
                    let host = Host(name: name.isEmpty ? address : name,
                                  address: address,
                                  pingMethod: pingMethod)
                    onAdd(host)
                }
                .keyboardShortcut(.return)
                .disabled(address.isEmpty)
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
}