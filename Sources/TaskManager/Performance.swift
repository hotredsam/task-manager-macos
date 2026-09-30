import AppKit
import Metal
import TaskCore

func hardwareClassName(_ key: String, fallback: String) -> String {
  var buffer = [CChar](repeating: 0, count: 128)
  var count = buffer.count
  return sysctlbyname(key, &buffer, &count, nil, 0) == 0 ? String(cString: buffer) : fallback
}

enum Resource: String, CaseIterable {
  case cpu = "CPU"
  case memory = "Memory"
  case disk = "Disk"
  case network = "Network"
  case gpu = "GPU"
  var color: NSColor {
    switch self {
    case .cpu: return accent
    case .memory: return .systemPurple
    case .disk: return .systemGreen
    case .network: return .systemOrange
    case .gpu: return .systemTeal
    }
  }
}
final class GraphView: NSView {
  var contextProvider: (() -> NSMenu?)?
  var doubleClick: (() -> Void)?
  override func menu(for event: NSEvent) -> NSMenu? { contextProvider?() }
  override func rightMouseDown(with event: NSEvent) {
    if let menu = contextProvider?() {
      WindowsMenu.show(menu, at: convert(event.locationInWindow, from: nil), in: self)
    }
  }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { doubleClick?() } else { super.mouseDown(with: event) }
  }
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
  let graphHost = NSView()
  let coreGrid = LogicalCPUGrid()
  var logicalMode = UserDefaults.standard.bool(forKey: "cpuLogicalGraphs")
  var kernelTimes = UserDefaults.standard.bool(forKey: "cpuKernelTimes")
  var summaryMode = false
  var detailSections: [NSView] = []
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
    cardScroll.contentView = FlippedClipView()
    cardScroll.drawsBackground = false
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
    graphHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 215).isActive = true
    // The graph consumes the available height, including summary mode.
    graphHost.setContentHuggingPriority(.defaultLow, for: .vertical)
    stats.orientation = .vertical
    stats.alignment = .leading
    stats.spacing = 16
    note.isHidden = true
    note.maximumNumberOfLines = 4
    note.lineBreakMode = .byWordWrapping
    let timeSpacer = NSView()
    timeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let timeRow = stack([timeline, timeSpacer, nowLabel])
    let detail = stack([head, graphHeader, graphHost, timeRow, stats, note], .vertical, 12)
    detail.edgeInsets = NSEdgeInsets(top: 26, left: 28, bottom: 24, right: 28)
    for v in [head, graphHeader, graphHost, timeRow, stats, note] {
      v.widthAnchor.constraint(equalTo: detail.widthAnchor, constant: -56).isActive = true
    }
    pin(graph, graphHost)
    pin(coreGrid, graphHost)
    coreGrid.isHidden = true
    graph.contextProvider = { [weak self] in self?.graphMenu() }
    coreGrid.contextProvider = { [weak self] in self?.graphMenu() }
    graph.doubleClick = { [weak self] in self?.toggleSummary() }
    detailSections = [head, graphHeader, timeRow, stats, note]
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
    render()
  }
  func graphMenu() -> NSMenu {
    let menu = NSMenu()
    if selected == .cpu {
      let item = NSMenuItem(title: "Change graph to", action: nil, keyEquivalent: "")
      let choices = NSMenu()
      for (title, tag) in [("Overall utilization", 0), ("Logical processors", 1)] {
        let choice = NSMenuItem(title: title, action: #selector(changeGraph(_:)), keyEquivalent: "")
        choice.tag = tag
        choice.target = self
        choice.state = (logicalMode == (tag == 1)) ? .on : .off
        choices.addItem(choice)
      }
      let numa = NSMenuItem(title: "NUMA nodes", action: nil, keyEquivalent: "")
      numa.isEnabled = false
      choices.autoenablesItems = false
      choices.addItem(numa)
      item.submenu = choices
      menu.addItem(item)
      let kernel = NSMenuItem(
        title: "Show kernel times", action: #selector(toggleKernel), keyEquivalent: "")
      kernel.target = self
      kernel.state = kernelTimes ? .on : .off
      menu.addItem(kernel)
      menu.addItem(.separator())
    }
    let summary = NSMenuItem(
      title: "Graph summary view", action: #selector(toggleSummary), keyEquivalent: "")
    summary.target = self
    summary.state = summaryMode ? .on : .off
    menu.addItem(summary)
    let view = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
    let resources = NSMenu()
    resources.autoenablesItems = false
    for (index, resource) in Resource.allCases.enumerated() {
      let item = NSMenuItem(
        title: resource.rawValue, action: #selector(selectResourceMenu(_:)), keyEquivalent: "")
      item.target = self
      item.tag = index
      item.state = selected == resource ? .on : .off
      resources.addItem(item)
    }
    view.submenu = resources
    menu.addItem(view)
    menu.addItem(.separator())
    let copy = NSMenuItem(title: "Copy", action: #selector(copyPerformance), keyEquivalent: "c")
    copy.target = self
    menu.addItem(copy)
    return menu
  }
  @objc func selectResourceMenu(_ item: NSMenuItem) {
    selected = Resource.allCases[item.tag]
    render()
  }
  @objc func changeGraph(_ item: NSMenuItem) {
    logicalMode = item.tag == 1
    UserDefaults.standard.set(logicalMode, forKey: "cpuLogicalGraphs")
    render()
  }
  @objc func toggleKernel() {
    kernelTimes.toggle()
    UserDefaults.standard.set(kernelTimes, forKey: "cpuKernelTimes")
    render()
  }
  @objc func toggleSummary() {
    summaryMode.toggle()
    for view in detailSections { view.isHidden = summaryMode || view === note }
  }
  @objc func copyPerformance() {
    let lines =
      [heading.stringValue, hardware.stringValue]
      + zip(statKeys, statValues).map { "\($0.0)\t\($0.1.stringValue)" }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
  }
  var historySeconds: Double {
    let value = UserDefaults.standard.double(forKey: "graphSeconds")
    return value > 0 ? value : 60
  }
  func series(_ r: Resource) -> [(Double, Double)] {
    return history.map { s in
      let value: Double
      switch r {
      case .cpu: value = s.cpu
      case .memory: value = s.memoryPercent
      case .disk: value = s.read
      case .network: value = s.received
      default: value = 0
      }
      return (s.timestamp.timeIntervalSince1970, value)
    }
  }
  func render() {
    let s = current
    let raw = s.raw
    for r in Resource.allCases {
      let c = cards[r]!
      c.selected = selected == r
      c.graph.points = series(r)
      c.graph.seconds = historySeconds
      c.graph.unavailable = r == .gpu ? "Unavailable" : nil
      c.graph.maxValue =
        [Resource.disk, .network].contains(r)
        ? max(1, c.graph.points.map(\.1).max() ?? 1) : 100
      switch r {
      case .cpu: c.detailLabel.stringValue = String(format: "%.1f%%", s.cpu)
      case .memory:
        c.detailLabel.stringValue =
          String(format: "%.0f%%", s.memoryPercent) + "  ·  " + bytes(Double(raw.ram))
      case .disk: c.detailLabel.stringValue = bytes(s.read + s.write) + "/s"
      case .network: c.detailLabel.stringValue = bytes(s.received + s.sent) + "/s"
      case .gpu: c.detailLabel.stringValue = gpu == nil ? "Not detected" : "Utilization unavailable"
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
    let showCores = selected == .cpu && logicalMode
    graph.isHidden = showCores
    coreGrid.isHidden = !showCores
    if showCores {
      coreGrid.update(
        history: history, count: max(Int(raw.logical), s.logicalCPUs.count),
        seconds: historySeconds, kernel: kernelTimes)
      upper.stringValue = "% Utilization over \(Int(historySeconds)) seconds"
    }
    if selected == .cpu && kernelTimes {
      graph.second = history.compactMap { sample in
        let values = sample.logicalCPUs.compactMap { $0?.kernel }
        guard !values.isEmpty else { return nil }
        return (sample.timestamp.timeIntervalSince1970, values.reduce(0, +) / Double(values.count))
      }
    }
    timeline.stringValue = "\(Int(historySeconds)) seconds"
    note.stringValue = ""
    var pairs: [(String, String)] = []
    switch selected {
    case .cpu:
      hardware.stringValue = cString(raw.cpu_brand)
      pairs = [
        ("Utilization", String(format: "%.0f%%", s.cpu)),
        ("Speed", "—"),
        ("Processes", "\(processes.count)"),
        ("Threads", "\(processes.reduce(0){$0+Int($1.threads)})"),
        ("Handles", "—"),
        (
          "Up time",
          "\(Int(raw.uptime)/86400):" + duration(raw.uptime.truncatingRemainder(dividingBy: 86400))
        ),
        ("Base speed:", "—"),
        ("Cores:", "\(raw.physical)"),
        ("Logical processors:", "\(raw.logical)"),
        (
          "\(hardwareClassName("hw.perflevel0.name",fallback:"Performance")):", "\(raw.performance)"
        ),
        ("\(hardwareClassName("hw.perflevel1.name",fallback:"Efficiency")):", "\(raw.efficiency)"),
        (
          "Load (1 / 5 / 15):",
          String(format: "%.2f / %.2f / %.2f", raw.load1, raw.load5, raw.load15)
        ),
        ("Architecture:", "Apple Silicon"),
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
    }
    heading.toolTip = note.stringValue
    graph.toolTip = note.stringValue
    if statKeys == pairs.map({ $0.0 }) {
      for (index, pair) in pairs.enumerated() { statValues[index].stringValue = pair.1 }
    } else {
      statKeys = pairs.map { $0.0 }
      statValues.removeAll()
      stats.arrangedSubviews.forEach {
        stats.removeArrangedSubview($0)
        $0.removeFromSuperview()
      }
      statValues = pairs.map { label($0.1, selected == .cpu ? 12 : 16) }
      if selected == .cpu {
        let live = stack([], .vertical, 12)
        for indices in [[0, 1], [2, 3, 4], [5]] {
          let cells = indices.map { index -> NSView in
            statValues[index].font = winFont(20)
            return stack(
              [label(pairs[index].0, 11, .regular, .secondaryLabelColor), statValues[index]],
              .vertical, 2)
          }
          let row = stack(cells, .horizontal, 20)
          live.addArrangedSubview(row)
        }
        let metadata = stack([], .vertical, 5)
        for index in 6..<pairs.count {
          let title = label(pairs[index].0, 11, .regular, .secondaryLabelColor)
          title.widthAnchor.constraint(equalToConstant: 118).isActive = true
          metadata.addArrangedSubview(stack([title, statValues[index]], .horizontal, 6))
        }
        let row = stack([live, metadata], .horizontal, 28)
        row.alignment = .top
        stats.addArrangedSubview(row)
        row.widthAnchor.constraint(lessThanOrEqualTo: stats.widthAnchor).isActive = true
      } else {
        for start in stride(from: 0, to: pairs.count, by: 3) {
          let row = NSStackView()
          row.orientation = .horizontal
          row.alignment = .top
          row.distribution = .fillEqually
          row.spacing = 20
          for index in start..<min(start + 3, pairs.count) {
            let value = statValues[index]
            value.maximumNumberOfLines = 2
            value.lineBreakMode = .byTruncatingMiddle
            row.addArrangedSubview(
              stack(
                [label(pairs[index].0, 11, .regular, .secondaryLabelColor), value], .vertical, 4))
          }
          stats.addArrangedSubview(row)
          row.widthAnchor.constraint(equalTo: stats.widthAnchor).isActive = true
        }
      }
    }
    graph.needsDisplay = true
  }
}

final class LogicalCPUGrid: NSView {
  var graphs: [GraphView] = []
  var labels: [NSTextField] = []
  var contextProvider: (() -> NSMenu?)?
  override var isFlipped: Bool { true }
  override func menu(for event: NSEvent) -> NSMenu? { contextProvider?() }
  override func rightMouseDown(with event: NSEvent) {
    if let menu = contextProvider?() {
      WindowsMenu.show(menu, at: convert(event.locationInWindow, from: nil), in: self)
    }
  }
  func update(history: [SystemSnapshot], count: Int, seconds: Double, kernel: Bool) {
    if graphs.count != count {
      subviews.forEach { $0.removeFromSuperview() }
      graphs = []
      labels = []
      for index in 0..<count {
        let graph = GraphView()
        graph.compact = true
        graph.contextProvider = { [weak self] in self?.contextProvider?() }
        let title = label("CPU \(index)", 10, .regular, .secondaryLabelColor)
        graph.addSubview(title)
        addSubview(graph)
        graphs.append(graph)
        labels.append(title)
      }
    }
    for index in graphs.indices {
      let graph = graphs[index]
      graph.seconds = seconds
      graph.points = history.compactMap { sample in
        guard sample.logicalCPUs.indices.contains(index), let value = sample.logicalCPUs[index]
        else { return nil }
        return (sample.timestamp.timeIntervalSince1970, value.total)
      }
      graph.second =
        kernel
        ? history.compactMap { sample in
          guard sample.logicalCPUs.indices.contains(index), let value = sample.logicalCPUs[index]
          else { return nil }
          return (sample.timestamp.timeIntervalSince1970, value.kernel)
        } : []
      graph.toolTip =
        "CPU \(index) • "
        + (graph.points.last.map { String(format: "%.1f%%", $0.1) } ?? "Collecting…")
      graph.setAccessibilityLabel(graph.toolTip)
      graph.needsDisplay = true
    }
    needsLayout = true
  }
  override func layout() {
    super.layout()
    guard !graphs.isEmpty else { return }
    let aspect = Double(max(1, bounds.width) / max(1, bounds.height))
    let divisors = (1...graphs.count).filter { graphs.count % $0 == 0 }
    let columns =
      divisors.min { a, b in
        abs(log(aspect * Double(graphs.count) / Double(a * a) / 1.4))
          < abs(log(aspect * Double(graphs.count) / Double(b * b) / 1.4))
      } ?? 1
    let rows = Int(ceil(Double(graphs.count) / Double(columns)))
    let gap: CGFloat = 6
    let width = max(0, (bounds.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
    let height = max(0, (bounds.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
    for i in graphs.indices {
      graphs[i].frame = NSRect(
        x: CGFloat(i % columns) * (width + gap), y: CGFloat(i / columns) * (height + gap),
        width: width, height: height)
      labels[i].frame = NSRect(
        x: 5, y: 3, width: max(0, width - 10), height: min(14, max(0, height - 3)))
    }
  }
}
