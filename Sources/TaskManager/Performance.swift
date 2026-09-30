import AppKit
import IOKit.ps
import Metal
import TaskCore

func hardwareClassName(_ key: String, fallback: String) -> String {
  var buffer = [CChar](repeating: 0, count: 128)
  var count = buffer.count
  return sysctlbyname(key, &buffer, &count, nil, 0) == 0 ? String(cString: buffer) : fallback
}

func batteryLevel() -> (Double?, String) {
  guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
    let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
  else { return (nil, "No battery data") }
  for source in sources {
    if let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
      let current = d[kIOPSCurrentCapacityKey] as? Double,
      let maximum = d[kIOPSMaxCapacityKey] as? Double, maximum > 0
    {
      let state = d[kIOPSPowerSourceStateKey] as? String ?? "Unknown"
      return (current / maximum * 100, state)
    }
  }
  return (nil, "No internal battery")
}
enum Resource: String, CaseIterable {
  case cpu = "CPU"
  case memory = "Memory"
  case disk = "Disk"
  case network = "Network"
  case gpu = "GPU"
  case battery = "Battery / Energy"
  case swap = "Swap"
  case thermal = "Thermal"
  var color: NSColor {
    switch self {
    case .cpu: return accent
    case .memory: return .systemPurple
    case .disk: return .systemGreen
    case .network: return .systemOrange
    case .gpu: return .systemTeal
    case .battery: return .systemGreen
    case .swap: return .systemIndigo
    case .thermal: return .systemPink
    }
  }
}
final class GraphView: NSView {
  var points: [(Double, Double)] = []
  var second: [(Double, Double)] = []
  var maxValue: Double = 100
  var seconds: Double = 60
  var color = accent
  var unavailable: String?
  var compact = false
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    guard bounds.width > 2, bounds.height > 2 else { return }
    let rect = bounds.insetBy(dx: 1, dy: 1)
    color.withAlphaComponent(0.035).setFill()
    rect.fill()
    let grid = NSBezierPath()
    grid.lineWidth = 0.5
    for i in 0...10 {
      let x = rect.minX + rect.width * CGFloat(i) / 10
      grid.move(to: NSPoint(x: x, y: rect.minY))
      grid.line(to: NSPoint(x: x, y: rect.maxY))
    }
    for i in 0...5 {
      let y = rect.minY + rect.height * CGFloat(i) / 5
      grid.move(to: NSPoint(x: rect.minX, y: y))
      grid.line(to: NSPoint(x: rect.maxX, y: y))
    }
    color.withAlphaComponent(0.19).setStroke()
    grid.stroke()
    guard unavailable == nil else {
      if !compact {
        let text = unavailable!
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(
          in: NSRect(x: 24, y: rect.midY - 24, width: rect.width - 48, height: 70),
          withAttributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: style,
          ])
      }
      return
    }
    let end = points.last?.0 ?? Date().timeIntervalSince1970
    func drawSeries(_ series: [(Double, Double)], fill: Bool) {
      guard !series.isEmpty else { return }
      let path = NSBezierPath()
      var first: NSPoint?
      var last: NSPoint?
      for (time, value) in series {
        let x = rect.maxX - rect.width * CGFloat(min(1, max(0, (end - time) / seconds)))
        let y = rect.maxY - rect.height * CGFloat(min(1, max(0, value / max(1, maxValue))))
        let p = NSPoint(x: x, y: y)
        if first == nil {
          path.move(to: p)
          first = p
        } else {
          path.line(to: p)
        }
        last = p
      }
      if fill, let first = first, let last = last {
        let area = path.copy() as! NSBezierPath
        area.line(to: NSPoint(x: last.x, y: rect.maxY))
        area.line(to: NSPoint(x: first.x, y: rect.maxY))
        area.close()
        color.withAlphaComponent(0.14).setFill()
        area.fill()
      }
      path.lineWidth = compact ? 1 : 1.8
      if !fill { path.setLineDash([4, 3], count: 2, phase: 0) }
      color.withAlphaComponent(fill ? 1 : 0.65).setStroke()
      path.stroke()
    }
    drawSeries(points, fill: true)
    drawSeries(second, fill: false)
  }
}
final class ResourceCard: NSButton {
  let graph = GraphView()
  let titleLabel = label("", 13, .semibold)
  let detailLabel = label("", 11, .regular, .secondaryLabelColor)
  var selected = false { didSet { needsDisplay = true } }
  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false
    title = ""
    graph.compact = true
    addSubview(graph)
    addSubview(titleLabel)
    addSubview(detailLabel)
    setButtonType(.momentaryPushIn)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func layout() {
    super.layout()
    graph.frame = NSRect(x: 12, y: 20, width: 62, height: 38)
    titleLabel.frame = NSRect(x: 84, y: 17, width: max(0, bounds.width - 96), height: 20)
    detailLabel.frame = NSRect(x: 84, y: 40, width: max(0, bounds.width - 96), height: 19)
  }
  override func draw(_ dirtyRect: NSRect) {
    if selected {
      NSColor.controlAccentColor.withAlphaComponent(0.09).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 2), xRadius: 5, yRadius: 5).fill()
      graph.color.setFill()
      NSBezierPath(
        roundedRect: NSRect(x: 3, y: 24, width: 3, height: 28), xRadius: 1.5, yRadius: 1.5
      ).fill()
    }
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(convert(point, from: superview)) ? self : nil
  }
}
final class PerformanceView: NSView {
  var selected: Resource = .cpu
  var cards: [Resource: ResourceCard] = [:]
  let graph = GraphView()
  let heading = label("CPU", 28, .semibold)
  let hardware = label("", 13, .regular, .secondaryLabelColor)
  let upper = label("% Utilization", 11, .regular, .secondaryLabelColor)
  let limit = label("100%", 11, .regular, .secondaryLabelColor)
  let timeline = label("60 seconds", 11, .regular, .secondaryLabelColor)
  let nowLabel = label("0", 11, .regular, .secondaryLabelColor)
  let note = label("", 11, .regular, .secondaryLabelColor)
  let stats = NSStackView()
  var statKeys: [String] = []
  var statValues: [NSTextField] = []
  var current = SystemSnapshot()
  var history: [SystemSnapshot] = []
  var processes: [ProcessRecord] = []
  let gpu = MTLCreateSystemDefaultDevice()
  var thermalSamples: [(Double, Double)] = []
  var batterySamples: [(Double, Double)] = []
  var lastTimestamp: Date?
  var batteryState = ""
  override init(frame: NSRect) {
    super.init(frame: frame)
    let cardStack = stack([], .vertical, 2)
    cardStack.edgeInsets = NSEdgeInsets(top: 12, left: 5, bottom: 12, right: 5)
    for (i, r) in Resource.allCases.enumerated() {
      let card = ResourceCard(frame: .zero)
      card.titleLabel.stringValue = r.rawValue
      card.graph.color = r.color
      card.tag = i
      card.target = self
      card.action = #selector(selectCard(_:))
      card.setAccessibilityLabel(r.rawValue)
      card.setAccessibilityIdentifier("resource-\(r.rawValue)")
      cards[r] = card
      cardStack.addArrangedSubview(card)
      card.widthAnchor.constraint(equalToConstant: 207).isActive = true
      card.heightAnchor.constraint(equalToConstant: 77).isActive = true
    }
    let cardScroll = NSScrollView()
    cardScroll.documentView = cardStack
    cardScroll.hasVerticalScroller = true
    cardScroll.autohidesScrollers = true
    cardStack.translatesAutoresizingMaskIntoConstraints = false
    cardStack.widthAnchor.constraint(equalTo: cardScroll.widthAnchor).isActive = true
    cardStack.topAnchor.constraint(equalTo: cardScroll.contentView.topAnchor).isActive = true
    cardStack.leadingAnchor.constraint(equalTo: cardScroll.contentView.leadingAnchor).isActive =
      true
    cardScroll.widthAnchor.constraint(equalToConstant: 217).isActive = true
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let head = stack([heading, spacer, hardware])
    let gs = NSView()
    gs.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let graphHeader = stack([upper, gs, limit])
    graph.heightAnchor.constraint(greaterThanOrEqualToConstant: 215).isActive = true
    graph.heightAnchor.constraint(lessThanOrEqualToConstant: 370).isActive = true
    graph.setContentHuggingPriority(.defaultLow, for: .vertical)
    stats.orientation = .vertical
    stats.alignment = .leading
    stats.spacing = 16
    note.maximumNumberOfLines = 4
    note.lineBreakMode = .byWordWrapping
    let timeSpacer = NSView()
    timeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let timeRow = stack([timeline, timeSpacer, nowLabel])
    let detail = stack([head, graphHeader, graph, timeRow, stats, note], .vertical, 12)
    detail.edgeInsets = NSEdgeInsets(top: 26, left: 28, bottom: 24, right: 28)
    for v in [head, graphHeader, graph, timeRow, stats, note] {
      v.widthAnchor.constraint(equalTo: detail.widthAnchor, constant: -56).isActive = true
    }
    let all = stack([cardScroll, detail], .horizontal, 0)
    all.alignment = .top
    pin(all, self)
    detail.widthAnchor.constraint(equalTo: all.widthAnchor, constant: -217).isActive = true
    cardScroll.heightAnchor.constraint(equalTo: all.heightAnchor).isActive = true
    detail.heightAnchor.constraint(equalTo: all.heightAnchor).isActive = true
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func selectCard(_ sender: NSButton) {
    selected = Resource.allCases[sender.tag]
    render()
  }
  func update(system: SystemSnapshot, samples: [SystemSnapshot], processes: [ProcessRecord]) {
    current = system
    history = samples
    self.processes = processes
    captureEnvironment(system)
    render()
  }
  func captureEnvironment(_ system: SystemSnapshot) {
    if lastTimestamp != system.timestamp {
      lastTimestamp = system.timestamp
      let now = system.timestamp.timeIntervalSince1970
      thermalSamples.append((now, Double(ProcessInfo.processInfo.thermalState.rawValue)))
      let battery = batteryLevel()
      batteryState = battery.1
      if let b = battery.0 { batterySamples.append((now, b)) }
      let seconds = historySeconds
      thermalSamples.removeAll { $0.0 < now - seconds }
      batterySamples.removeAll { $0.0 < now - seconds }
    }
  }
  var historySeconds: Double {
    let value = UserDefaults.standard.double(forKey: "graphSeconds")
    return value > 0 ? value : 60
  }
  func series(_ r: Resource) -> [(Double, Double)] {
    if r == .thermal { return thermalSamples }
    if r == .battery { return batterySamples }
    return history.map { s in
      let value: Double
      switch r {
      case .cpu: value = s.cpu
      case .memory: value = s.memoryPercent
      case .disk: value = s.read
      case .network: value = s.received
      case .swap: value = Double(s.raw.swap_used)
      default: value = 0
      }
      return (s.timestamp.timeIntervalSince1970, value)
    }
  }
  func render() {
    let s = current
    let raw = s.raw
    let battery = batterySamples.last?.1
    let thermal = ["Nominal", "Fair", "Serious", "Critical"][
      min(3, ProcessInfo.processInfo.thermalState.rawValue)]
    for r in Resource.allCases {
      let c = cards[r]!
      c.selected = selected == r
      c.graph.points = series(r)
      c.graph.seconds = historySeconds
      c.graph.unavailable = r == .gpu || (r == .battery && battery == nil) ? "Unavailable" : nil
      c.graph.maxValue =
        [Resource.disk, .network, .swap].contains(r)
        ? max(1, c.graph.points.map(\.1).max() ?? 1) : (r == .thermal ? 3 : 100)
      switch r {
      case .cpu: c.detailLabel.stringValue = String(format: "%.1f%%", s.cpu)
      case .memory:
        c.detailLabel.stringValue =
          String(format: "%.0f%%", s.memoryPercent) + "  ·  " + bytes(Double(raw.ram))
      case .disk: c.detailLabel.stringValue = bytes(s.read + s.write) + "/s"
      case .network: c.detailLabel.stringValue = bytes(s.received + s.sent) + "/s"
      case .gpu: c.detailLabel.stringValue = gpu == nil ? "Not detected" : "Utilization unavailable"
      case .battery:
        c.detailLabel.stringValue =
          battery.map { String(format: "%.0f%%", $0) } ?? "AC power / no battery"
      case .swap: c.detailLabel.stringValue = bytes(Double(raw.swap_used))
      case .thermal: c.detailLabel.stringValue = thermal
      }
      c.graph.needsDisplay = true
    }
    heading.stringValue = selected.rawValue
    hardware.stringValue = ""
    upper.stringValue = "% Utilization"
    limit.stringValue = "100%"
    graph.color = selected.color
    graph.points = series(selected)
    graph.second = []
    graph.seconds = historySeconds
    graph.maxValue = 100
    graph.unavailable = nil
    timeline.stringValue = "\(Int(historySeconds)) seconds"
    note.stringValue = ""
    var pairs: [(String, String)] = []
    switch selected {
    case .cpu:
      hardware.stringValue = cString(raw.cpu_brand)
      pairs = [
        ("Utilization", String(format: "%.1f%%", s.cpu)), ("Processes", "\(processes.count)"),
        ("Threads", "\(processes.reduce(0){$0+Int($1.threads)})"),
        ("Logical processors", "\(raw.logical)"),
        (
          "Core classes",
          "\(hardwareClassName("hw.perflevel0.name", fallback: "Class 0")) \(raw.performance) / \(hardwareClassName("hw.perflevel1.name", fallback: "Class 1")) \(raw.efficiency)"
        ),
        ("Up time", duration(raw.uptime)),
        (
          "Load average (1 / 5 / 15)",
          String(format: "%.2f / %.2f / %.2f", raw.load1, raw.load5, raw.load15)
        ), ("Current clock", "Not exposed"), ("Architecture", "Apple Silicon"),
      ]
      note.stringValue =
        "CPU percentages use total machine capacity (0–100%), matching Task Manager. Load average counts runnable and waiting tasks. Dynamic clock telemetry is not publicly exposed."
    case .memory:
      hardware.stringValue = bytes(Double(raw.ram)) + " installed"
      upper.stringValue = "Physical memory in use"
      pairs = [
        ("In use", bytes(Double(s.used))), ("Available (estimate)", bytes(Double(s.available))),
        ("Inactive / cached", bytes(Double(raw.inactive))), ("Wired", bytes(Double(raw.wired))),
        ("Compressed", bytes(Double(raw.compressed))), ("Purgeable", bytes(Double(raw.purgeable))),
        ("Free pages", bytes(Double(raw.free_bytes))), ("Swap used", bytes(Double(raw.swap_used))),
        (
          "Memory pressure",
          raw.pressure == 1
            ? "Normal"
            : (raw.pressure == 2 ? "Warning" : (raw.pressure == 4 ? "Critical" : "Unavailable"))
        ),
      ]
      note.stringValue =
        "In use = active + wired + compressor pages. Available = physical RAM − in use. These are VM estimates; purgeable and cached categories overlap. Process tables show RSS, which can double-count shared pages."
    case .disk:
      hardware.stringValue = cString(raw.device)
      upper.stringValue = "Read — solid    Write — dashed"
      graph.second = history.map { ($0.timestamp.timeIntervalSince1970, $0.write) }
      graph.maxValue = max(1024, (history.map { max($0.read, $0.write) }.max() ?? 0) * 1.15)
      limit.stringValue = bytes(graph.maxValue) + "/s"
      if raw.disk_valid == 0 {
        graph.unavailable = "Disk throughput counters are unavailable on this storage driver."
      }
      pairs = [
        ("Read speed", raw.disk_valid == 1 ? bytes(s.read) + "/s" : "Unavailable"),
        ("Write speed", raw.disk_valid == 1 ? bytes(s.write) + "/s" : "Unavailable"),
        ("Active time", "Not exposed"), ("Data volume capacity", bytes(Double(raw.disk_capacity))),
        ("Available space", bytes(Double(raw.disk_free))), ("Filesystem", cString(raw.filesystem)),
        ("Mount point", cString(raw.mount)), ("Storage scope", "All exposed block drivers"),
        ("Device type", "Not exposed"),
      ]
      note.stringValue =
        "Throughput sums IOKit block-storage counters where drivers publish them. Capacity describes the data volume; APFS volumes share container space. Active time is not inferred from throughput."
    case .network:
      hardware.stringValue = "Physical interfaces"
      upper.stringValue = "Receive — solid    Send — dashed"
      graph.second = history.map { ($0.timestamp.timeIntervalSince1970, $0.sent) }
      graph.maxValue = max(1024, (history.map { max($0.received, $0.sent) }.max() ?? 0) * 1.15)
      limit.stringValue = bytes(graph.maxValue) + "/s"
      pairs = [
        ("Receive", bytes(s.received) + "/s"), ("Send", bytes(s.sent) + "/s"),
        ("Link speed", "Not exposed"),
        ("Interfaces / IPv4", cString(raw.interfaces).trimmingCharacters(in: .newlines)),
        ("Total received", bytes(Double(raw.net_in))), ("Total sent", bytes(Double(raw.net_out))),
      ]
      note.stringValue =
        "Aggregated en* interface counters. Loopback and VPN tunnels are excluded to avoid counting traffic twice. Per-process network attribution is unavailable through supported general-purpose APIs."
    case .gpu:
      hardware.stringValue = gpu?.name ?? "Not detected"
      upper.stringValue = "GPU utilization"
      graph.unavailable =
        "macOS does not publish supported system-wide GPU utilization.\nMetal device information is available below."
      pairs = [
        ("Device", gpu?.name ?? "Not detected"),
        ("Unified memory", gpu?.hasUnifiedMemory == true ? "Yes" : "No"),
        (
          "Recommended working set",
          gpu.map { bytes(Double($0.recommendedMaxWorkingSetSize)) } ?? "—"
        ), ("Per-process GPU", "Not exposed"), ("GPU engines", "Not exposed"),
        ("Telemetry API", "Metal device capabilities"),
      ]
      note.stringValue =
        "The working-set value is Metal's recommended limit, not current GPU memory usage. No private IOAccelerator properties or elevated powermetrics sampling are used."
    case .battery:
      hardware.stringValue = batteryState
      upper.stringValue = "Battery charge"
      if battery == nil {
        graph.unavailable =
          "No internal battery was reported by IOKit.\nThis Mac may be connected to AC power without a battery."
      }
      pairs = [
        ("Charge", battery.map { String(format: "%.0f%%", $0) } ?? "Not available"),
        ("Power source", batteryState), ("Thermal state", thermal),
        ("Low power mode", ProcessInfo.processInfo.isLowPowerModeEnabled ? "Enabled" : "Disabled"),
        ("Energy impact", "Not exposed"), ("Package power", "Requires elevated tools"),
      ]
      note.stringValue =
        "Battery charge comes from IOKit power sources. Energy Impact is an Apple-specific metric and is not approximated from CPU usage."
    case .swap:
      hardware.stringValue = "Virtual memory"
      upper.stringValue = "Swap in use"
      graph.maxValue = max(1024, Double(raw.swap_total))
      limit.stringValue = bytes(graph.maxValue)
      pairs = [
        ("Used", bytes(Double(raw.swap_used))), ("Allocated", bytes(Double(raw.swap_total))),
        (
          "Free in allocation",
          bytes(Double(raw.swap_total >= raw.swap_used ? raw.swap_total - raw.swap_used : 0))
        ), ("Compressed memory", bytes(Double(raw.compressed))),
        ("Physical RAM", bytes(Double(raw.ram))), ("Managed by", "macOS dynamic pager"),
      ]
      note.stringValue =
        "Swap allocation can grow and shrink as macOS manages virtual memory. The graph scale follows the current allocation."
    case .thermal:
      hardware.stringValue = "System thermal pressure"
      upper.stringValue = "Nominal → Fair → Serious → Critical"
      limit.stringValue = "Critical"
      graph.maxValue = 3
      pairs = [
        ("Thermal state", thermal),
        ("Low power mode", ProcessInfo.processInfo.isLowPowerModeEnabled ? "Enabled" : "Disabled"),
        ("Temperature", "Not exposed"),
      ]
      note.stringValue =
        "Thermal state is a discrete system pressure indicator, not a temperature reading. Values come from ProcessInfo."
    }
    if statKeys == pairs.map({ $0.0 }) {
      for (index, pair) in pairs.enumerated() { statValues[index].stringValue = pair.1 }
    } else {
      statKeys = pairs.map { $0.0 }
      statValues.removeAll()
      stats.arrangedSubviews.forEach {
        stats.removeArrangedSubview($0)
        $0.removeFromSuperview()
      }
      for start in stride(from: 0, to: pairs.count, by: 3) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 20
        for pair in pairs[start..<min(start + 3, pairs.count)] {
          let value = label(pair.1, 16, .medium)
          statValues.append(value)
          value.maximumNumberOfLines = 2
          value.lineBreakMode = .byTruncatingMiddle
          let cell = stack(
            [label(pair.0, 11, .regular, .secondaryLabelColor), value], .vertical, 4)
          row.addArrangedSubview(cell)
        }
        stats.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stats.widthAnchor).isActive = true
      }
    }
    graph.needsDisplay = true
  }
}
