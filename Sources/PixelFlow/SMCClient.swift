import Foundation
import IOKit

struct FanSpeed {
    let currentRPM: Double
    let minRPM: Double?
    let maxRPM: Double?
}

struct SMCTemperatureSample {
    let celsius: Double
    let key: String
}

struct SMCFanSpeedSample {
    let speed: FanSpeed
    let key: String
}

enum SMCOpenResult {
    case opened(SMCClient)
    case unavailable(String)
}

final class SMCClient {
    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCKeyData {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private enum Command: UInt8 {
        case readBytes = 5
        case readKeyInfo = 9
    }

    private static let temperatureKeys = [
        "TC0P", "TC0E", "TC0F", "TC0D", "TC0H", "TC0C",
        "TC1C", "TC2C", "Tp09", "Tp0T", "Tp0P"
    ]

    private let connection: io_connect_t

    static func open() -> SMCOpenResult {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            return .unavailable("未发现 AppleSMC 服务")
        }

        var connection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)

        guard result == KERN_SUCCESS else {
            return .unavailable("AppleSMC 打开失败 \(kernelResultDescription(result))")
        }

        return .opened(SMCClient(connection: connection))
    }

    private init(connection: io_connect_t) {
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func cpuTemperatureCelsius() -> Double? {
        cpuTemperatureSample()?.celsius
    }

    func cpuTemperatureSample() -> SMCTemperatureSample? {
        for key in Self.temperatureKeys {
            guard let value = readDouble(key), value > 0, value < 130 else {
                continue
            }

            return SMCTemperatureSample(celsius: value, key: key)
        }

        return nil
    }

    func primaryFanSpeedRPM() -> FanSpeed? {
        primaryFanSpeedSample()?.speed
    }

    func primaryFanSpeedSample() -> SMCFanSpeedSample? {
        if let fanCount = readDouble("FNum"), fanCount > 0 {
            for index in 0..<Int(fanCount) {
                guard let currentRPM = readDouble("F\(index)Ac") else {
                    continue
                }

                return SMCFanSpeedSample(
                    speed: FanSpeed(
                        currentRPM: currentRPM,
                        minRPM: readDouble("F\(index)Mn"),
                        maxRPM: readDouble("F\(index)Mx")
                    ),
                    key: "F\(index)Ac"
                )
            }
        }

        guard let currentRPM = readDouble("F0Ac") else {
            return nil
        }

        return SMCFanSpeedSample(
            speed: FanSpeed(
                currentRPM: currentRPM,
                minRPM: readDouble("F0Mn"),
                maxRPM: readDouble("F0Mx")
            ),
            key: "F0Ac"
        )
    }

    func temperatureDiagnostic() -> String {
        "AppleSMC 温度键不可读"
    }

    func fanDiagnostic() -> String {
        guard let fanCount = readDouble("FNum") else {
            return "AppleSMC FNum 不可读"
        }

        guard fanCount > 0 else {
            return "AppleSMC 报告未发现风扇"
        }

        return "AppleSMC 报告 \(Int(fanCount)) 个风扇，但转速键不可读"
    }

    private func readDouble(_ key: String) -> Double? {
        guard let value = readValue(key) else {
            return nil
        }

        switch value.dataType {
        case "sp78":
            guard value.bytes.count >= 2 else {
                return nil
            }

            let raw = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(raw) / 256

        case "fpe2":
            guard value.bytes.count >= 2 else {
                return nil
            }

            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw) / 4

        case "flt ":
            guard value.bytes.count >= 4 else {
                return nil
            }

            let raw = UInt32(value.bytes[0]) << 24
                | UInt32(value.bytes[1]) << 16
                | UInt32(value.bytes[2]) << 8
                | UInt32(value.bytes[3])
            return Double(Float32(bitPattern: raw))

        case "ui8 ":
            return value.bytes.first.map(Double.init)

        case "ui16":
            guard value.bytes.count >= 2 else {
                return nil
            }

            return Double(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))

        case "ui32":
            guard value.bytes.count >= 4 else {
                return nil
            }

            return Double(
                UInt32(value.bytes[0]) << 24
                    | UInt32(value.bytes[1]) << 16
                    | UInt32(value.bytes[2]) << 8
                    | UInt32(value.bytes[3])
            )

        default:
            return nil
        }
    }

    private struct SMCValue {
        let dataType: String
        let bytes: [UInt8]
    }

    private func readValue(_ key: String) -> SMCValue? {
        let keyCode = Self.fourCharCode(key)
        guard let keyInfo = readKeyInfo(keyCode) else {
            return nil
        }

        var input = SMCKeyData()
        input.key = keyCode
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue

        var output = SMCKeyData()
        guard call(input: &input, output: &output) else {
            return nil
        }

        let byteCount = min(Int(keyInfo.dataSize), 32)
        let bytes = withUnsafeBytes(of: output.bytes) { rawBuffer in
            Array(rawBuffer.prefix(byteCount))
        }

        return SMCValue(dataType: Self.string(from: keyInfo.dataType), bytes: bytes)
    }

    private func readKeyInfo(_ key: UInt32) -> SMCKeyInfoData? {
        var input = SMCKeyData()
        input.key = key
        input.data8 = Command.readKeyInfo.rawValue

        var output = SMCKeyData()
        guard call(input: &input, output: &output) else {
            return nil
        }

        return output.keyInfo
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> Bool {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let inputSize = MemoryLayout<SMCKeyData>.stride

        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPointer,
                    inputSize,
                    outputPointer,
                    &outputSize
                )
            }
        }

        return result == KERN_SUCCESS && output.result == 0
    }

    private static func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) + UInt32(byte)
        }
        return result
    }

    private static func string(from code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]

        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    private static func kernelResultDescription(_ result: kern_return_t) -> String {
        "0x\(String(UInt32(bitPattern: result), radix: 16))"
    }
}
