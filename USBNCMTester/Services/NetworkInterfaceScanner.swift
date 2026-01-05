import Foundation
import Combine
import Network

final class NetworkInterfaceScanner: ObservableObject {
    @Published private(set) var interfaces: [NetworkInterface] = []
    @Published private(set) var ethernetInterface: NetworkInterface?
    @Published private(set) var lastScanTime: Date?

    private var scanTimer: Timer?
    private let scanInterval: TimeInterval

    init(scanInterval: TimeInterval = 2.0) {
        self.scanInterval = scanInterval
    }

    func startScanning() {
        scan()
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    func scan() {
        let scannedInterfaces = scanInterfaces()
        let newEthernetInterface = scannedInterfaces.first { $0.isEthernet }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let oldEthernet = self.ethernetInterface
            self.interfaces = scannedInterfaces
            self.ethernetInterface = newEthernetInterface
            self.lastScanTime = Date()

            if oldEthernet?.id != newEthernetInterface?.id {
                if let eth = newEthernetInterface {
                    print("DEBUG: [SCAN] Ethernet interface appeared: \(eth.name) = \(eth.ipAddress)")
                } else if oldEthernet != nil {
                    print("DEBUG: [SCAN] Ethernet interface disappeared")
                }
            }

            let interfaceList = scannedInterfaces.map { "\($0.name)=\($0.ipAddress)" }.joined(separator: ", ")
            print("DEBUG: [SCAN] Interfaces: \(interfaceList)")
        }
    }

    private func scanInterfaces() -> [NetworkInterface] {
        var interfaces: [NetworkInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return interfaces
        }

        defer { freeifaddrs(ifaddr) }

        var currentAddr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        var seenInterfaces = Set<String>()

        while let addr = currentAddr {
            let interface = addr.pointee
            let family = interface.ifa_addr.pointee.sa_family

            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                let flags = Int32(interface.ifa_flags)
                let isUp = (flags & IFF_UP) != 0
                let isLoopback = (flags & IFF_LOOPBACK) != 0

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                let ipAddress = String(cString: hostname)

                var netmaskString: String?
                if let netmask = interface.ifa_netmask {
                    var netmaskHostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        netmask,
                        socklen_t(netmask.pointee.sa_len),
                        &netmaskHostname,
                        socklen_t(netmaskHostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    netmaskString = String(cString: netmaskHostname)
                }

                let interfaceId = "\(name)-\(ipAddress)"
                guard !seenInterfaces.contains(interfaceId) else {
                    currentAddr = interface.ifa_next
                    continue
                }
                seenInterfaces.insert(interfaceId)

                let isEthernet = detectEthernetInterface(name: name, flags: flags)

                let networkInterface = NetworkInterface(
                    id: interfaceId,
                    name: name,
                    ipAddress: ipAddress,
                    netmask: netmaskString,
                    isUp: isUp,
                    isLoopback: isLoopback,
                    isEthernet: isEthernet
                )
                interfaces.append(networkInterface)
            }

            currentAddr = interface.ifa_next
        }

        return interfaces.sorted { lhs, rhs in
            if lhs.isEthernet != rhs.isEthernet { return lhs.isEthernet }
            if lhs.isLoopback != rhs.isLoopback { return !lhs.isLoopback }
            return lhs.name < rhs.name
        }
    }

    private func detectEthernetInterface(name: String, flags: Int32) -> Bool {
        // USB-NCM interfaces on iOS typically appear as en2, en3, en4, etc.
        // en0 is typically Wi-Fi on iOS
        // We look for en* interfaces that are not en0 (Wi-Fi) and not loopback
        if name.hasPrefix("en") {
            guard let suffix = Int(name.dropFirst(2)) else { return false }
            // en0 is typically Wi-Fi, en1+ could be USB Ethernet
            return suffix >= 1
        }
        return false
    }
}
