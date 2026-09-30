import AppKit
import IOKit.ps
import TaskCore

/// System-wide macOS power mode, independent of per-process scheduling priority.
final class PowerModeController {
  var onChange: (() -> Void)?
  private(set) var profiles: [MacPowerSource: MacPowerProfile] = [:]
  private(set) var supported = false
  private(set) var busy = false
  private var observers: [NSObjectProtocol] = []
  private var timer: Timer?
  private let queue = DispatchQueue(label: "TaskManager.power-mode", qos: .utility)
  var enabled: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
  var source: MacPowerSource {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let value = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
    else { return .ac }
    return value as String == kIOPSBatteryPowerValue ? .battery : .ac
  }
  func start() {
    for name in [
      Notification.Name.NSProcessInfoPowerStateDidChange, NSApplication.didBecomeActiveNotification,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
          [weak self] _ in self?.refresh()
        })
    }
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      self?.refresh()
    }
    refresh()
  }
  deinit {
    timer?.invalidate()
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
  private static func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    } catch { return (-1, error.localizedDescription) }
  }
  func refresh(completion: (() -> Void)? = nil) {
    queue.async { [weak self] in
      let custom = Self.run("/usr/bin/pmset", ["-g", "custom"])
      let cap = Self.run("/usr/bin/pmset", ["-g", "cap"])
      let profiles = custom.0 == 0 ? MacPowerConfiguration.parse(custom.1) : [:]
      let supported =
        cap.0 == 0 && cap.1.split(whereSeparator: \.isWhitespace).contains("lowpowermode")
      DispatchQueue.main.async {
        guard let self else { return }
        self.profiles = profiles
        self.supported = supported
        self.onChange?()
        completion?()
      }
    }
  }
  func toggle(
    confirm: @escaping (String, String, String) -> Bool, report: @escaping (String) -> Void
  ) {
    guard !busy else { return }
    busy = true
    onChange?()
    refresh { [weak self] in
      guard let self else { return }
      let source = self.source
      guard self.supported, let profile = self.profiles[source] else {
        self.busy = false
        self.onChange?()
        report("Low Power Mode is not available for this Mac's current power source.")
        return
      }
      let restoreKey = "powerMode.restore." + source.rawValue
      let saved =
        MacEnergyMode(rawValue: UserDefaults.standard.integer(forKey: restoreKey)) ?? .automatic
      let target: MacEnergyMode = profile.mode == .low ? (saved == .low ? .automatic : saved) : .low
      guard let command = profile.command(source: source, target: target) else {
        self.busy = false
        self.onChange?()
        report("This power profile cannot restore the requested mode.")
        return
      }
      let title = target == .low ? "Turn on Low Power Mode?" : "Turn off Low Power Mode?"
      let message =
        "This changes the whole Mac, not just the selected process.\n\n\(source.rawValue): \(profile.mode.title) → \(target.title). The other power-source profile stays unchanged.\n\nmacOS will request administrator authorization. Task Manager never receives or stores your password."
      guard confirm(title, message, target == .low ? "Turn on" : "Restore " + target.title) else {
        self.busy = false
        self.onChange?()
        return
      }
      self.queue.async {
        // The shell command contains only fixed enum values, never process names or user input.
        let script =
          "do shell script \"\(command)\" with administrator privileges with prompt \"Task Manager wants to change macOS Low Power Mode.\""
        let result = Self.run("/usr/bin/osascript", ["-e", script])
        DispatchQueue.main.async {
          self.refresh {
            self.busy = false
            self.onChange?()
            guard result.0 == 0 else {
              if !result.1.contains("(-128)") {
                report(
                  "macOS did not change the power mode.\n\n"
                    + result.1.trimmingCharacters(in: .whitespacesAndNewlines))
              }
              return
            }
            guard self.profiles[source]?.mode == target else {
              report(
                "macOS returned without the requested power profile taking effect. Check System Settings → Battery or Energy."
              )
              return
            }
            if target == .low {
              UserDefaults.standard.set(profile.mode.rawValue, forKey: restoreKey)
            } else {
              UserDefaults.standard.removeObject(forKey: restoreKey)
            }
          }
        }
      }
    }
  }
}
