import Darwin
import Foundation

final class NetworkStatsMonitor {
    var onUpdate: ((TrafficRates) -> Void)?

    private let interval: TimeInterval
    private let smoothingAlpha: Double
    private let nettopSampler = NettopTrafficSampler()
    private var timer: Timer?
    private var previousSnapshot: CounterSnapshot?
    private var smoothedUpload: Double = 0
    private var smoothedDownload: Double = 0

    init(interval: TimeInterval = 0.5, smoothingAlpha: Double = 0.3) {
        self.interval = interval
        self.smoothingAlpha = smoothingAlpha
    }

    func start() {
        stop()
        previousSnapshot = Self.readSnapshot()

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousSnapshot = nil
        smoothedUpload = 0
        smoothedDownload = 0
    }

    func pause() {
        timer?.fireDate = .distantFuture
    }

    func resume() {
        previousSnapshot = Self.readSnapshot()
        timer?.fireDate = Date(timeIntervalSinceNow: interval)
    }

    private func sample() {
        guard let current = Self.readSnapshot() else {
            publish(upload: 0, download: 0, source: .interfaceCounters, interfaceRates: [])
            return
        }

        defer {
            previousSnapshot = current
        }

        guard let previous = previousSnapshot else {
            return
        }

        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            return
        }

        var rawRates = Self.rates(from: previous, to: current, elapsed: elapsed)
        var source: TrafficSource = .interfaceCounters

        if rawRates.download < 1, let fallbackRates = nettopSampler.sample() {
            if fallbackRates.download > rawRates.download {
                rawRates.download = fallbackRates.download
                source = .nettopFallback
            }

            if rawRates.upload < 1, fallbackRates.upload > rawRates.upload {
                rawRates.upload = fallbackRates.upload
                source = .nettopFallback
            }
        }

        smoothedDownload = smooth(previous: smoothedDownload, raw: rawRates.download)
        smoothedUpload = smooth(previous: smoothedUpload, raw: rawRates.upload)

        publish(
            upload: smoothedUpload,
            download: smoothedDownload,
            source: source,
            interfaceRates: rawRates.interfaceRates
        )
    }

    private func smooth(previous: Double, raw: Double) -> Double {
        let value = previous * (1 - smoothingAlpha) + raw * smoothingAlpha
        return value < 1 ? 0 : value
    }

    private func publish(
        upload: Double,
        download: Double,
        source: TrafficSource,
        interfaceRates: [InterfaceTrafficRate]
    ) {
        onUpdate?(
            TrafficRates(
                uploadBytesPerSecond: upload,
                downloadBytesPerSecond: download,
                timestamp: Date(),
                source: source,
                interfaceRates: interfaceRates
            )
        )
    }

    private struct InterfaceCounters {
        let name: String
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private struct CounterSnapshot {
        let interfaces: [UInt16: InterfaceCounters]
        let timestamp: Date
    }

    private static func rates(
        from previous: CounterSnapshot,
        to current: CounterSnapshot,
        elapsed: TimeInterval
    ) -> (upload: Double, download: Double, interfaceRates: [InterfaceTrafficRate]) {
        var bytesInDelta: UInt64 = 0
        var bytesOutDelta: UInt64 = 0
        var interfaceRates: [InterfaceTrafficRate] = []

        for (interfaceIndex, counters) in current.interfaces {
            guard let oldCounters = previous.interfaces[interfaceIndex] else {
                continue
            }

            if counters.bytesIn >= oldCounters.bytesIn {
                bytesInDelta += counters.bytesIn - oldCounters.bytesIn
            }

            if counters.bytesOut >= oldCounters.bytesOut {
                bytesOutDelta += counters.bytesOut - oldCounters.bytesOut
            }

            let interfaceDownload = counters.bytesIn >= oldCounters.bytesIn
                ? Double(counters.bytesIn - oldCounters.bytesIn) / elapsed
                : 0
            let interfaceUpload = counters.bytesOut >= oldCounters.bytesOut
                ? Double(counters.bytesOut - oldCounters.bytesOut) / elapsed
                : 0

            if interfaceDownload >= 1 || interfaceUpload >= 1 {
                interfaceRates.append(
                    InterfaceTrafficRate(
                        name: counters.name,
                        uploadBytesPerSecond: interfaceUpload,
                        downloadBytesPerSecond: interfaceDownload
                    )
                )
            }
        }

        return (
            upload: Double(bytesOutDelta) / elapsed,
            download: Double(bytesInDelta) / elapsed,
            interfaceRates: interfaceRates.sorted { $0.totalBytesPerSecond > $1.totalBytesPerSecond }
        )
    }

    private static func readSnapshot() -> CounterSnapshot? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0

        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: length,
            alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer {
            buffer.deallocate()
        }

        guard sysctl(&mib, u_int(mib.count), buffer, &length, nil, 0) == 0 else {
            return nil
        }

        var offset = 0
        var interfaces: [UInt16: InterfaceCounters] = [:]

        while offset < length {
            let pointer = buffer.advanced(by: offset)
            let header = pointer.assumingMemoryBound(to: if_msghdr.self).pointee
            let messageLength = Int(header.ifm_msglen)

            guard messageLength > 0 else {
                break
            }

            if header.ifm_type == RTM_IFINFO2 {
                let info = pointer.assumingMemoryBound(to: if_msghdr2.self).pointee
                let flags = info.ifm_flags

                if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
                    interfaces[info.ifm_index] = InterfaceCounters(
                        name: interfaceName(for: info.ifm_index),
                        bytesIn: info.ifm_data.ifi_ibytes,
                        bytesOut: info.ifm_data.ifi_obytes
                    )
                }
            }

            offset += messageLength
        }

        return CounterSnapshot(interfaces: interfaces, timestamp: Date())
    }

    private static func interfaceName(for index: UInt16) -> String {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(IF_NAMESIZE))
        defer {
            buffer.deallocate()
        }

        guard let name = if_indextoname(UInt32(index), buffer) else {
            return "#\(index)"
        }

        return String(cString: name)
    }
}

private final class NettopTrafficSampler {
    private var previousSnapshot: Snapshot?

    func sample() -> (upload: Double, download: Double)? {
        guard let current = readSnapshot() else {
            return nil
        }

        defer {
            previousSnapshot = current
        }

        guard let previous = previousSnapshot else {
            return nil
        }

        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0 else {
            return nil
        }

        var bytesInDelta: UInt64 = 0
        var bytesOutDelta: UInt64 = 0

        for (key, counters) in current.processes {
            guard let oldCounters = previous.processes[key] else {
                continue
            }

            if counters.bytesIn >= oldCounters.bytesIn {
                bytesInDelta += counters.bytesIn - oldCounters.bytesIn
            }

            if counters.bytesOut >= oldCounters.bytesOut {
                bytesOutDelta += counters.bytesOut - oldCounters.bytesOut
            }
        }

        return (
            upload: Double(bytesOutDelta) / elapsed,
            download: Double(bytesInDelta) / elapsed
        )
    }

    private struct Counters {
        let bytesIn: UInt64
        let bytesOut: UInt64
    }

    private struct Snapshot {
        let processes: [String: Counters]
        let timestamp: Date
    }

    private func readSnapshot() -> Snapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        var processes: [String: Counters] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3 else {
                continue
            }

            let key = String(columns[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key != "interface" else {
                continue
            }

            let bytesInText = String(columns[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bytesOutText = String(columns[2]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let bytesIn = UInt64(bytesInText), let bytesOut = UInt64(bytesOutText) else {
                continue
            }

            processes[key] = Counters(bytesIn: bytesIn, bytesOut: bytesOut)
        }

        return Snapshot(processes: processes, timestamp: Date())
    }
}
