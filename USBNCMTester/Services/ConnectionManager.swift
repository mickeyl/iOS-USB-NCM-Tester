import Foundation
import Combine
import Network
import AudioToolbox

final class ConnectionManager: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var description: String {
            switch self {
                case .disconnected:
                    return "Disconnected"
                case .connecting:
                    return "Connecting…"
                case .connected:
                    return "Connected"
                case .failed(let error):
                    return "Failed: \(error)"
            }
        }
    }

    enum OperationMode: String, CaseIterable, Identifiable {
        case pingGateway = "Ping Gateway"
        case pingCustom = "Ping Custom IP"
        case httpGoogle = "HTTP (Google)"

        var id: String { rawValue }
    }

    struct ConnectionLog: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let isError: Bool
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var logs: [ConnectionLog] = []
    @Published private(set) var requestCount: Int = 0
    @Published private(set) var lastResponseTime: Date?
    @Published private(set) var lastResponseSize: Int = 0
    @Published var soundEnabled: Bool = true
    @Published var operationMode: OperationMode = .pingGateway
    @Published var customPingTarget: String = ""

    private var connection: NWConnection?
    private var keepAliveTimer: Timer?
    private var pingTask: Task<Void, Never>?
    private var currentInterfaceIP: String?
    private let keepAliveInterval: TimeInterval = 5.0

    func connect(usingInterface interfaceName: String? = nil, interfaceIP: String? = nil) {
        disconnect()
        currentInterfaceIP = interfaceIP

        switch operationMode {
            case .pingGateway:
                startPingMode(gateway: true)
            case .pingCustom:
                startPingMode(gateway: false)
            case .httpGoogle:
                startHTTPMode(interfaceName: interfaceName)
        }
    }

    func disconnect() {
        stopKeepAlive()
        pingTask?.cancel()
        pingTask = nil
        connection?.cancel()
        connection = nil
        state = .disconnected
        log("Disconnected")
    }

    // MARK: - Ping Mode

    private func startPingMode(gateway: Bool) {
        let target: String
        if gateway {
            guard let gatewayIP = deriveGatewayIP() else {
                state = .failed("Cannot determine gateway")
                log("Cannot determine gateway IP from interface", isError: true)
                return
            }
            target = gatewayIP
            log("Pinging gateway: \(target)")
        } else {
            guard !customPingTarget.isEmpty else {
                state = .failed("No target specified")
                log("No custom ping target specified", isError: true)
                return
            }
            target = customPingTarget
            log("Pinging custom target: \(target)")
        }

        state = .connecting

        pingTask = Task { @MainActor in
            let result = await Pinger.shared.ping(host: target, timeout: 2.0)
            handlePingResult(result)

            guard !Task.isCancelled else { return }
            state = .connected

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(keepAliveInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }

                requestCount += 1
                let currentRequest = requestCount
                log("Ping #\(currentRequest) to \(target)")

                let result = await Pinger.shared.ping(host: target, timeout: 2.0)
                handlePingResult(result, requestNumber: currentRequest)
            }
        }
    }

    private func handlePingResult(_ result: Pinger.PingEvent, requestNumber: Int? = nil) {
        switch result {
            case .pong(let seq, let timeInMs):
                lastResponseTime = Date()
                let msg = requestNumber != nil
                    ? "Pong #\(requestNumber!): \(String(format: "%.1f", timeInMs)) ms"
                    : "Pong (seq=\(seq)): \(String(format: "%.1f", timeInMs)) ms"
                log(msg)
                if soundEnabled {
                    AudioServicesPlaySystemSound(1057)
                }

            case .timeout(let seq):
                let msg = requestNumber != nil
                    ? "Timeout #\(requestNumber!)"
                    : "Timeout (seq=\(seq))"
                log(msg, isError: true)

            case .error(let error):
                log("Ping error: \(error)", isError: true)
                state = .failed(error)
        }
    }

    private func deriveGatewayIP() -> String? {
        guard currentInterfaceIP != nil else { return nil }
        return "192.168.42.42"
    }

    // MARK: - HTTP Mode

    private func startHTTPMode(interfaceName: String?) {
        let targetHost = "www.google.de"
        let targetPort: UInt16 = 80

        state = .connecting
        log("Initiating HTTP connection to \(targetHost):\(targetPort)")

        let host = NWEndpoint.Host(targetHost)
        let port = NWEndpoint.Port(rawValue: targetPort)!

        let parameters = NWParameters.tcp
        parameters.prohibitExpensivePaths = false
        parameters.prohibitedInterfaceTypes = []

        if let interfaceName = interfaceName {
            log("Requiring interface: \(interfaceName)")
            parameters.requiredInterfaceType = .wiredEthernet
        }

        connection = NWConnection(host: host, port: port, using: parameters)

        connection?.stateUpdateHandler = { [weak self] newState in
            DispatchQueue.main.async {
                self?.handleConnectionStateChange(newState)
            }
        }

        connection?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.handlePathUpdate(path)
            }
        }

        connection?.viabilityUpdateHandler = { [weak self] isViable in
            DispatchQueue.main.async {
                self?.log("Connection viability changed: \(isViable ? "viable" : "not viable")")
            }
        }

        connection?.betterPathUpdateHandler = { [weak self] betterPathAvailable in
            DispatchQueue.main.async {
                self?.log("Better path available: \(betterPathAvailable)")
            }
        }

        connection?.start(queue: .global(qos: .userInitiated))
    }

    private func handlePathUpdate(_ path: NWPath) {
        var pathInfo = "Path update: status=\(path.status)"
        if let interface = path.availableInterfaces.first {
            pathInfo += ", interface=\(interface.name) (\(interface.type))"
        }
        pathInfo += ", expensive=\(path.isExpensive), constrained=\(path.isConstrained)"
        log(pathInfo)
    }

    private func handleConnectionStateChange(_ newState: NWConnection.State) {
        switch newState {
            case .ready:
                state = .connected
                log("Connection established")
                if let path = connection?.currentPath {
                    handlePathUpdate(path)
                }
                startKeepAlive()

            case .waiting(let error):
                log("Waiting: \(error.localizedDescription)", isError: true)

            case .failed(let error):
                state = .failed(error.localizedDescription)
                log("Connection failed: \(error.localizedDescription)", isError: true)
                stopKeepAlive()

            case .cancelled:
                state = .disconnected
                stopKeepAlive()

            case .preparing:
                log("Preparing connection…")

            case .setup:
                break

            @unknown default:
                break
        }
    }

    private func startKeepAlive() {
        sendHTTPRequest()

        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { [weak self] _ in
            self?.sendHTTPRequest()
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func sendHTTPRequest() {
        guard case .connected = state, let connection = connection else { return }

        let targetHost = "www.google.de"
        let request = "GET / HTTP/1.1\r\nHost: \(targetHost)\r\nConnection: keep-alive\r\n\r\n"
        let requestData = Data(request.utf8)

        requestCount += 1
        let currentRequest = requestCount
        log("Sending HTTP request #\(currentRequest)")

        connection.send(content: requestData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.log("Send error: \(error.localizedDescription)", isError: true)
                }
                return
            }

            self?.receiveResponse(requestNumber: currentRequest)
        })
    }

    private func receiveResponse(requestNumber: Int) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log("Receive error: \(error.localizedDescription)", isError: true)
                    return
                }

                if let data = data {
                    self?.lastResponseTime = Date()
                    self?.lastResponseSize = data.count
                    self?.log("HTTP Response #\(requestNumber): \(data.count) bytes")
                    if self?.soundEnabled == true {
                        AudioServicesPlaySystemSound(1057)
                    }
                }

                if isComplete {
                    self?.log("Connection closed by server")
                    self?.state = .disconnected
                    self?.stopKeepAlive()
                }
            }
        }
    }

    // MARK: - Logging

    private func log(_ message: String, isError: Bool = false) {
        let logEntry = ConnectionLog(timestamp: Date(), message: message, isError: isError)
        logs.insert(logEntry, at: 0)

        if logs.count > 100 {
            logs = Array(logs.prefix(100))
        }

        let timestamp = ISO8601DateFormatter().string(from: logEntry.timestamp)
        print("DEBUG: [\(timestamp)] \(isError ? "ERROR: " : "")\(message)")
    }

    func clearLogs() {
        logs.removeAll()
    }
}
