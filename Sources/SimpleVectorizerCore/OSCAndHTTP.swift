import Darwin
import Foundation

public let kSimpleVectorizerDefaultOSCInPort: UInt16 = 9140
public let kSimpleVectorizerDefaultOSCOutPort: UInt16 = 9141
public let kSimpleVectorizerDefaultHTTPPort: UInt16 = 17940

/// Minimal, zero-dependency OSC 1.0 packet decoder & encoder.
public enum OSCCodec {
    public enum Value: Equatable, Sendable {
        case int(Int32)
        case float(Float32)
        case string(String)
        case bool(Bool)

        public var boolValue: Bool? {
            switch self {
            case .bool(let b): return b
            case .int(let i): return i != 0
            case .float(let f): return f != 0
            case .string(let s):
                switch s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
                case "1", "true", "on", "yes", "oui": return true
                case "0", "false", "off", "no", "non": return false
                default: return nil
                }
            }
        }

        public var doubleValue: Double? {
            switch self {
            case .int(let i): return Double(i)
            case .float(let f): return Double(f)
            case .bool(let b): return b ? 1.0 : 0.0
            case .string(let s): return Double(s.replacingOccurrences(of: ",", with: "."))
            }
        }

        public var intValue: Int? {
            switch self {
            case .int(let i): return Int(i)
            case .float(let f): return Int(f.rounded())
            case .bool(let b): return b ? 1 : 0
            case .string(let s): return Int(s)
            }
        }

        public var stringValue: String {
            switch self {
            case .int(let i): return "\(i)"
            case .float(let f): return "\(f)"
            case .string(let s): return s
            case .bool(let b): return b ? "1" : "0"
            }
        }
    }

    public struct Message: Equatable, Sendable {
        public var address: String
        public var arguments: [Value]

        public init(address: String, arguments: [Value] = []) {
            self.address = address
            self.arguments = arguments
        }
    }

    public static func encode(_ message: Message) -> Data {
        var data = Data()
        appendPaddedString(message.address, to: &data)
        var typeTag = ","
        for arg in message.arguments {
            switch arg {
            case .int: typeTag.append("i")
            case .float: typeTag.append("f")
            case .string: typeTag.append("s")
            case .bool(let b): typeTag.append(b ? "T" : "F")
            }
        }
        appendPaddedString(typeTag, to: &data)
        for arg in message.arguments {
            switch arg {
            case .int(let v):
                var be = v.bigEndian
                withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
            case .float(let v):
                var be = v.bitPattern.bigEndian
                withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
            case .string(let s):
                appendPaddedString(s, to: &data)
            case .bool:
                break
            }
        }
        return data
    }

    public static func decode(_ data: Data) -> [Message] {
        let bytes = Array(data)
        guard !bytes.isEmpty else { return [] }
        if bytes.count >= 16, String(decoding: bytes[0..<7], as: UTF8.self) == "#bundle" {
            var offset = 16
            var out: [Message] = []
            while offset + 4 <= bytes.count {
                let size = Int(readUInt32(bytes, at: offset))
                offset += 4
                guard size > 0, offset + size <= bytes.count else { break }
                let slice = Data(bytes[offset..<(offset + size)])
                out.append(contentsOf: decode(slice))
                offset += size
            }
            return out
        }

        var idx = 0
        guard let address = readPaddedString(bytes, index: &idx), address.hasPrefix("/") else {
            return []
        }
        guard let tags = readPaddedString(bytes, index: &idx), tags.hasPrefix(",") else {
            return [Message(address: address, arguments: [])]
        }

        var args: [Value] = []
        for ch in tags.dropFirst() {
            switch ch {
            case "i":
                guard idx + 4 <= bytes.count else { break }
                let raw = Int32(bitPattern: readUInt32(bytes, at: idx))
                idx += 4
                args.append(.int(raw))
            case "f":
                guard idx + 4 <= bytes.count else { break }
                let bits = readUInt32(bytes, at: idx)
                idx += 4
                args.append(.float(Float32(bitPattern: bits)))
            case "s":
                if let s = readPaddedString(bytes, index: &idx) {
                    args.append(.string(s))
                }
            case "T":
                args.append(.bool(true))
            case "F":
                args.append(.bool(false))
            default:
                break
            }
        }
        return [Message(address: address, arguments: args)]
    }

    private static func appendPaddedString(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
        data.append(0)
        while data.count % 4 != 0 {
            data.append(0)
        }
    }

    private static func readPaddedString(_ bytes: [UInt8], index: inout Int) -> String? {
        guard index < bytes.count else { return nil }
        var end = index
        while end < bytes.count && bytes[end] != 0 {
            end += 1
        }
        let str = String(decoding: bytes[index..<end], as: UTF8.self)
        let total = end - index + 1
        let padded = (total + 3) & ~3
        index = min(bytes.count, index + padded)
        return str
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}

/// UDP OSC server for receiving show/automation cues (`/simplevectorizer/...`).
public final class OSCUDPServer: @unchecked Sendable {
    public private(set) var port: UInt16
    public private(set) var isRunning = false
    private var socketFD: Int32 = -1
    private let lock = NSLock()
    private let handler: @Sendable (OSCCodec.Message) -> Void

    public init(port: UInt16 = kSimpleVectorizerDefaultOSCInPort, handler: @escaping @Sendable (OSCCodec.Message) -> Void) {
        self.port = port
        self.handler = handler
    }

    deinit {
        stop()
    }

    @discardableResult
    public func start() -> Bool {
        lock.lock()
        if isRunning {
            lock.unlock()
            return true
        }
        lock.unlock()

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindRes < 0 {
            Darwin.close(fd)
            return false
        }

        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &len)
            }
        }

        lock.lock()
        self.socketFD = fd
        self.port = UInt16(bigEndian: bound.sin_port)
        self.isRunning = true
        lock.unlock()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.receiveLoop(fd: fd)
        }
        return true
    }

    public func stop() {
        lock.lock()
        isRunning = false
        let fd = socketFD
        socketFD = -1
        lock.unlock()
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    private func receiveLoop(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            lock.lock()
            let active = isRunning
            lock.unlock()
            if !active { break }

            let n = Darwin.recv(fd, &buffer, buffer.count, 0)
            if n <= 0 {
                if errno == EINTR { continue }
                break
            }
            let data = Data(buffer[0..<n])
            let messages = OSCCodec.decode(data)
            for msg in messages {
                handler(msg)
            }
        }
    }

    public static func send(_ message: OSCCodec.Message, toHost host: String = "127.0.0.1", port: UInt16 = kSimpleVectorizerDefaultOSCOutPort) {
        let data = OSCCodec.encode(message)
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return }
        _ = data.withUnsafeBytes { ptr in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.sendto(fd, ptr.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
