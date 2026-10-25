import Foundation
import Observation
import SimpleVectorizerCore

enum AxiDrawRunState: Equatable {
    case disconnected
    case idle
    case plotting
    case pausedByUser
    case pausedForPenChange(penIndex: Int, penName: String, widthMM: Double)
    case framingBoundingBox
    case error(String)

    var isBusy: Bool {
        switch self {
        case .plotting, .framingBoundingBox:
            return true
        default:
            return false
        }
    }

    var isPaused: Bool {
        switch self {
        case .pausedByUser, .pausedForPenChange:
            return true
        default:
            return false
        }
    }
}

/// High-level `@MainActor` controller driving a physical AxiDraw over USB EBB serial (`/dev/cu.usbmodem*`) or the virtual simulator.
@Observable
@MainActor
final class AxiDrawPlotterController {
    var availablePorts: [AxiDrawPortDevice] = []
    var selectedPortPath: String = AxiDrawPortDevice.simulatorPath
    var config = AxiDrawConfig()
    var onlyPenLayerIndex: Int? = nil // nil = all visible pen layers

    private(set) var runState: AxiDrawRunState = .idle
    private(set) var firmwareVersion: String = ""
    private(set) var currentPosMM: VectorPoint = .zero
    private(set) var isPenDown: Bool = false
    private(set) var activePathID: Int? = nil
    private(set) var progressFraction: Double = 0.0
    private(set) var completedStepCount: Int = 0
    private(set) var totalStepCount: Int = 0
    private(set) var statusLog: String = L("Prêt (Origine 0, 0 mm)", "Ready (Home 0, 0 mm)")

    // Integer step position accumulator (at 80 steps/mm) to prevent any sub-step rounding drift
    private var currentStepsX: Int = 0
    private var currentStepsY: Int = 0
    private var transport: EBBSerialTransport? = nil
    private var plotTask: Task<Void, Never>? = nil
    private var pauseRequested: Bool = false
    private var stopRequested: Bool = false

    init() {
        refreshPorts()
    }

    var selectedDevice: AxiDrawPortDevice {
        availablePorts.first(where: { $0.path == selectedPortPath }) ?? .simulator
    }

    var isConnectedToHardware: Bool {
        !selectedDevice.isSimulator && (transport?.isOpen ?? false)
    }

    func refreshPorts() {
        let ports = EBBSerialTransport.availablePorts()
        self.availablePorts = ports
        // Prefer first physical USB AxiDraw port if available and currently on simulator
        if let physical = ports.first(where: { !$0.isSimulator }),
           selectedPortPath == AxiDrawPortDevice.simulatorPath || !ports.contains(where: { $0.path == selectedPortPath }) {
            selectedPortPath = physical.path
        } else if !ports.contains(where: { $0.path == selectedPortPath }) {
            selectedPortPath = AxiDrawPortDevice.simulatorPath
        }
    }

    @discardableResult
    func ensureConnected() -> Bool {
        let dev = selectedDevice
        if let existing = transport, existing.device == dev, existing.isOpen {
            return true
        }
        transport?.close()
        let t = EBBSerialTransport(device: dev)
        do {
            try t.open()
            self.transport = t
            self.firmwareVersion = t.firmwareVersion
            try configureEBBServoAndMotors(on: t)
            if case .error = runState {
                runState = .idle
            }
            return true
        } catch {
            self.runState = .error(error.localizedDescription)
            self.statusLog = error.localizedDescription
            return false
        }
    }

    private func configureEBBServoAndMotors(on t: EBBSerialTransport) throws {
        let downTicks = AxiDrawConfig.servoTicks(forPercent: config.penDownPercent)
        let upTicks = AxiDrawConfig.servoTicks(forPercent: config.penUpPercent)
        try t.sendCommand("SC,4,\(downTicks)") // Pen-Down servo position
        try t.sendCommand("SC,5,\(upTicks)")   // Pen-Up servo position
        try t.sendCommand("SC,10,65535")       // Fast servo rate
        try t.sendCommand("EM,1,1")            // Enable both motors at 1/16 microstepping (80 steps/mm)
    }

    func pushServoConfigIfConnected() {
        guard let t = transport, t.isOpen else { return }
        try? configureEBBServoAndMotors(on: t)
    }

    // MARK: - Direct Manual Jog & Setup Controls

    func raisePen() {
        guard ensureConnected(), let t = transport else { return }
        do {
            try configureEBBServoAndMotors(on: t)
            try t.sendCommand("SP,1,\(config.penDelayMs)")
            isPenDown = false
            statusLog = L("Stylo levé (\(config.penUpPercent) %)", "Pen raised (\(config.penUpPercent)%)")
        } catch {
            runState = .error(error.localizedDescription)
            statusLog = error.localizedDescription
        }
    }

    func lowerPen() {
        guard ensureConnected(), let t = transport else { return }
        do {
            try configureEBBServoAndMotors(on: t)
            try t.sendCommand("SP,0,\(config.penDelayMs)")
            isPenDown = true
            statusLog = L("Stylo baissé (\(config.penDownPercent) %)", "Pen lowered (\(config.penDownPercent)%)")
        } catch {
            runState = .error(error.localizedDescription)
            statusLog = error.localizedDescription
        }
    }

    func togglePen() {
        if isPenDown {
            raisePen()
        } else {
            lowerPen()
        }
    }

    func unlockMotorsAndZeroOrigin() {
        stopPlot()
        guard ensureConnected(), let t = transport else { return }
        do {
            try t.sendCommand("SP,1,\(config.penDelayMs)")
            try t.sendCommand("EM,0,0")
            isPenDown = false
            currentPosMM = .zero
            currentStepsX = 0
            currentStepsY = 0
            activePathID = nil
            runState = .idle
            statusLog = L("Moteurs débloqués — placez la tête à l'origine (0, 0)", "Motors unlocked — move carriage to home (0, 0)")
        } catch {
            runState = .error(error.localizedDescription)
            statusLog = error.localizedDescription
        }
    }

    func returnToHome() {
        guard !runState.isBusy else { return }
        guard ensureConnected(), let t = transport else { return }
        do {
            try configureEBBServoAndMotors(on: t)
            try t.sendCommand("SP,1,\(config.penDelayMs)")
            isPenDown = false
            let dxSteps = -currentStepsX
            let dySteps = -currentStepsY
            if dxSteps != 0 || dySteps != 0 {
                let distMM = currentPosMM.distance(to: .zero)
                let durationMs = max(25, Int((distMM / max(10.0, config.travelSpeedMMPerSec) * 1000.0).rounded()))
                try t.sendCommand("XM,\(durationMs),\(dxSteps),\(dySteps)", timeoutMs: durationMs + 2500)
            }
            currentPosMM = .zero
            currentStepsX = 0
            currentStepsY = 0
            activePathID = nil
            statusLog = L("Retour à l'origine (0, 0 mm)", "Returned to home (0, 0 mm)")
        } catch {
            runState = .error(error.localizedDescription)
            statusLog = error.localizedDescription
        }
    }

    // MARK: - Streaming Plot & Bounding-Box Framing

    func startBoundingBoxFrame(result: VectorizationResult) {
        stopPlot()
        guard ensureConnected() else { return }
        let job = AxiDrawCompiledJob.compileBoundingBoxTour(result: result, config: config)
        guard !job.steps.isEmpty else {
            statusLog = L("Aucun chemin à cadrer", "No paths to frame")
            return
        }
        launchJob(job, startIndex: 0, isFraming: true)
    }

    func startPlot(result: VectorizationResult) {
        stopPlot()
        guard ensureConnected() else { return }
        let job = AxiDrawCompiledJob.compile(
            result: result,
            config: config,
            onlyPenIndex: onlyPenLayerIndex
        )
        guard !job.steps.isEmpty else {
            statusLog = L("Aucun chemin visible à tracer", "No visible paths to plot")
            return
        }
        launchJob(job, startIndex: 0, isFraming: false)
    }

    func pausePlot() {
        guard runState.isBusy else { return }
        pauseRequested = true
        statusLog = L("Mise en pause…", "Pausing…")
    }

    func resumePlot() {
        guard let pausedJob = activeCompiledJob, runState.isPaused else { return }
        pauseRequested = false
        stopRequested = false
        launchJob(pausedJob, startIndex: completedStepCount, isFraming: false)
    }

    func stopPlot() {
        stopRequested = true
        pauseRequested = false
        plotTask?.cancel()
        plotTask = nil
        activeCompiledJob = nil
        if let t = transport, t.isOpen {
            try? t.sendCommand("ES")
            try? t.sendCommand("SP,1,\(config.penDelayMs)")
        }
        isPenDown = false
        activePathID = nil
        progressFraction = 0.0
        completedStepCount = 0
        totalStepCount = 0
        if case .error = runState {
            // Preserve error state if any
        } else {
            runState = .idle
        }
        statusLog = L("Tracé arrêté (stylo levé)", "Plot stopped (pen up)")
    }

    private var activeCompiledJob: AxiDrawCompiledJob? = nil

    private func launchJob(_ job: AxiDrawCompiledJob, startIndex: Int, isFraming: Bool) {
        guard let t = transport else { return }
        do {
            try configureEBBServoAndMotors(on: t)
        } catch {
            runState = .error(error.localizedDescription)
            statusLog = error.localizedDescription
            return
        }

        self.activeCompiledJob = job
        self.totalStepCount = job.steps.count
        self.completedStepCount = startIndex
        self.pauseRequested = false
        self.stopRequested = false
        self.runState = isFraming ? .framingBoundingBox : .plotting
        self.statusLog = isFraming
            ? L("Cadrage du rectangle englobant (stylo levé)…", "Framing bounding box (pen up)…")
            : L("Tracé AxiDraw en cours…", "AxiDraw plotting in progress…")

        let isSim = t.device.isSimulator
        let simAccel = max(1.0, config.simulationSpeedMultiplier)

        plotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var idx = startIndex
            while idx < job.steps.count {
                if Task.isCancelled || self.stopRequested {
                    return
                }
                if self.pauseRequested {
                    try? t.sendCommand("SP,1,\(self.config.penDelayMs)")
                    self.isPenDown = false
                    self.completedStepCount = idx
                    self.runState = .pausedByUser
                    self.statusLog = L("En pause (\(idx)/\(job.steps.count)) — cliquer sur Reprendre", "Paused (\(idx)/\(job.steps.count)) — click Resume")
                    return
                }

                let step = job.steps[idx]
                switch step {
                case let .beginLayer(penIndex, penName, widthMM):
                    self.completedStepCount = idx + 1
                    self.progressFraction = Double(idx + 1) / Double(max(1, job.steps.count))
                    self.isPenDown = false
                    self.activePathID = nil
                    self.runState = .pausedForPenChange(penIndex: penIndex, penName: penName, widthMM: widthMM)
                    self.statusLog = L(
                        "Changement de stylo : insérez \(penName) (\(Format.decimal(widthMM, digits: 1)) mm) puis cliquez sur Reprendre",
                        "Pen change: insert \(penName) (\(Format.decimal(widthMM, digits: 1)) mm) then click Resume"
                    )
                    return

                case let .setPen(down, delayMs):
                    do {
                        try t.sendCommand("SP,\(down ? 0 : 1),\(delayMs)", timeoutMs: delayMs + 1500)
                        self.isPenDown = down
                        let sleepMs = isSim ? max(8, Int(Double(delayMs) / simAccel)) : delayMs
                        try? await Task.sleep(for: .milliseconds(sleepMs))
                    } catch {
                        self.runState = .error(error.localizedDescription)
                        self.statusLog = error.localizedDescription
                        return
                    }

                case let .moveXY(targetMM, penDown, pathID):
                    let targetStepsX = Int((targetMM.x * EBBSerialTransport.stepsPerMM).rounded())
                    let targetStepsY = Int((targetMM.y * EBBSerialTransport.stepsPerMM).rounded())
                    let dxSteps = targetStepsX - self.currentStepsX
                    let dySteps = targetStepsY - self.currentStepsY
                    let distMM = self.currentPosMM.distance(to: targetMM)
                    let speedMMPerSec = penDown ? self.config.drawSpeedMMPerSec : self.config.travelSpeedMMPerSec
                    let durationMs = max(4, Int((distMM / max(2.0, speedMMPerSec) * 1000.0).rounded()))

                    if dxSteps != 0 || dySteps != 0 {
                        do {
                            try t.sendCommand("XM,\(durationMs),\(dxSteps),\(dySteps)", timeoutMs: durationMs + 2500)
                        } catch {
                            self.runState = .error(error.localizedDescription)
                            self.statusLog = error.localizedDescription
                            return
                        }
                    }

                    self.currentStepsX = targetStepsX
                    self.currentStepsY = targetStepsY
                    self.currentPosMM = targetMM
                    self.isPenDown = penDown
                    self.activePathID = pathID

                    let sleepMs = isSim ? max(2, Int(Double(durationMs) / simAccel)) : min(durationMs, 40)
                    if sleepMs >= 2 {
                        try? await Task.sleep(for: .milliseconds(sleepMs))
                    }
                }

                idx += 1
                self.completedStepCount = idx
                self.progressFraction = Double(idx) / Double(max(1, job.steps.count))
                if idx % 12 == 0 || idx == job.steps.count {
                    let pct = Int((self.progressFraction * 100.0).rounded())
                    self.statusLog = isFraming
                        ? L("Cadrage \(pct) % (\(Int(self.currentPosMM.x.rounded())), \(Int(self.currentPosMM.y.rounded())) mm)", "Framing \(pct)% (\(Int(self.currentPosMM.x.rounded())), \(Int(self.currentPosMM.y.rounded())) mm)")
                        : L("Tracé \(pct) % — (\(Int(self.currentPosMM.x.rounded())), \(Int(self.currentPosMM.y.rounded())) mm)", "Plotting \(pct)% — (\(Int(self.currentPosMM.x.rounded())), \(Int(self.currentPosMM.y.rounded())) mm)")
                }
            }

            self.isPenDown = false
            self.activePathID = nil
            self.progressFraction = 1.0
            self.activeCompiledJob = nil
            self.runState = .idle
            self.statusLog = isFraming
                ? L("Cadrage terminé — retour à (0, 0 mm)", "Framing complete — returned to (0, 0 mm)")
                : L("Tracé AxiDraw terminé — retour à (0, 0 mm)", "AxiDraw plot complete — returned to (0, 0 mm)")
        }
    }
}
