import Foundation
import SystemBridge

public func cString<T>(_ tuple: T) -> String {
  var v = tuple
  return withUnsafePointer(to: &v) {
    $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
  }
}
public enum Metrics {
  public static func rate(_ now: UInt64, _ previous: UInt64, elapsed: Double) -> Double {
    elapsed > 0 && now >= previous ? Double(now - previous) / elapsed : 0
  }
  public static func cpu(now: UInt64, previous: UInt64, elapsed: Double, cores: Int) -> Double {
    min(100, max(0, rate(now, previous, elapsed: elapsed) / 1e9 / Double(max(1, cores)) * 100))
  }
  public static func memoryPercent(_ bytes: UInt64, total: UInt64) -> Double {
    total > 0 ? min(100, Double(bytes) / Double(total) * 100) : 0
  }
}
public struct ProcessRecord: Identifiable, Codable {
  public var pid: Int32 = 0, ppid: Int32 = 0, uid: Int32 = 0, state: Int32 = 0, threads: Int32 = 0,
    nice: Int32 = 0
  public var start: UInt64 = 0, startMicro: UInt64 = 0, cpuNS: UInt64 = 0, memory: UInt64 = 0,
    readBytes: UInt64 = 0, writeBytes: UInt64 = 0
  public var name = "", path = "", user = "", architecture = "—", bundleID = "", appPath = "",
    appName = ""
  public var cpu: Double = 0, diskRead: Double = 0, diskWrite: Double = 0
  public var metricsValid = false, ioValid = false
  public var id: String { "\(pid):\(start):\(startMicro)" }
  public var status: String {
    switch state {
    case 1: return "Idle"
    case 2: return "Running"
    case 3: return "Sleeping"
    case 4: return "Stopped"
    case 5: return "Zombie"
    default: return "Unknown"
    }
  }
  public init() {}
  public init(_ p: TMProcess) {
    pid = p.pid
    ppid = p.ppid
    uid = p.uid
    state = p.state
    threads = p.threads
    nice = p.nice_value
    start = p.start_sec
    startMicro = p.start_usec
    cpuNS = p.cpu_ns
    memory = p.memory
    readBytes = p.read_bytes
    writeBytes = p.write_bytes
    name = cString(p.name)
    path = cString(p.path)
    user = cString(p.user)
    metricsValid = p.metrics_valid != 0
    ioValid = p.io_valid != 0
    architecture = p.arch == 0x0100_000c ? "Apple" : (p.arch == 0x0100_0007 ? "Intel" : "—")
    if let range = path.range(of: ".app/") { appPath = String(path[..<range.lowerBound]) + ".app" }
  }
  public func matches(_ query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return q.isEmpty
      || [name, appName, String(pid), path, bundleID, user].contains {
        $0.localizedCaseInsensitiveContains(q)
      }
  }
  public func protectedReason(currentUID: Int32, ownPID: Int32) -> String? {
    if pid <= 1 { return "Kernel and launchd processes are protected." }
    if pid == ownPID { return "Task Manager protects its own monitoring process." }
    if uid != currentUID {
      return "This process belongs to another user. No privilege escalation is performed."
    }
    if [
      "WindowServer", "loginwindow", "launchd", "kernel_task", "watchdogd", "powerd", "securityd",
      "opendirectoryd", "runningboardd", "systemstats", "coreservicesd", "tccd",
    ].contains(name) {
      return "This process provides a critical macOS service."
    }
    if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") || path.hasPrefix("/usr/sbin/")
    {
      return "System-managed executables are protected by Task Manager."
    }
    return nil
  }
  public func number(_ key: String, total: UInt64) -> Double? {
    switch key {
    case "pid": return Double(pid)
    case "ppid": return Double(ppid)
    case "cpu": return metricsValid ? cpu : nil
    case "time": return metricsValid ? Double(cpuNS) / 1e9 : nil
    case "memory": return metricsValid ? Double(memory) : nil
    case "mempercent": return metricsValid ? Metrics.memoryPercent(memory, total: total) : nil
    case "disk": return ioValid ? diskRead + diskWrite : nil
    case "read": return ioValid ? diskRead : nil
    case "write": return ioValid ? diskWrite : nil
    case "threads": return metricsValid ? Double(threads) : nil
    case "nice": return Double(nice)
    case "start": return Double(start)
    default: return nil
    }
  }
  public func text(_ key: String) -> String {
    switch key {
    case "name": return appName.isEmpty ? name : appName
    case "status": return status
    case "user": return user
    case "arch": return architecture
    case "path": return path
    case "bundle": return bundleID
    default: return ""
    }
  }
}
public struct ProcessGroup {
  public var key: String, name: String, members: [ProcessRecord]
  public var cpu: Double { members.reduce(0) { $0 + $1.cpu } }
  public var memory: UInt64 { members.reduce(0) { $0 + $1.memory } }
}
public enum ProcessLogic {
  public static func sorted(_ records: [ProcessRecord], key: String, ascending: Bool, total: UInt64)
    -> [ProcessRecord]
  {
    records.sorted { a, b in
      let x = a.number(key, total: total)
      let y = b.number(key, total: total)
      if x != nil || y != nil {
        if x == nil { return false }
        if y == nil { return true }
        if x! != y! { return ascending ? x! < y! : x! > y! }
      } else {
        let c = a.text(key).localizedStandardCompare(b.text(key))
        if c != .orderedSame { return ascending ? c == .orderedAscending : c == .orderedDescending }
      }
      return a.pid < b.pid
    }
  }
  public static func groups(_ records: [ProcessRecord]) -> [ProcessGroup] {
    let lookup = Dictionary(records.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    var buckets: [String: [ProcessRecord]] = [:]
    var titles: [String: String] = [:]
    for record in records {
      var root = record
      var seen: Set<Int32> = [record.pid]
      while root.appPath.isEmpty, let parent = lookup[root.ppid], parent.pid > 1,
        seen.insert(parent.pid).inserted
      { root = parent }
      let key = root.appPath.isEmpty ? "pid:\(record.id)" : root.appPath
      buckets[key, default: []].append(record)
      titles[key] =
        root.appPath.isEmpty
        ? record.name
        : (root.appName.isEmpty
          ? URL(fileURLWithPath: root.appPath).deletingPathExtension().lastPathComponent
          : root.appName)
    }
    return buckets.map {
      ProcessGroup(key: $0.key, name: titles[$0.key] ?? $0.key, members: $0.value)
    }
  }
}
public enum RefreshSpeed: String, CaseIterable {
  case high = "High"
  case normal = "Normal"
  case low = "Low"
  case paused = "Paused"
  public var interval: Double? {
    switch self {
    case .high: return 1
    case .normal: return 2
    case .low: return 4
    case .paused: return nil
    }
  }
}
public struct CPUCounter {
  public var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
  public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
    self.user = user
    self.system = system
    self.idle = idle
    self.nice = nice
  }
  public func utilization(since previous: CPUCounter) -> CPUUtilization? {
    // Mach exposes wrapping 32-bit cumulative tick counters per processor.
    let user = UInt64(user &- previous.user)
    let system = UInt64(system &- previous.system)
    let idle = UInt64(idle &- previous.idle)
    let nice = UInt64(nice &- previous.nice)
    let total = user + system + idle + nice
    guard total > 0 else { return nil }
    return CPUUtilization(
      total: Double(user + system + nice) / Double(total) * 100,
      kernel: Double(system) / Double(total) * 100)
  }
}
public struct CPUUtilization {
  public let total: Double, kernel: Double
}
public struct SystemSnapshot {
  public var logicalCPUs: [CPUUtilization?] = []
  public var raw = TMSystem(), cpu: Double = 0, read: Double = 0, write: Double = 0,
    received: Double = 0, sent: Double = 0
  public var timestamp = Date()
  public var used: UInt64 { min(raw.ram, raw.active + raw.wired + raw.compressed) }
  public var available: UInt64 { raw.ram > used ? raw.ram - used : 0 }
  public var memoryPercent: Double { Metrics.memoryPercent(used, total: raw.ram) }
  public init() {}
}
public final class Sampler {
  private var previous: [String: ProcessRecord] = [:]
  private var previousSystem: TMSystem?
  private var previousCPUs: [CPUCounter] = []
  private var previousTime: Double?
  private var bundles: [String: (String, String)] = [:]
  public init() {}
  public func resetBaseline() {
    previous = [:]
    previousSystem = nil
    previousCPUs = []
    previousTime = nil
  }
  public func sample() -> ([ProcessRecord], SystemSnapshot) {
    let now = ProcessInfo.processInfo.systemUptime
    let dt = previousTime.map { now - $0 } ?? 0
    var raw = TMSystem()
    tm_system(&raw)
    var ptr: UnsafeMutablePointer<TMProcess>?
    let count = tm_processes(&ptr)
    defer { tm_free(ptr) }
    var records: [ProcessRecord] = []
    if let ptr = ptr {
      records.reserveCapacity(Int(count))
      for i in 0..<Int(count) {
        var p = ProcessRecord(ptr[i])
        if !p.appPath.isEmpty {
          if bundles[p.appPath] == nil {
            let b = Bundle(path: p.appPath)
            bundles[p.appPath] = (
              b?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? b?.object(
                forInfoDictionaryKey: "CFBundleName") as? String
                ?? URL(fileURLWithPath: p.appPath).deletingPathExtension().lastPathComponent,
              b?.bundleIdentifier ?? ""
            )
          }
          if let b = bundles[p.appPath] {
            p.appName = b.0
            p.bundleID = b.1
          }
        }
        if let old = previous[p.id], p.metricsValid, old.metricsValid {
          p.cpu = Metrics.cpu(
            now: p.cpuNS, previous: old.cpuNS, elapsed: dt, cores: Int(raw.logical))
          if p.ioValid && old.ioValid {
            p.diskRead = Metrics.rate(p.readBytes, old.readBytes, elapsed: dt)
            p.diskWrite = Metrics.rate(p.writeBytes, old.writeBytes, elapsed: dt)
          }
        }
        records.append(p)
      }
    }
    var sys = SystemSnapshot()
    sys.raw = raw
    var cpuPointer: UnsafeMutablePointer<TMCPU>?
    let cpuCount = Int(tm_cpu_load(&cpuPointer))
    if let cpuPointer {
      let counters = (0..<cpuCount).map { i in
        let c = cpuPointer[i]
        return CPUCounter(user: c.user, system: c.system, idle: c.idle, nice: c.nice)
      }
      sys.logicalCPUs = counters.enumerated().map { i, value in
        previousCPUs.count == counters.count ? value.utilization(since: previousCPUs[i]) : nil
      }
      previousCPUs = counters
      tm_free(cpuPointer)
    } else {
      previousCPUs = []
    }

    if let old = previousSystem {
      let busy = raw.cpu_user + raw.cpu_system + raw.cpu_nice
      let oldBusy = old.cpu_user + old.cpu_system + old.cpu_nice
      let total = busy + raw.cpu_idle
      let oldTotal = oldBusy + old.cpu_idle
      if total > oldTotal && busy >= oldBusy {
        sys.cpu = Double(busy - oldBusy) / Double(total - oldTotal) * 100
      }
      sys.read = Metrics.rate(raw.disk_read, old.disk_read, elapsed: dt)
      sys.write = Metrics.rate(raw.disk_write, old.disk_write, elapsed: dt)
      sys.received = Metrics.rate(raw.net_in, old.net_in, elapsed: dt)
      sys.sent = Metrics.rate(raw.net_out, old.net_out, elapsed: dt)
    }
    previous = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    previousSystem = raw
    previousTime = now
    let paths = Set(records.map(\.appPath))
    bundles = bundles.filter { paths.contains($0.key) }
    return (records, sys)
  }
}
public struct HistoryEntry: Codable {
  public var name: String, path: String, cpuSeconds: Double = 0, peakMemory: UInt64 = 0,
    observedSeconds: Double = 0, diskBytes: Double = 0
  public init(name: String, path: String) {
    self.name = name
    self.path = path
  }
}
public final class HistoryStore {
  public var entries: [String: HistoryEntry] = [:]
  private var last: [String: UInt64] = [:]
  private var time: Date?
  public init() {}
  public func reset() {
    entries = [:]
    last = [:]
    time = nil
  }
  public func suspend() {
    last = [:]
    time = nil
  }
  public func ingest(_ records: [ProcessRecord], at date: Date) {
    let elapsed = time.map { max(0, date.timeIntervalSince($0)) } ?? 0
    var keys = Set<String>()
    for p in records where p.metricsValid {
      let key = p.appPath.isEmpty ? (p.path.isEmpty ? p.name : p.path) : p.appPath
      var h = entries[key] ?? HistoryEntry(name: p.appName.isEmpty ? p.name : p.appName, path: key)
      if let prior = last[p.id], p.cpuNS >= prior {
        h.cpuSeconds += Double(p.cpuNS - prior) / 1e9
        h.diskBytes += (p.diskRead + p.diskWrite) * elapsed
      }
      if keys.insert(key).inserted { h.observedSeconds += elapsed }
      h.peakMemory = max(h.peakMemory, p.memory)
      entries[key] = h
    }
    last = Dictionary(records.map { ($0.id, $0.cpuNS) }, uniquingKeysWith: { first, _ in first })
    time = date
    // Retain the most informative 5,000 entries for a strict long-running bound.
    if entries.count > 5000 {
      let keep = entries.sorted { $0.value.cpuSeconds > $1.value.cpuSeconds }.prefix(5000)
      entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
  }
}
