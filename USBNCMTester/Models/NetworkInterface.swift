import Foundation

struct NetworkInterface: Identifiable, Hashable {
    let id: String
    let name: String
    let ipAddress: String
    let netmask: String?
    let isUp: Bool
    let isLoopback: Bool
    let isEthernet: Bool

    var displayName: String {
        if isLoopback {
            return "\(name) (Loopback)"
        } else if isEthernet {
            return "\(name) (Ethernet/USB)"
        } else if name.hasPrefix("ipsec") {
            return "\(name) (IPsec)"
        } else if name.hasPrefix("en") {
            return "\(name) (Wi-Fi)"
        } else if name.hasPrefix("pdp_ip") {
            return "\(name) (Cellular)"
        } else {
            return name
        }
    }

    enum InterfaceType: String {
        case loopback
        case ethernet
        case ipsec
        case wifi
        case cellular
        case other
    }

    var type: InterfaceType {
        if isLoopback { return .loopback }
        if isEthernet { return .ethernet }
        if name.hasPrefix("ipsec") { return .ipsec }
        if name.hasPrefix("en") { return .wifi }
        if name.hasPrefix("pdp_ip") { return .cellular }
        return .other
    }
}
