import Foundation
import Darwin

enum AirliftNetworkStatus {
    struct Interface {
        let name: String
        let ipv4: String
    }

    static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            ptr = current.pointee.ifa_next
            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(MemoryLayout<sockaddr_in>.size)
            guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            result.append(Interface(name: String(decoding: bytes, as: UTF8.self),
                                    ipv4: String(decoding: bytes, as: UTF8.self)))
        }
        return result
    }

    static func tunnelPairs() -> [(local: String, peer: String?, iface: String)] {
        var result: [(String, String?, String)] = []
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            ptr = current.pointee.ifa_next
            let name = String(cString: current.pointee.ifa_name)
            guard isTunnelInterface(name),
                  let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET),
                  let local = numericHost(addr),
                  isLoopbackRange(local) else { continue }

            var peer: String?
            if let dst = current.pointee.ifa_dstaddr,
               dst.pointee.sa_family == sa_family_t(AF_INET),
               let p = numericHost(dst), isLoopbackRange(p), p != local {
                peer = p
            }
            result.append((local, peer, name))
        }
        return result
    }

    static func isConnected() -> Bool { !tunnelPairs().isEmpty }
    static func tunnelIP() -> String? {
        tunnelPairs().first(where: { $0.peer != nil })?.peer ?? tunnelPairs().first?.local
    }

    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func isLoopbackRange(_ ip: String) -> Bool {
        ip.hasPrefix("10.7.")
    }

    private static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("tap") || name.hasPrefix("ppp")
    }
}
