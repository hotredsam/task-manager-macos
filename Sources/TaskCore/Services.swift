import Foundation

public struct ServiceRecord: Identifiable {
  public var id: String { domain + "/" + label }
  public var label: String, program: String, path: String, domain: String, mechanism: String,
    publisher: String, status: String
  public var pid: Int32?, modified: Date?, disabled: Bool = false, mutable: Bool = false
}
public enum LaunchParser {
  public static func jobs(_ text: String) -> [String: Int32?] {
    var result: [String: Int32?] = [:]
    let isDomainDump = text.contains("services = {")
    var inside = !isDomainDump
    for line in text.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if isDomainDump && trimmed == "services = {" {
        inside = true
        continue
      }
      if isDomainDump && inside && trimmed == "}" { break }
      guard inside else { continue }
      let cols = line.split(whereSeparator: { $0.isWhitespace })
      if cols.count == 3, cols[0] == "-" || Int32(cols[0]) != nil,
        cols[1] == "-" || cols[1] == "(pe)" || Int32(cols[1]) != nil
      {
        let value = Int32(cols[0])
        let pid = value.flatMap { $0 > 0 ? $0 : nil }
        result.updateValue(pid, forKey: String(cols[2]))
      }
    }
    return result
  }
  public static func disabled(_ text: String) -> [String: Bool] {
    var result: [String: Bool] = [:]
    for line in text.split(separator: "\n") {
      let parts = line.components(separatedBy: "=>")
      if parts.count == 2 {
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(
          in: CharacterSet(charactersIn: "\""))
        result[key] = parts[1].contains("true")
      }
    }
    return result
  }
}
public enum LaunchServices {
  // launchctl is the supported command interface for inspecting other launchd jobs.
  // No shell interpolation, no privilege elevation, and a bounded subprocess lifetime.
  public static func command(_ arguments: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = arguments
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: deadline)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    deadline.cancel()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }
  public static func scan(uid: UInt32) -> [ServiceRecord] {
    let userDomain = "gui/\(uid)"
    let userJobs = LaunchParser.jobs(command(["list"]).1)
    let systemJobs = LaunchParser.jobs(command(["print", "system"]).1)
    let userDisabled = LaunchParser.disabled(command(["print-disabled", userDomain]).1)
    let systemDisabled = LaunchParser.disabled(command(["print-disabled", "system"]).1)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let folders = [
      (home + "/Library/LaunchAgents", userDomain, "LaunchAgent"),
      ("/Library/LaunchAgents", userDomain, "LaunchAgent"),
      ("/Library/LaunchDaemons", "system", "LaunchDaemon"),
      ("/System/Library/LaunchAgents", userDomain, "System agent"),
      ("/System/Library/LaunchDaemons", "system", "System daemon"),
    ]
    var records: [ServiceRecord] = []
    var seen = Set<String>()
    for (folder, domain, mechanism) in folders {
      for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
      where name.hasSuffix(".plist") {
        let path = folder + "/" + name
        guard let data = FileManager.default.contents(atPath: path),
          let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil))
            as? [String: Any], let label = dict["Label"] as? String
        else { continue }
        let program =
          dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first ?? "—"
        let jobs = domain == "system" ? systemJobs : userJobs
        let overrides = domain == "system" ? systemDisabled : userDisabled
        let isDisabled = overrides[label] ?? (dict["Disabled"] as? Bool ?? false)
        let pid = jobs[label].flatMap { $0 }
        let loaded = jobs.keys.contains(label)
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mutable =
          folder == home + "/Library/LaunchAgents" && !label.hasPrefix("com.apple.")
          && !URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix("/System/")
        let parts = label.split(separator: ".")
        let publisher =
          label.hasPrefix("com.apple.")
          ? "Apple" : (parts.count >= 2 ? String(parts[1]) : "Unknown")
        records.append(
          ServiceRecord(
            label: label, program: program, path: path, domain: domain, mechanism: mechanism,
            publisher: publisher,
            status: isDisabled
              ? "Disabled" : (pid != nil ? "Running" : (loaded ? "On demand" : "Not loaded")),
            pid: pid, modified: attrs?[.modificationDate] as? Date, disabled: isDisabled,
            mutable: mutable))
        seen.insert(domain + "/" + label)
      }
    }
    for (domain, jobs) in [(userDomain, userJobs), ("system", systemJobs)] {
      for (label, pid) in jobs where !seen.contains(domain + "/" + label) {
        let disabled = (domain == "system" ? systemDisabled : userDisabled)[label] ?? false
        records.append(
          ServiceRecord(
            label: label, program: "—", path: "—", domain: domain, mechanism: "Registered job",
            publisher: label.hasPrefix("com.apple.") ? "Apple" : "Unknown",
            status: disabled ? "Disabled" : (pid != nil ? "Running" : "On demand"), pid: pid,
            disabled: disabled))
      }
    }
    return records.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
  }
}
