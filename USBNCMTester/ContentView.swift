import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var scanner = NetworkInterfaceScanner()
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var activityManager = ActivityManager()

    @AppStorage("autoConnectEnabled") private var autoConnectEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("operationMode") private var operationMode: String = ConnectionManager.OperationMode.pingGateway.rawValue
    @AppStorage("customPingTarget") private var customPingTarget: String = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    InterfaceListView(
                        interfaces: scanner.interfaces,
                        lastScanTime: scanner.lastScanTime
                    )

                    Divider()

                    ConnectionStatusView(
                        connectionManager: connectionManager,
                        ethernetInterface: scanner.ethernetInterface
                    )
                }
                .padding()
            }
            .navigationTitle("USB-NCM Tester")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(
                    autoConnectEnabled: $autoConnectEnabled,
                    soundEnabled: $soundEnabled,
                    operationMode: $operationMode,
                    customPingTarget: $customPingTarget
                )
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                scanner.startScanning()
                locationManager.requestAuthorization()
                syncSettingsToManager()
            }
            .onDisappear {
                scanner.stopScanning()
                connectionManager.disconnect()
                activityManager.endActivity()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: scanner.ethernetInterface) { _, newInterface in
                handleEthernetInterfaceChange(newInterface)
            }
            .onChange(of: connectionManager.state) { _, _ in
                updateLiveActivity()
            }
            .onChange(of: connectionManager.requestCount) { _, _ in
                updateLiveActivity()
            }
            .onChange(of: soundEnabled) { _, _ in
                syncSettingsToManager()
            }
            .onChange(of: operationMode) { _, _ in
                syncSettingsToManager()
            }
            .onChange(of: customPingTarget) { _, _ in
                syncSettingsToManager()
            }
        }
    }

    private func syncSettingsToManager() {
        connectionManager.soundEnabled = soundEnabled
        connectionManager.operationMode = ConnectionManager.OperationMode(rawValue: operationMode) ?? .pingGateway
        connectionManager.customPingTarget = customPingTarget
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
            case .background:
                print("DEBUG: [APP] Entering background")
                activityManager.startActivity(interfaceName: scanner.ethernetInterface?.name)
                updateLiveActivity()

            case .active:
                print("DEBUG: [APP] Becoming active")
                activityManager.endActivity()

            case .inactive:
                print("DEBUG: [APP] Becoming inactive")

            @unknown default:
                break
        }
    }

    private func handleEthernetInterfaceChange(_ interface: NetworkInterface?) {
        guard autoConnectEnabled else { return }

        if let interface = interface {
            if case .disconnected = connectionManager.state {
                connectionManager.connect(usingInterface: interface.name, interfaceIP: interface.ipAddress)
            }
        }
    }

    private func updateLiveActivity() {
        let isConnected: Bool
        if case .connected = connectionManager.state {
            isConnected = true
        } else {
            isConnected = false
        }

        activityManager.updateActivity(
            isConnected: isConnected,
            requestCount: connectionManager.requestCount,
            lastResponseTime: connectionManager.lastResponseTime,
            interfaceName: scanner.ethernetInterface?.name
        )
    }
}

struct SettingsSheet: View {
    @Binding var autoConnectEnabled: Bool
    @Binding var soundEnabled: Bool
    @Binding var operationMode: String
    @Binding var customPingTarget: String
    @Environment(\.dismiss) private var dismiss

    private var selectedMode: ConnectionManager.OperationMode {
        ConnectionManager.OperationMode(rawValue: operationMode) ?? .pingGateway
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $autoConnectEnabled) {
                        Label("Auto-connect", systemImage: "bolt.horizontal")
                    }
                } footer: {
                    Text("Automatically connect when an Ethernet interface is detected.")
                }

                Section {
                    Picker(selection: $operationMode) {
                        ForEach(ConnectionManager.OperationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    } label: {
                        Label("Mode", systemImage: "arrow.triangle.2.circlepath")
                    }

                    if selectedMode == .pingCustom {
                        HStack {
                            Label("Target IP", systemImage: "network")
                            Spacer()
                            TextField("IP Address", text: $customPingTarget)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.decimalPad)
                                .frame(width: 140)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } footer: {
                    switch selectedMode {
                        case .pingGateway:
                            Text("Ping the USB-NCM gateway at 192.168.42.42.")
                        case .pingCustom:
                            Text("Ping a custom IP address.")
                        case .httpGoogle:
                            Text("Send HTTP keep-alive requests to www.google.de.")
                    }
                }

                Section {
                    Toggle(isOn: $soundEnabled) {
                        Label("Response Sound", systemImage: "speaker.wave.2")
                    }
                } footer: {
                    Text("Play a sound for each successful response.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
