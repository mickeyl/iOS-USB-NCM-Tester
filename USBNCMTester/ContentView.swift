import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkInterfaceScanner()
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var locationManager = LocationManager()
    @State private var autoConnectEnabled = true
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
                SettingsSheet(autoConnectEnabled: $autoConnectEnabled)
                    .presentationDetents([.medium])
            }
            .onAppear {
                scanner.startScanning()
                locationManager.requestAuthorization()
            }
            .onDisappear {
                scanner.stopScanning()
                connectionManager.disconnect()
            }
            .onChange(of: scanner.ethernetInterface) { _, newInterface in
                handleEthernetInterfaceChange(newInterface)
            }
        }
    }

    private func handleEthernetInterfaceChange(_ interface: NetworkInterface?) {
        guard autoConnectEnabled else { return }

        if let interface = interface {
            if case .disconnected = connectionManager.state {
                connectionManager.connect(usingInterface: interface.name)
            }
        }
    }
}

struct SettingsSheet: View {
    @Binding var autoConnectEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $autoConnectEnabled) {
                        Label("Auto-connect", systemImage: "bolt.horizontal")
                    }
                } footer: {
                    Text("Automatically connect to www.google.de when an Ethernet interface is detected.")
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
