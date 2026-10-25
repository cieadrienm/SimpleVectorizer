import Darwin
import Foundation

/// Physical AxiDraw hardware models and their maximum travel dimensions in millimeters.
public enum AxiDrawMachineModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case v3A4 = "v3_a4"
    case v3A3 = "v3_a3"
    case miniKit = "minikit_a6"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .v3A4: return "AxiDraw V3 / SE (A4 · 300 × 218 mm)"
        case .v3A3: return "AxiDraw V3/A3 / SE/A3 (A3 · 430 × 297 mm)"
        case .miniKit: return "AxiDraw MiniKit 2 (A6 · 160 × 101 mm)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .v3A4: return "V3 (A4)"
        case .v3A3: return "V3/A3"
        case .miniKit: return "MiniKit"
        }
    }

    public var maxTravelWidthMM: Double {
        switch self {
        case .v3A4: return 300.0
        case .v3A3: return 430.0
        case .miniKit: return 160.0
        }
    }

    public var maxTravelHeightMM: Double {
        switch self {
        case .v3A4: return 218.0
        case .v3A3: return 297.0
        case .miniKit: return 101.0
        }
    }
}

/// Configuration parameters for direct AxiDraw EBB hardware control.
public struct AxiDrawConfig: Equatable, Codable, Sendable {
    public var machineModel: AxiDrawMachineModel = .v3A4
    public var penUpPercent: Int = 60         // 0...100% -> SC,5
    public var penDownPercent: Int = 30       // 0...100% -> SC,4
    public var penDelayMs: Int = 150          // Delay after SP,0 / SP,1 in ms
    public var drawSpeedPercent: Int = 40     // 5...100% -> mm/s when pen is down
    public var travelSpeedPercent: Int = 75   // 10...100% -> mm/s when pen is up
    public var pauseBetweenPenLayers: Bool = true
    public var simulationSpeedMultiplier: Double = 4.0

    public init() {}

    /// Converts a servo height percentage (0...100%) to EBB 83.3 ns timer ticks (`SC,4` / `SC,5`).
    public static func servoTicks(forPercent percent: Int) -> Int {
        let clamped = max(0, min(100, percent))
        return 9855 + 178 * clamped
    }

    /// Pen-down linear speed in mm/s (`5% -> 8 mm/s`, `40% -> 38 mm/s`, `100% -> 85 mm/s`).
    public var drawSpeedMMPerSec: Double {
        let p = Double(max(5, min(100, drawSpeedPercent))) / 100.0
        return 4.0 + p * 81.0
    }

    /// Pen-up rapid travel speed in mm/s (`10% -> 25 mm/s`, `75% -> 115 mm/s`, `100% -> 150 mm/s`).
    public var travelSpeedMMPerSec: Double {
        let p = Double(max(10, min(100, travelSpeedPercent))) / 100.0
        return 12.0 + p * 138.0
    }
}

/// Discovered USB serial port or built-in virtual simulator for AxiDraw.
public struct AxiDrawPortDevice: Identifiable, Equatable, Hashable, Sendable {
    public static let simulatorPath = "virtual://axidraw-simulator"

    public let path: String
    public let displayName: String
    public let isSimulator: Bool

    public var id: String { path }

    public init(path: String, displayName: String, isSimulator: Bool) {
        self.path = path
        self.displayName = displayName
        self.isSimulator = isSimulator
    }

    public static var simulator: AxiDrawPortDevice {
        AxiDrawPortDevice(
            path: simulatorPath,
            displayName: L("Simulateur AxiDraw (Virtuel)", "AxiDraw Simulator (Virtual)"),
            isSimulator: true
        )
    }
}

/// Atomic motion / servo command in a compiled AxiDraw plot job.
public enum AxiDrawJobStep: Sendable, Equatable {
    case beginLayer(penIndex: Int, penName: String, widthMM: Double)
    case setPen(down: Bool, delayMs: Int)
    case moveXY(targetMM: VectorPoint, penDown: Bool, pathID: Int?)
}

/// Compiled sequence of AxiDraw hardware steps ready to stream to EBB or simulator.
public struct AxiDrawCompiledJob: Sendable {
    public let steps: [AxiDrawJobStep]
    public let totalDrawMM: Double
    public let totalTravelMM: Double
    public let boundingBoxMM: (min: VectorPoint, max: VectorPoint)?

    /// Compiles a `VectorizationResult` into discretized sub-millimeter motion steps (`0.25 mm` chord tolerance on cubic Béziers).
    public static func compile(
        result: VectorizationResult,
        config: AxiDrawConfig,
        onlyPenIndex: Int? = nil
    ) -> AxiDrawCompiledJob {
        let transform = result.pageTransform
        let maxW = config.machineModel.maxTravelWidthMM
        let maxH = config.machineModel.maxTravelHeightMM

        func clampMM(_ ptPx: VectorPoint) -> VectorPoint {
            let mm = transform.toPage(ptPx)
            return VectorPoint(
                x: max(0.0, min(maxW, mm.x)),
                y: max(0.0, min(maxH, mm.y))
            )
        }

        var steps: [AxiDrawJobStep] = []
        var totalDraw = 0.0
        var totalTravel = 0.0
        var currentPos = VectorPoint(x: 0, y: 0)
        var penIsDown = false

        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude

        func includeBounds(_ p: VectorPoint) {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }

        let activeLayers = result.layers.filter { layer in
            guard layer.visible, !layer.paths.isEmpty else { return false }
            if let only = onlyPenIndex { return layer.index == only }
            return true
        }

        for (layerOffset, layer) in activeLayers.enumerated() {
            if layerOffset > 0 && config.pauseBetweenPenLayers {
                if penIsDown {
                    steps.append(.setPen(down: false, delayMs: config.penDelayMs))
                    penIsDown = false
                }
                if currentPos.distance(to: .zero) > 0.05 {
                    totalTravel += currentPos.distance(to: .zero)
                    steps.append(.moveXY(targetMM: .zero, penDown: false, pathID: nil))
                    currentPos = .zero
                }
                steps.append(.beginLayer(penIndex: layer.index, penName: layer.name, widthMM: layer.widthMM))
            }

            for vp in layer.paths {
                let polyMM = discretizePathToMM(vp, clampMM: clampMM)
                guard polyMM.count >= 2 else { continue }

                let startMM = polyMM[0]
                includeBounds(startMM)

                // Rapid travel to stroke start if needed
                let gap = currentPos.distance(to: startMM)
                if gap > 0.08 {
                    if penIsDown {
                        steps.append(.setPen(down: false, delayMs: config.penDelayMs))
                        penIsDown = false
                    }
                    totalTravel += gap
                    steps.append(.moveXY(targetMM: startMM, penDown: false, pathID: vp.id))
                    currentPos = startMM
                }

                // Lower pen if raised
                if !penIsDown {
                    steps.append(.setPen(down: true, delayMs: config.penDelayMs))
                    penIsDown = true
                }

                // Trace all vertices of the discretized stroke
                for i in 1..<polyMM.count {
                    let nextMM = polyMM[i]
                    includeBounds(nextMM)
                    let segLen = currentPos.distance(to: nextMM)
                    guard segLen > 0.02 else { continue }
                    totalDraw += segLen
                    steps.append(.moveXY(targetMM: nextMM, penDown: true, pathID: vp.id))
                    currentPos = nextMM
                }
            }
        }

        // Lift pen and return to (0, 0) at end of job
        if penIsDown {
            steps.append(.setPen(down: false, delayMs: config.penDelayMs))
        }
        if currentPos.distance(to: .zero) > 0.05 {
            totalTravel += currentPos.distance(to: .zero)
            steps.append(.moveXY(targetMM: .zero, penDown: false, pathID: nil))
        }

        let bbox: (min: VectorPoint, max: VectorPoint)?
        if minX <= maxX && minY <= maxY {
            bbox = (VectorPoint(x: minX, y: minY), VectorPoint(x: maxX, y: maxY))
        } else {
            bbox = nil
        }

        return AxiDrawCompiledJob(
            steps: steps,
            totalDrawMM: totalDraw,
            totalTravelMM: totalTravel,
            boundingBoxMM: bbox
        )
    }

    /// Compiles a pen-up bounding-box framing tour to visually check paper alignment before plotting.
    public static func compileBoundingBoxTour(
        result: VectorizationResult,
        config: AxiDrawConfig
    ) -> AxiDrawCompiledJob {
        let base = compile(result: result, config: config)
        guard let box = base.boundingBoxMM else {
            return AxiDrawCompiledJob(steps: [], totalDrawMM: 0, totalTravelMM: 0, boundingBoxMM: nil)
        }
        let c0 = VectorPoint(x: box.min.x, y: box.min.y)
        let c1 = VectorPoint(x: box.max.x, y: box.min.y)
        let c2 = VectorPoint(x: box.max.x, y: box.max.y)
        let c3 = VectorPoint(x: box.min.x, y: box.max.y)
        let corners = [c0, c1, c2, c3, c0, .zero]

        var steps: [AxiDrawJobStep] = [.setPen(down: false, delayMs: config.penDelayMs)]
        var prev = VectorPoint.zero
        var travel = 0.0
        for pt in corners {
            travel += prev.distance(to: pt)
            steps.append(.moveXY(targetMM: pt, penDown: false, pathID: nil))
            prev = pt
        }
        return AxiDrawCompiledJob(steps: steps, totalDrawMM: 0, totalTravelMM: travel, boundingBoxMM: box)
    }

    private static func discretizePathToMM(
        _ vp: VectorPath,
        clampMM: (VectorPoint) -> VectorPoint
    ) -> [VectorPoint] {
        if !vp.beziers.isEmpty {
            var out: [VectorPoint] = []
            out.reserveCapacity(vp.beziers.count * 6 + 1)
            out.append(clampMM(vp.beziers[0].p0))
            for seg in vp.beziers {
                let p0 = clampMM(seg.p0)
                let c1 = clampMM(seg.c1)
                let c2 = clampMM(seg.c2)
                let p3 = clampMM(seg.p3)
                let approxLen = p0.distance(to: c1) + c1.distance(to: c2) + c2.distance(to: p3)
                let subdivisions = max(2, min(32, Int((approxLen / 0.45).rounded(.up))))
                for s in 1...subdivisions {
                    let t = Double(s) / Double(subdivisions)
                    let mt = 1.0 - t
                    let b0 = mt * mt * mt
                    let b1 = 3.0 * t * mt * mt
                    let b2 = 3.0 * t * t * mt
                    let b3 = t * t * t
                    let pt = VectorPoint(
                        x: b0 * p0.x + b1 * c1.x + b2 * c2.x + b3 * p3.x,
                        y: b0 * p0.y + b1 * c1.y + b2 * c2.y + b3 * p3.y
                    )
                    out.append(pt)
                }
            }
            return out
        } else {
            return vp.points.map(clampMM)
        }
    }
}

// MARK: - Low-Level POSIX EBB USB Serial Transport

/// Non-blocking / timeout-guarded POSIX `termios` transport for EiBotBoard (`/dev/cu.usbmodem*`) and virtual simulator.
public final class EBBSerialTransport: @unchecked Sendable {
    public static let stepsPerMM: Double = 80.0 // 2032 steps/in at 1/16 microstepping

    private var fd: Int32 = -1
    public let device: AxiDrawPortDevice
    public private(set) var firmwareVersion: String = ""

    public var isOpen: Bool {
        device.isSimulator || fd >= 0
    }

    public init(device: AxiDrawPortDevice) {
        self.device = device
    }

    deinit {
        close()
    }

    /// Scans `/dev` for connected USB CDC modem devices (`cu.usbmodem*`, `cu.usbserial*`) plus the virtual simulator.
    public static func availablePorts() -> [AxiDrawPortDevice] {
        var ports: [AxiDrawPortDevice] = []
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: "/dev") {
            let matching = entries.filter { name in
                name.hasPrefix("cu.usbmodem") || name.hasPrefix("cu.usbserial")
            }.sorted()
            for name in matching {
                let fullPath = "/dev/\(name)"
                ports.append(
                    AxiDrawPortDevice(
                        path: fullPath,
                        displayName: "AxiDraw USB (\(name))",
                        isSimulator: false
                    )
                )
            }
        }
        ports.append(.simulator)
        return ports
    }

    public func open() throws {
        if device.isSimulator {
            firmwareVersion = "EBBv13_and_above EB Firmware Version 2.8.1 (Sim)"
            return
        }
        guard fd < 0 else { return }

        let opened = Darwin.open(device.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard opened >= 0 else {
            let err = String(cString: strerror(errno))
            throw NSError(
                domain: "EBBSerialTransport",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: L("Impossible d'ouvrir \(device.path) : \(err)", "Could not open \(device.path): \(err)")]
            )
        }

        // Clear O_NONBLOCK after open and configure raw 8N1 serial via termios
        _ = fcntl(opened, F_SETFL, 0)
        var tty = termios()
        if tcgetattr(opened, &tty) == 0 {
            cfmakeraw(&tty)
            cfsetspeed(&tty, speed_t(B115200))
            tty.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
            tty.c_cflag &= ~tcflag_t(PARENB | CSTOPB)
            _ = tcsetattr(opened, TCSANOW, &tty)
        }
        tcflush(opened, TCIOFLUSH)
        self.fd = opened

        // Query EBB firmware version ("V\r")
        if let resp = try? sendQuery("V"), !resp.isEmpty {
            self.firmwareVersion = resp.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            self.firmwareVersion = "EBB USB (\(device.displayName))"
        }
    }

    public func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    /// Sends an EBB command expecting `"OK\r\n"`.
    public func sendCommand(_ command: String, timeoutMs: Int = 2500) throws {
        if device.isSimulator { return }
        let response = try sendRaw(command, timeoutMs: timeoutMs)
        if response.uppercased().contains("!") || response.uppercased().contains("ERR") {
            throw NSError(
                domain: "EBBSerialTransport",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "EBB: \(response.trimmingCharacters(in: .whitespacesAndNewlines))"]
            )
        }
    }

    /// Sends a query command (such as `"V"`) and returns the first response line.
    public func sendQuery(_ command: String, timeoutMs: Int = 1000) throws -> String {
        if device.isSimulator {
            return "EBBv13_and_above EB Firmware Version 2.8.1 (Sim)"
        }
        return try sendRaw(command, timeoutMs: timeoutMs)
    }

    private func sendRaw(_ command: String, timeoutMs: Int) throws -> String {
        guard fd >= 0 else {
            throw NSError(
                domain: "EBBSerialTransport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L("Port série AxiDraw fermé", "AxiDraw serial port closed")]
            )
        }
        let line = command.hasSuffix("\r") ? command : (command + "\r")
        let bytes = Array(line.utf8)
        let written = bytes.withUnsafeBufferPointer { buf -> Int in
            guard let base = buf.baseAddress else { return -1 }
            return Darwin.write(fd, base, buf.count)
        }
        guard written == bytes.count else {
            throw NSError(
                domain: "EBBSerialTransport",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: L("Erreur d'écriture USB AxiDraw", "AxiDraw USB write error")]
            )
        }

        // Read until '\n' or timeout using poll()
        var buffer: [UInt8] = []
        buffer.reserveCapacity(64)
        let deadline = CFAbsoluteTimeGetCurrent() + Double(timeoutMs) / 1000.0
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)

        while CFAbsoluteTimeGetCurrent() < deadline {
            let remainingMs = max(10, Int((deadline - CFAbsoluteTimeGetCurrent()) * 1000.0))
            let pr = Darwin.poll(&pfd, 1, Int32(min(50, remainingMs)))
            if pr > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                var byte: UInt8 = 0
                let n = Darwin.read(fd, &byte, 1)
                if n == 1 {
                    buffer.append(byte)
                    if byte == 0x0A { // '\n'
                        break
                    }
                } else if n <= 0 {
                    break
                }
            }
        }
        return String(decoding: buffer, as: UTF8.self)
    }
}
