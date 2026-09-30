import Foundation

public enum MacPowerSource: String, CaseIterable {
  case battery = "Battery Power"
  case ac = "AC Power"
  public var argument: String { self == .battery ? "-b" : "-c" }
}
public enum MacEnergyMode: Int {
  case automatic = 0
  case low = 1
  case high = 2
  public var title: String {
    switch self {
    case .automatic: return "Automatic"
    case .low: return "Low Power"
    case .high: return "High Power"
    }
  }
}
public struct MacPowerProfile: Equatable {
  public let mode: MacEnergyMode
  public let usesUnifiedKey: Bool
  public init(mode: MacEnergyMode, usesUnifiedKey: Bool) {
    self.mode = mode
    self.usesUnifiedKey = usesUnifiedKey
  }
  /// Restrict the privileged command to an enumerated power source, key, and mode.
  public func command(source: MacPowerSource, target: MacEnergyMode) -> String? {
    guard usesUnifiedKey || target != .high else { return nil }
    return
      "/usr/bin/pmset \(source.argument) \(usesUnifiedKey ? "powermode" : "lowpowermode") \(target.rawValue)"
  }
}
public enum MacPowerConfiguration {
  public static func parse(_ text: String) -> [MacPowerSource: MacPowerProfile] {
    var source: MacPowerSource?
    var result: [MacPowerSource: MacPowerProfile] = [:]
    for line in text.split(separator: "\n") {
      let text = line.trimmingCharacters(in: .whitespaces)
      if text.hasSuffix(":") {
        source = MacPowerSource(rawValue: String(text.dropLast()))
        continue
      }
      let fields = text.split(whereSeparator: \.isWhitespace)
      guard let source, fields.count == 2, let number = Int(fields[1]),
        let mode = MacEnergyMode(rawValue: number)
      else { continue }
      if fields[0] == "powermode" {
        result[source] = MacPowerProfile(mode: mode, usesUnifiedKey: true)
      }
      if fields[0] == "lowpowermode", number <= 1, result[source]?.usesUnifiedKey != true {
        result[source] = MacPowerProfile(mode: mode, usesUnifiedKey: false)
      }
    }
    return result
  }
}
