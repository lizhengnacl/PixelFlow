import Foundation
import IOKit
import IOKit.hidsystem

struct TemperatureSensorSample {
    let celsius: Double
    let diagnostic: String
}

final class ThermalSensorSampler {
    private struct HIDTemperatureReading {
        let name: String
        let celsius: Double
    }

    private static let appleVendorUsagePage = 0xff00
    private static let temperatureUsage = 0x05
    private static let temperatureEventType: Int64 = 0x0f
    private static let temperatureEventField: Int64 = 0x0f << 0x10

    private let client: IOHIDEventSystemClient?

    init() {
        let client = IOHIDEventSystemClientCreatePrivate(kCFAllocatorDefault)
        self.client = client

        guard let client else {
            return
        }

        let matching = [
            "PrimaryUsagePage": Self.appleVendorUsagePage,
            "PrimaryUsage": Self.temperatureUsage
        ] as CFDictionary
        IOHIDEventSystemClientSetMatchingPrivate(client, matching)
    }

    func cpuTemperatureSample() -> TemperatureSensorSample? {
        let readings = temperatureReadings()
        guard let selection = Self.selectCPUReading(from: readings) else {
            return nil
        }

        return TemperatureSensorSample(
            celsius: selection.reading.celsius,
            diagnostic: "\(selection.source) \(selection.reading.name)"
        )
    }

    func diagnostic() -> String {
        guard client != nil else {
            return "HID 温度客户端不可用"
        }

        let services = temperatureServices()
        guard !services.isEmpty else {
            return "HID 未发现 Apple 温度传感器"
        }

        let readings = temperatureReadings(from: services)
        guard !readings.isEmpty else {
            return "HID 发现 \(services.count) 个温度传感器，但未返回温度事件"
        }

        return "HID 温度传感器未匹配 CPU 候选"
    }

    private func temperatureServices() -> [IOHIDServiceClient] {
        guard
            let client,
            let services = IOHIDEventSystemClientCopyServices(client) as? [AnyObject]
        else {
            return []
        }

        return services.map { $0 as! IOHIDServiceClient }
    }

    private func temperatureReadings() -> [HIDTemperatureReading] {
        temperatureReadings(from: temperatureServices())
    }

    private func temperatureReadings(from services: [IOHIDServiceClient]) -> [HIDTemperatureReading] {
        services.compactMap { service in
            let name = (IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sensorName: String
            if let name, !name.isEmpty {
                sensorName = name
            } else {
                sensorName = "未命名传感器"
            }

            guard
                let event = IOHIDServiceClientCopyEventPrivate(
                    service,
                    Self.temperatureEventType,
                    0,
                    0
                )?.takeRetainedValue()
            else {
                return nil
            }

            let celsius = IOHIDEventGetFloatValuePrivate(event, Self.temperatureEventField)
            guard celsius > 0, celsius < 150 else {
                return nil
            }

            return HIDTemperatureReading(name: sensorName, celsius: celsius)
        }
    }

    private static func selectCPUReading(
        from readings: [HIDTemperatureReading]
    ) -> (reading: HIDTemperatureReading, source: String)? {
        let groups: [(source: String, readings: [HIDTemperatureReading])] = [
            ("HID PMU tdie", readings.filter { $0.name.localizedCaseInsensitiveContains("tdie") }),
            ("HID PMU tdev", readings.filter { $0.name.localizedCaseInsensitiveContains("tdev") }),
            (
                "HID PMU",
                readings.filter {
                    let lowercasedName = $0.name.lowercased()
                    return lowercasedName.hasPrefix("pmu ")
                        && !lowercasedName.contains("tcal")
                        && !lowercasedName.contains("battery")
                }
            ),
            (
                "HID 温度",
                readings.filter {
                    let lowercasedName = $0.name.lowercased()
                    return !lowercasedName.contains("battery")
                        && !lowercasedName.contains("nand")
                        && !lowercasedName.contains("tcal")
                }
            )
        ]

        for group in groups where !group.readings.isEmpty {
            guard let hottest = group.readings.max(by: { $0.celsius < $1.celsius }) else {
                continue
            }

            return (hottest, group.source)
        }

        return nil
    }
}

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreatePrivate(_ allocator: CFAllocator?) -> IOHIDEventSystemClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatchingPrivate(
    _ client: IOHIDEventSystemClient,
    _ matching: CFDictionary
)

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEventPrivate(
    _ service: IOHIDServiceClient,
    _ type: Int64,
    _ options: Int64,
    _ timeout: Int64
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValuePrivate(
    _ event: CFTypeRef,
    _ field: Int64
) -> Double
