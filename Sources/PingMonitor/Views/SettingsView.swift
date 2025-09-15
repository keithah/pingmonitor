import SwiftUI

struct SettingsView: View {
    @Binding var hosts: [Host]
    let onUpdateHost: (Host) -> Void
    let onRemoveHost: (Host) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedHost: Host?
    @State private var pingInterval: Double = 2.0
    @State private var pingTimeout: Double = 5.0
    @State private var goodThreshold: Double = 50.0
    @State private var warningThreshold: Double = 150.0
    @State private var errorThreshold: Double = 500.0
    @State private var enableNotifications = true
    @State private var enableSounds = true
    @State private var autoSaveHistory = true
    @State private var historyLimit: Double = 100

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            HSplitView {
                hostsList
                    .frame(minWidth: 200, idealWidth: 250)

                settingsContent
                    .frame(minWidth: 350)
            }
            .frame(width: 600, height: 400)

            bottomBar
        }
    }

    private var titleBar: some View {
        HStack {
            Text("Preferences")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var hostsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hosts")
                .font(.headline)
                .padding()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(hosts) { host in
                        HostListItem(
                            host: host,
                            isSelected: selectedHost?.id == host.id,
                            onSelect: {
                                selectedHost = host
                                loadHostSettings(host)
                            },
                            onToggle: {
                                var updatedHost = host
                                updatedHost.enabled.toggle()
                                onUpdateHost(updatedHost)
                            },
                            onRemove: {
                                onRemoveHost(host)
                                if selectedHost?.id == host.id {
                                    selectedHost = nil
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if selectedHost != nil {
                    hostSettings
                }

                generalSettings
                thresholdSettings
                notificationSettings
                dataSettings
            }
            .padding()
        }
    }

    private var hostSettings: some View {
        GroupBox("Host Settings") {
            VStack(alignment: .leading, spacing: 12) {
                if let host = selectedHost {
                    HStack {
                        Text("Name:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("Host Name", text: Binding(
                            get: { host.name },
                            set: { newValue in
                                if var updatedHost = selectedHost {
                                    updatedHost.name = newValue
                                    selectedHost = updatedHost
                                }
                            }
                        ))
                    }

                    HStack {
                        Text("Address:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("IP or Domain", text: Binding(
                            get: { host.address },
                            set: { newValue in
                                if var updatedHost = selectedHost {
                                    updatedHost.address = newValue
                                    selectedHost = updatedHost
                                }
                            }
                        ))
                    }

                    HStack {
                        Text("Method:")
                            .frame(width: 100, alignment: .trailing)
                        Picker("", selection: Binding(
                            get: { host.pingMethod },
                            set: { newValue in
                                if var updatedHost = selectedHost {
                                    updatedHost.pingMethod = newValue
                                    selectedHost = updatedHost
                                }
                            }
                        )) {
                            Text("ICMP").tag(PingMethod.icmp)
                            Text("HTTP HEAD").tag(PingMethod.httpHead)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                        Spacer()
                    }

                    HStack {
                        Spacer()
                        Button("Apply Changes") {
                            if let host = selectedHost {
                                onUpdateHost(host)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var generalSettings: some View {
        GroupBox("General") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ping Interval:")
                        .frame(width: 100, alignment: .trailing)
                    Slider(value: $pingInterval, in: 1...60, step: 1)
                    Text("\(Int(pingInterval))s")
                        .frame(width: 40)
                }

                HStack {
                    Text("Timeout:")
                        .frame(width: 100, alignment: .trailing)
                    Slider(value: $pingTimeout, in: 2...10, step: 1)
                    Text("\(Int(pingTimeout))s")
                        .frame(width: 40)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var thresholdSettings: some View {
        GroupBox("Thresholds") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Good (<):")
                        .frame(width: 100, alignment: .trailing)
                    Slider(value: $goodThreshold, in: 10...100, step: 5)
                    Text("\(Int(goodThreshold))ms")
                        .frame(width: 60)
                }

                HStack {
                    Text("Warning (<):")
                        .frame(width: 100, alignment: .trailing)
                    Slider(value: $warningThreshold, in: 50...300, step: 10)
                    Text("\(Int(warningThreshold))ms")
                        .frame(width: 60)
                }

                HStack {
                    Text("Error (>):")
                        .frame(width: 100, alignment: .trailing)
                    Slider(value: $errorThreshold, in: 200...1000, step: 50)
                    Text("\(Int(errorThreshold))ms")
                        .frame(width: 60)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var notificationSettings: some View {
        GroupBox("Notifications") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable Desktop Notifications", isOn: $enableNotifications)
                Toggle("Enable Sound Alerts", isOn: $enableSounds)
            }
            .padding(.vertical, 8)
        }
    }

    private var dataSettings: some View {
        GroupBox("Data") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-save History", isOn: $autoSaveHistory)

                HStack {
                    Text("History Limit:")
                        .frame(width: 100, alignment: .trailing)
                    Slider(value: $historyLimit, in: 50...500, step: 50)
                    Text("\(Int(historyLimit))")
                        .frame(width: 60)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Done") {
                saveSettings()
                dismiss()
            }
            .keyboardShortcut(.return)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func loadHostSettings(_ host: Host) {
        if let thresholds = host.customThresholds {
            goodThreshold = thresholds.good
            warningThreshold = thresholds.warning
            errorThreshold = thresholds.error
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(pingInterval, forKey: "pingInterval")
        UserDefaults.standard.set(pingTimeout, forKey: "pingTimeout")
        UserDefaults.standard.set(enableNotifications, forKey: "enableNotifications")
        UserDefaults.standard.set(enableSounds, forKey: "enableSounds")
        UserDefaults.standard.set(autoSaveHistory, forKey: "autoSaveHistory")
        UserDefaults.standard.set(historyLimit, forKey: "historyLimit")
    }
}

struct HostListItem: View {
    let host: Host
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { host.enabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(CheckboxToggleStyle())

            VStack(alignment: .leading, spacing: 2) {
                Text(host.name)
                    .font(.system(size: 12, weight: .medium))
                Text(host.address)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            onSelect()
        }
    }
}