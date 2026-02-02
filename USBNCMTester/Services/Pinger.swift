//
//  Pinger.swift
//  Based on Cornucopia – (C) Dr. Lauer Information Technology
//
import Darwin
import Foundation

final class Pinger: @unchecked Sendable {

    enum PingEvent {
        case pong(sequenceNumber: UInt16, timeInMs: Double)
        case timeout(sequenceNumber: UInt16)
        case error(String)
    }

    static let shared = Pinger()

    private var thread: Thread?
    private var runLoop: RunLoop?
    private var socket: CFSocket?
    private var requestsInFlight: [UInt16: RequestInFlight] = [:]
    private let lock = NSLock()

    private init() {
        startThread()
    }

    private func startThread() {
        thread = Thread { [weak self] in
            self?.runLoop = RunLoop.current
            self?.setupSocket()
            RunLoop.current.run()
        }
        thread?.name = "Pinger"
        thread?.start()

        while runLoop == nil {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func setupSocket() {
        var context = CFSocketContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)

        socket = CFSocketCreate(
            kCFAllocatorDefault,
            PF_INET,
            SOCK_DGRAM,
            IPPROTO_ICMP,
            CFSocketCallBackType.dataCallBack.rawValue,
            { _, _, _, data, info in
                guard let info, let data else { return }
                let pinger = Unmanaged<Pinger>.fromOpaque(info).takeUnretainedValue()
                let cfdata = Unmanaged<CFData>.fromOpaque(data).takeUnretainedValue()
                pinger.receivedData(data: cfdata as Data)
            },
            &context
        )

        guard let socket else {
            print("DEBUG: Failed to create ICMP socket")
            return
        }

        let handle = CFSocketGetNative(socket)
        var value: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout.size(ofValue: value)))

        let socketSource = CFSocketCreateRunLoopSource(nil, socket, 0)
        CFRunLoopAddSource(runLoop!.getCFRunLoop(), socketSource, .commonModes)
    }

    func ping(host: String, timeout: TimeInterval = 2.0) async -> PingEvent {
        await withCheckedContinuation { continuation in
            performOnThread {
                self.sendPing(host: host, timeout: timeout, continuation: continuation)
            }
        }
    }

    private func performOnThread(_ block: @escaping () -> Void) {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop.getCFRunLoop(), CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop.getCFRunLoop())
    }

    private func sendPing(host: String, timeout: TimeInterval, continuation: CheckedContinuation<PingEvent, Never>) {
        guard let socket else {
            continuation.resume(returning: .error("Socket not available"))
            return
        }

        guard let ipAddress = resolveHost(host) else {
            continuation.resume(returning: .error("Invalid hostname: \(host)"))
            return
        }

        let identifier = generateIdentifier()
        let sequenceNumber: UInt16 = 1

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_addr = ipAddress

        let address = withUnsafeBytes(of: &socketAddress) { Data($0) }
        let uuid = UUID()
        var packet = ICMPPacket.build(identifier: identifier, sequenceNumber: sequenceNumber, uuid: uuid)
        let packetData = withUnsafeBytes(of: &packet) { Data($0) }

        let request = RequestInFlight(
            identifier: identifier,
            sequenceNumber: sequenceNumber,
            timestamp: Date(),
            continuation: continuation
        )

        let timer = Timer(fire: Date().addingTimeInterval(timeout), interval: 0, repeats: false) { [weak self] _ in
            self?.handleTimeout(identifier: identifier)
        }
        RunLoop.current.add(timer, forMode: .common)

        lock.lock()
        requestsInFlight[identifier] = request
        requestsInFlight[identifier]?.timer = timer
        lock.unlock()

        let error = CFSocketSendData(socket, address as CFData, packetData as CFData, timeout)
        if error.rawValue != 0 {
            lock.lock()
            requestsInFlight.removeValue(forKey: identifier)
            lock.unlock()
            timer.invalidate()
            continuation.resume(returning: .error("Failed to send ping"))
        }
    }

    private func receivedData(data: Data) {
        guard data.count >= MemoryLayout<IPHeader>.size + MemoryLayout<ICMPHeader>.size else { return }

        let ipHeader = data.withUnsafeBytes { $0.load(as: IPHeader.self) }
        guard ipHeader.protocol == IPPROTO_ICMP else { return }

        let icmpHeader = data.withUnsafeBytes {
            $0.load(fromByteOffset: MemoryLayout<IPHeader>.size, as: ICMPHeader.self)
        }

        guard icmpHeader.type == 0 else { return }

        let identifier = UInt16(bigEndian: icmpHeader.identifier)

        lock.lock()
        guard let request = requestsInFlight.removeValue(forKey: identifier) else {
            lock.unlock()
            return
        }
        lock.unlock()

        request.timer?.invalidate()
        let timeInMs = Date().timeIntervalSince(request.timestamp) * 1000
        request.continuation.resume(returning: .pong(sequenceNumber: request.sequenceNumber, timeInMs: timeInMs))
    }

    private func handleTimeout(identifier: UInt16) {
        lock.lock()
        guard let request = requestsInFlight.removeValue(forKey: identifier) else {
            lock.unlock()
            return
        }
        lock.unlock()

        request.continuation.resume(returning: .timeout(sequenceNumber: request.sequenceNumber))
    }

    private func generateIdentifier() -> UInt16 {
        lock.lock()
        defer { lock.unlock() }
        var id: UInt16
        repeat {
            id = UInt16.random(in: 0...UInt16.max)
        } while requestsInFlight.keys.contains(id)
        return id
    }

    private func resolveHost(_ host: String) -> in_addr? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let info = result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        if let sockaddr = info.pointee.ai_addr {
            let sockaddrIn = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            return sockaddrIn.sin_addr
        }
        return nil
    }
}

extension Pinger {

    private struct RequestInFlight {
        let identifier: UInt16
        let sequenceNumber: UInt16
        let timestamp: Date
        let continuation: CheckedContinuation<PingEvent, Never>
        var timer: Timer?
    }

    private struct IPHeader {
        let versionAndHeaderLength: UInt8
        let differentiatedServices: UInt8
        let totalLength: UInt16
        let identification: UInt16
        let flagsAndFragmentOffset: UInt16
        let timeToLive: UInt8
        let `protocol`: UInt8
        let headerChecksum: UInt16
        let sourceAddress: (UInt8, UInt8, UInt8, UInt8)
        let destinationAddress: (UInt8, UInt8, UInt8, UInt8)
    }

    private struct ICMPHeader {
        var type: UInt8
        var code: UInt8
        var checksum: UInt16
        var identifier: UInt16
        var sequenceNumber: UInt16
    }

    private struct ICMPPacket {
        var type: UInt8
        var code: UInt8
        var checksum: UInt16
        var identifier: UInt16
        var sequenceNumber: UInt16
        var payload: uuid_t

        static func build(identifier: UInt16, sequenceNumber: UInt16, uuid: UUID) -> ICMPPacket {
            var packet = ICMPPacket(
                type: 8,
                code: 0,
                checksum: 0,
                identifier: CFSwapInt16HostToBig(identifier),
                sequenceNumber: CFSwapInt16HostToBig(sequenceNumber),
                payload: uuid.uuid
            )
            packet.checksum = Self.computeChecksum(&packet)
            return packet
        }

        private static func computeChecksum(_ packet: inout ICMPPacket) -> UInt16 {
            packet.checksum = 0
            var checksum: UInt32 = 0

            let data = withUnsafeBytes(of: &packet) { Data($0) }
            for i in stride(from: 0, to: data.count, by: 2) {
                let word: UInt32
                if i + 1 < data.count {
                    word = UInt32(data[i]) << 8 | UInt32(data[i + 1])
                } else {
                    word = UInt32(data[i]) << 8
                }
                checksum &+= word
            }

            while (checksum >> 16) != 0 {
                checksum = (checksum & 0xffff) + (checksum >> 16)
            }

            return ~CFSwapInt16HostToBig(UInt16(checksum))
        }
    }
}
