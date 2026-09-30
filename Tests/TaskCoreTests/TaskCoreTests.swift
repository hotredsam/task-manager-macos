import Darwin
import Foundation
import SystemBridge
import Testing

@testable import TaskCore

struct TaskCoreTests {
  func process(_ pid: Int32, _ name: String, _ cpu: Double = 0) -> ProcessRecord {
    var p = ProcessRecord()
    p.pid = pid
    p.name = name
    p.cpu = cpu
    p.metricsValid = true
    p.uid = 501
    p.start = 100
    p.path = "/Applications/Test.app/Contents/MacOS/Test"
    return p
  }
  @Test func testCPUCalculation() {
    expectEqual(
      Metrics.cpu(now: 3_000_000_000, previous: 1_000_000_000, elapsed: 2, cores: 8), 12.5)
  }
  @Test func testCPUInvalidIntervals() {
    expectEqual(Metrics.cpu(now: 1, previous: 2, elapsed: 1, cores: 8), 0)
    expectEqual(Metrics.cpu(now: 9, previous: 0, elapsed: 0, cores: 8), 0)
  }
  @Test func testCPUClamped() {
    expectEqual(Metrics.cpu(now: 100_000_000_000, previous: 0, elapsed: 1, cores: 1), 100)
  }
  @Test func testMemoryPercentage() {
    expectEqual(Metrics.memoryPercent(256, total: 1024), 25)
    expectEqual(Metrics.memoryPercent(20, total: 0), 0)
  }
  @Test func testMemorySnapshot() {
    var s = SystemSnapshot()
    s.raw.ram = 1000
    s.raw.active = 300
    s.raw.wired = 100
    s.raw.compressed = 100
    expectEqual(s.used, 500)
    expectEqual(s.available, 500)
    expectEqual(s.memoryPercent, 50)
  }
  @Test func testDiskRateCounterReset() {
    expectEqual(Metrics.rate(1000, 500, elapsed: 2), 250)
    expectEqual(Metrics.rate(4, 100, elapsed: 1), 0)
  }
  @Test func testGroupingBundleAndChild() {
    var root = process(10, "Editor")
    root.appPath = "/Applications/Test.app"
    root.appName = "Editor"
    var helper = process(11, "Helper")
    helper.ppid = 10
    helper.appPath = ""
    let g = ProcessLogic.groups([root, helper])
    expectEqual(g.count, 1)
    expectEqual(g.first?.members.count, 2)
    expectEqual(g.first?.name, "Editor")
  }
  @Test func testGroupingCycleTerminates() {
    var a = process(10, "A")
    a.ppid = 11
    var b = process(11, "B")
    b.ppid = 10
    expectEqual(ProcessLogic.groups([a, b]).count, 2)
  }
  @Test func testGroupingDoesNotCombineUnrelatedProcesses() {
    let a = process(10, "WebContent")
    let b = process(11, "WebContent")
    expectEqual(ProcessLogic.groups([a, b]).count, 2)
  }
  @Test func testSortingBothDirections() {
    let a = process(10, "B", 30)
    let b = process(11, "A", 5)
    expectEqual(
      ProcessLogic.sorted([a, b], key: "cpu", ascending: false, total: 1000).map(\.pid), [10, 11])
    expectEqual(
      ProcessLogic.sorted([a, b], key: "cpu", ascending: true, total: 1000).map(\.pid), [11, 10])
    expectEqual(
      ProcessLogic.sorted([a, b], key: "name", ascending: true, total: 1000).map(\.pid), [11, 10])
  }
  @Test func testUnavailableSortsLast() {
    var a = process(10, "A")
    a.metricsValid = false
    let b = process(11, "B", 0)
    expectEqual(
      ProcessLogic.sorted([a, b], key: "cpu", ascending: true, total: 1000).map(\.pid), [11, 10])
  }
  @Test func testSearchAllFields() {
    var p = process(123, "Helper")
    p.appName = "Editor"
    p.bundleID = "org.test.Editor"
    p.user = "alice"
    for q in ["HELPER", "editor", "123", "alice", "Contents", "org.test", ""] {
      expectTrue(p.matches(q), q)
    }
    expectFalse(p.matches("nonexistent"))
  }
  @Test func testPIDIdentityIncludesStartTime() {
    var a = process(10, "A")
    var b = a
    b.startMicro = 1
    expectNotEqual(a.id, b.id)
    a.start = 101
    expectNotEqual(a.id, b.id)
  }
  @Test func testProtectedProcesses() {
    var p = process(20, "Editor")
    expectNil(p.protectedReason(currentUID: 501, ownPID: 30))
    expectNotNil(p.protectedReason(currentUID: 502, ownPID: 30))
    expectNotNil(p.protectedReason(currentUID: 501, ownPID: 20))
    p.name = "WindowServer"
    expectNotNil(p.protectedReason(currentUID: 501, ownPID: 30))
    p.name = "Service"
    p.path = "/System/Library/service"
    expectNotNil(p.protectedReason(currentUID: 501, ownPID: 30))
    p.pid = 1
    expectNotNil(p.protectedReason(currentUID: 501, ownPID: 30))
  }
  @Test func testRefreshStates() {
    expectNil(RefreshSpeed.paused.interval)
    expectEqual(RefreshSpeed.high.interval, 1)
    expectEqual(RefreshSpeed.normal.interval, 2)
    expectEqual(RefreshSpeed.low.interval, 4)
  }
  @Test func testLaunchctlParsing() {
    let jobs = LaunchParser.jobs(
      "PID Status Label\n42 0 com.test.running\n- 0 com.test.idle\ninvalid data\n")
    expectEqual(jobs.count, 2)
    expectEqual(jobs["com.test.running"]!, 42)
    expectTrue(jobs.keys.contains("com.test.idle"))
    expectNil(jobs["com.test.idle"]!)
  }
  @Test func testDomainJobParsing() {
    let jobs = LaunchParser.jobs(
      "system = {\n services = {\n 0 (pe) com.test.idle\n 42 (pe) com.test.running\n }\n 123 0 bogus.endpoint\n}"
    )
    expectEqual(jobs.count, 2)
    expectNil(jobs["com.test.idle"]!)
    expectEqual(jobs["com.test.running"]!, 42)
  }
  @Test func testNativeCPUClockUnits() {
    var a = TMProcess()
    var b = TMProcess()
    expectEqual(tm_read_process(getpid(), &a), 1)
    let start = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - start < 0.12 {}
    expectEqual(tm_read_process(getpid(), &b), 1)
    expectGreater(b.cpu_ns - a.cpu_ns, 30_000_000)
  }
  @Test func testDisabledParsing() {
    expectEqual(
      LaunchParser.disabled("\t\"com.test.agent\" => true\n\"com.other\" => false"),
      ["com.test.agent": true, "com.other": false])
  }
  @Test func testHistoryDoesNotCountLifetimeCPU() {
    let store = HistoryStore()
    var p = process(22, "Editor")
    p.cpuNS = 100_000_000_000
    store.ingest([p], at: Date(timeIntervalSince1970: 0))
    expectEqual(store.entries.values.first?.cpuSeconds, 0)
    p.cpuNS += 2_000_000_000
    store.ingest([p], at: Date(timeIntervalSince1970: 2))
    expectEqual(store.entries.values.first?.cpuSeconds, 2)
    expectEqual(store.entries.values.first?.observedSeconds, 2)
    store.reset()
    expectTrue(store.entries.isEmpty)
  }
  @Test func testMachTimeConversion() {
    var tb = mach_timebase_info_data_t()
    mach_timebase_info(&tb)
    expectEqual(
      tm_ticks_to_ns(24_000_000), UInt64(24_000_000) * UInt64(tb.numer) / UInt64(tb.denom))
  }
  @Test func testRestrictedProcessIdentity() {
    var p = TMProcess()
    expectEqual(tm_read_process(1, &p), 1)
    expectEqual(p.pid, 1)
    expectEqual(p.uid, 0)
    expectTrue(!cString(p.name).isEmpty)
  }
  @Test func testNativeSampling() {
    let sampler = Sampler()
    let (processes, system) = sampler.sample()
    expectGreater(processes.count, 0)
    expectGreater(system.raw.ram, 0)
    expectGreater(system.raw.logical, 0)
    let own = processes.first { $0.pid == getpid() }
    expectNotNil(own)
    expectEqual(own?.uid, Int32(getuid()))
    expectTrue(own?.metricsValid ?? false)
    expectGreater(own?.memory ?? 0, 0)
  }
}

private func expectEqual<T: Equatable>(
  _ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation
) { #expect(a == b, sourceLocation: sourceLocation) }
private func expectNotEqual<T: Equatable>(
  _ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation
) { #expect(a != b, sourceLocation: sourceLocation) }
private func expectGreater<T: Comparable>(
  _ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation
) { #expect(a > b, sourceLocation: sourceLocation) }
private func expectTrue(
  _ a: Bool, _ message: String = "", sourceLocation: SourceLocation = #_sourceLocation
) { #expect(a, Comment(rawValue: message), sourceLocation: sourceLocation) }
private func expectFalse(_ a: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(!a, sourceLocation: sourceLocation)
}
private func expectNil<T>(_ a: T?, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(a == nil, sourceLocation: sourceLocation)
}
private func expectNotNil<T>(_ a: T?, sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(a != nil, sourceLocation: sourceLocation)
}
