import AppKit
import Security
import ServiceManagement
import SystemBridge
import TaskCore

struct Column {
  let key: String, title: String, width: CGFloat
  var numeric: Bool = false
  var hidden: Bool = false
}
struct DisplayRow {
  var id: String
  var values: [String: String]
  var numbers: [String: Double] = [:]
  var process: ProcessRecord?
  var service: ServiceRecord?
  var members: [ProcessRecord] = []
  var section = false
  var group = false
  var indent: CGFloat = 0
  var iconPath: String = ""
}

enum Page: String, CaseIterable {
  case processes = "Processes"
  case performance = "Performance"
  case history = "App history"
  case startup = "Startup apps"
  case users = "Users"
  case details = "Details"
  case services = "Services"
  case settings = "Settings"
  var symbol: String {
    switch self {
    case .processes: return "square.stack.3d.up"
    case .performance: return "waveform.path.ecg"
    case .history: return "clock.arrow.circlepath"
    case .startup: return "power"
    case .users: return "person.2"
    case .details: return "list.bullet.rectangle"
    case .services: return "gearshape.2"
    case .settings: return "gearshape"
    }
  }
  var subtitle: String {
    switch self {
    case .processes: return "Applications and background processes"
    case .performance: return "Live resource usage across your Mac"
    case .history: return "Resource usage observed by Task Manager"
    case .startup: return "Login and background launch mechanisms"
    case .users: return "Process ownership and login sessions"
    case .details: return "All processes · detailed system information"
    case .services: return "launchd agents, daemons, and registered jobs"
    case .settings: return "Personalize Task Manager"
    }
  }
}

final class AppController: NSObject, NSApplicationDelegate, NSTableViewDataSource,
  NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSWindowDelegate
{
  var window: NSWindow!
  let sidebar = Surface(winBackdrop)
  let content = Surface(winContent)
  let pageTitle = label("Processes", 14, .semibold)
  let subtitle = label("", 12, .regular, .secondaryLabelColor)
  let search = WindowsSearchField()
  let table = ProcessTable()
  let scroll = NSScrollView()
  let footer = label("Collecting system data…", 11, .regular, .secondaryLabelColor)
  let activity = label("●  Live", 11, .medium, accent)
  var sidebarWidth: NSLayoutConstraint!
  var navButtons: [Page: NSButton] = [:]
  var collapsed = false
  var actionBar = NSStackView()
  var commandSurface: Surface!
  let commandRule = rule()
  var endButton: NSButton!
  var efficiencyButton: NSButton!
  var caption: WindowsTitleBar!
  var inspectButton: NSButton!
  var refreshButton: NSButton!
  var columnsButton: NSPopUpButton!
  var page: Page = .processes
  var rows: [DisplayRow] = []
  var columns: [Column] = []
  var records: [ProcessRecord] = []
  var system = SystemSnapshot()
  var services: [ServiceRecord] = []
  var sessions: [String: [String]] = [:]
  var expanded: Set<String> = []
  var sortKey = "cpu"
  var ascending = false
  var timer: Timer?
  var serviceTimer: Timer?
  var inFlight = false
  var serviceInFlight = false
  let queue = DispatchQueue(label: "com.local.TaskManager.sampling", qos: .utility)
  let serviceQueue = DispatchQueue(label: "com.local.TaskManager.services", qos: .utility)
  let sampler = Sampler()
  let powerMode = PowerModeController()
  let history = HistoryStore()
  var samples: [SystemSnapshot] = []
  var perf: PerformanceView!
  var settingsView: NSView!
  var icons: [String: NSImage] = [:]
  var inspector: NSWindow?
  var sampleCount = 0
  var lastSave = Date.distantPast
  let defaults = UserDefaults.standard
  var speed: RefreshSpeed {
    get { RefreshSpeed(rawValue: defaults.string(forKey: "speed") ?? "Normal") ?? .normal }
    set {
      defaults.set(newValue.rawValue, forKey: "speed")
      startTimer()
    }
  }
  var grouped: Bool {
    defaults.object(forKey: "grouped") == nil || defaults.bool(forKey: "grouped")
  }
  var historyURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("TaskManager/history.json")
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
      let icon = NSImage(contentsOfFile: path)
    {
      NSApp.applicationIconImage = icon
    }
    if !defaults.bool(forKey: "windowsChromeV2") {
      defaults.set(true, forKey: "columns.Processes.pid")
      defaults.set(true, forKey: "columns.Processes.user")
      defaults.set(false, forKey: "columns.Processes.network")
      defaults.set(true, forKey: "windowsChromeV2")
    }
    if !defaults.bool(forKey: "windowsReferenceV3") {
      defaults.set("Light", forKey: "theme")
      defaults.set(true, forKey: "windowsReferenceV3")
    }
    installMenus()
    loadHistory()
    buildWindow()
    showPage(Page(rawValue: defaults.string(forKey: "startPage") ?? "Processes") ?? .processes)
    startTimer()
    powerMode.onChange = { [weak self] in self?.updateActions() }
    powerMode.start()
    poll()
    scanServices()
    serviceTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
      guard let self = self, self.speed != .paused else { return }
      self.scanServices()
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    if CommandLine.arguments.contains("--ui-test") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.runUITests() }
    }
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationWillTerminate(_ notification: Notification) { saveHistory() }
  func windowDidMiniaturize(_ notification: Notification) {
    if defaults.bool(forKey: "hideWhenMinimized") { NSApp.hide(nil) }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
    return true
  }
  func installMenus() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(withTitle: "About Task Manager", action: #selector(about), keyEquivalent: "")
      .target = self
    appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
      .target = self
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "Quit Task Manager", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    let edit = NSMenuItem()
    edit.title = "Edit"
    main.addItem(edit)
    edit.submenu = NSMenu(title: "Edit")
    for (title, sel, key) in [
      ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
      ("Select All", #selector(NSText.selectAll(_:)), "a"),
    ] { edit.submenu?.addItem(withTitle: title, action: sel, keyEquivalent: key) }
    let view = NSMenuItem()
    view.title = "View"
    main.addItem(view)
    view.submenu = NSMenu(title: "View")
    for (i, p) in Page.allCases.enumerated() {
      let item = view.submenu!.addItem(
        withTitle: p.rawValue, action: #selector(menuNavigate(_:)), keyEquivalent: String(i + 1))
      item.tag = i
      item.target = self
    }
    view.submenu?.addItem(.separator())
    view.submenu?.addItem(
      withTitle: "Find Process", action: #selector(focusSearch), keyEquivalent: "f"
    ).target = self
    view.submenu?.addItem(
      withTitle: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"
    ).target = self
    view.submenu?.addItem(
      withTitle: "Pause / Resume", action: #selector(togglePause), keyEquivalent: "p"
    ).target = self
    view.submenu?.addItem(
      withTitle: "Toggle Sidebar", action: #selector(toggleSidebar), keyEquivalent: "\\"
    ).target = self
    NSApp.mainMenu = main
  }
  func buildWindow() {
    window = WindowsWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1360, height: 830),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false
    )
    window.title = "Task Manager"
    window.delegate = self
    window.minSize = NSSize(width: 1000, height: 650)
    window.center()
    window.setFrameAutosaveName("TaskManagerWindow")
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = false
    for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      window.standardWindowButton(kind)?.isHidden = true
    }
    window.level = defaults.bool(forKey: "alwaysTop") ? .floating : .normal
    let root = Surface(winBackdrop)
    caption = WindowsTitleBar(search: search, controller: self)
    (window as? WindowsWindow)?.caption = caption
    caption.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(caption)
    NSLayoutConstraint.activate([
      caption.topAnchor.constraint(equalTo: root.topAnchor),
      caption.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      caption.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      caption.heightAnchor.constraint(equalToConstant: 48),
    ])
    window.contentView = root
    sidebar.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    content.layer?.cornerRadius = 8
    content.layer?.masksToBounds = true
    root.addSubview(sidebar)
    root.addSubview(content)
    sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: collapsed ? 48 : 240)
    NSLayoutConstraint.activate([
      sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      sidebar.topAnchor.constraint(equalTo: caption.bottomAnchor),
      sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebarWidth,
      content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
      content.topAnchor.constraint(equalTo: caption.bottomAnchor),
      content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    let nav = stack([], .vertical, 2)
    nav.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 8, right: 4)
    for (i, p) in Page.allCases.enumerated() {
      let b = button(p.rawValue, p.symbol, target: self, action: #selector(navigate(_:)))
      b.tag = i
      b.title = collapsed ? "" : p.rawValue
      b.toolTip = p.rawValue
      (b as? FlatButton)?.navigation = true
      b.isBordered = false
      b.alignment = .left
      b.imageHugsTitle = true
      b.imagePosition = .imageLeading
      b.contentTintColor = .labelColor
      b.wantsLayer = true
      b.layer?.cornerRadius = 5
      b.heightAnchor.constraint(equalToConstant: 40).isActive = true
      nav.addArrangedSubview(b)
      b.widthAnchor.constraint(equalTo: nav.widthAnchor, constant: -8).isActive = true
      navButtons[p] = b
    }
    pin(nav, sidebar)
    nav.distribution = .fill
    let spacer = NSView()
    nav.insertArrangedSubview(spacer, at: 7)
    spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    search.placeholderString = "Type a name, publisher, or PID to search"
    search.delegate = self
    search.sendsSearchStringImmediately = true
    search.controlSize = .regular
    search.font = winFont(12)
    search.focusRingType = .none
    search.isBezeled = false
    search.setAccessibilityIdentifier("processSearch")
    endButton = button("End task", "xmark.circle", target: self, action: #selector(endTask))
    inspectButton = button(
      "Properties", "info.circle", target: self, action: #selector(inspectSelected))
    refreshButton = button(
      "Refresh", "arrow.clockwise", target: self, action: #selector(refreshNow))
    columnsButton = WindowsPopupButton(frame: .zero, pullsDown: true)
    columnsButton.controlSize = .small
    columnsButton.bezelStyle = .inline
    columnsButton.isBordered = false
    columnsButton.widthAnchor.constraint(equalToConstant: 65).isActive = true
    let run = button("Run new task", "plus.square", target: self, action: #selector(runNewTask))
    efficiencyButton = button(
      "Efficiency mode", "leaf", target: self, action: #selector(toggleEfficiencyMode))
    efficiencyButton.toolTip =
      "Toggle macOS Low Power Mode for the whole Mac."
    actionBar = stack(
      [pageTitle, NSView(), run, endButton, efficiencyButton, inspectButton, columnsButton],
      .horizontal, 12)
    actionBar.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
    actionBar.arrangedSubviews[1].setContentHuggingPriority(.defaultLow, for: .horizontal)
    table.delegate = self
    table.dataSource = self
    table.rowHeight = 30
    table.backgroundColor = winContent
    table.intercellSpacing = NSSize(width: 1, height: 0)
    table.usesAlternatingRowBackgroundColors = false
    table.style = .plain
    table.gridStyleMask = .solidVerticalGridLineMask
    table.gridColor = NSColor.separatorColor.withAlphaComponent(0.35)
    table.allowsMultipleSelection = true
    table.allowsColumnReordering = true
    table.allowsColumnResizing = true
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.target = self
    table.doubleAction = #selector(doubleClick)
    table.setAccessibilityIdentifier("processTable")
    table.contextProvider = { [weak self] row in self?.contextMenu(row) }
    table.deleteAction = { [weak self] in self?.endTask() }
    table.expandAction = { [weak self] expanded in self?.expandSelected(expanded) }
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    let body = NSView()
    body.setContentHuggingPriority(.defaultLow, for: .vertical)
    pin(scroll, body)
    perf = PerformanceView()
    pin(perf, body)
    perf.isHidden = true
    settingsView = makeSettings()
    pin(settingsView, body)
    settingsView.isHidden = true
    actionBar.heightAnchor.constraint(equalToConstant: 48).isActive = true
    commandSurface = Surface(winCommand)
    pin(actionBar, commandSurface)
    commandSurface.heightAnchor.constraint(equalToConstant: 48).isActive = true
    let outer = stack([commandSurface!, commandRule, body], .vertical, 0)
    pin(outer, content)
    for v in outer.arrangedSubviews {
      v.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
    }
    applyTheme()
    if let screen = window.screen ?? NSScreen.main {
      window.setContentSize(
        NSSize(
          width: min(1120, screen.visibleFrame.width - 60),
          height: min(720, screen.visibleFrame.height - 80)))
      window.center()
    }
  }
  func startTimer() {
    timer?.invalidate()
    if speed == .paused {
      history.suspend()
      queue.async { self.sampler.resetBaseline() }
    }
    if let interval = speed.interval {
      timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
        self?.poll()
      }
    }
    updateActivity()
  }
  func updateActivity() {
    activity.stringValue = speed == .paused ? "Ⅱ  Paused" : "●  Live · \(speed.rawValue)"
    activity.textColor = speed == .paused ? .systemOrange : accent
  }
  func poll(force: Bool = false) {
    guard !inFlight else { return }
    inFlight = true
    queue.async {
      let result = self.sampler.sample()
      DispatchQueue.main.async {
        self.inFlight = false
        guard self.speed != .paused || self.sampleCount == 0 || force else { return }
        self.records = result.0
        self.system = result.1
        self.sampleCount += 1
        self.samples.append(result.1)
        let seconds = self.defaults.double(forKey: "graphSeconds")
        let cutoff = Date().addingTimeInterval(-(seconds > 0 ? seconds : 60))
        self.samples.removeAll { $0.timestamp < cutoff }
        self.history.ingest(result.0, at: result.1.timestamp)
        self.updateContent()
        if Date().timeIntervalSince(self.lastSave) > 60 { self.saveHistory() }
      }
    }
  }
  func scanServices(force: Bool = false) {
    guard !serviceInFlight else { return }
    serviceInFlight = true
    serviceQueue.async {
      let services = LaunchServices.scan(uid: getuid())
      var buffer = [CChar](repeating: 0, count: 32768)
      _ = tm_sessions(&buffer, Int32(buffer.count))
      let text = String(cString: buffer)
      var sessions: [String: [String]] = [:]
      for line in text.split(separator: "\n") {
        let c = line.split(separator: "\t")
        if c.count == 2 { sessions[String(c[0]), default: []].append(String(c[1])) }
      }
      DispatchQueue.main.async {
        self.serviceInFlight = false
        guard self.speed != .paused || self.services.isEmpty || force else { return }
        self.services = services
        self.sessions = sessions
        if [.services, .startup, .users].contains(self.page) { self.updateContent() }
      }
    }
  }
  func loadHistory() {
    if let data = try? Data(contentsOf: historyURL),
      let entries = try? JSONDecoder().decode([String: HistoryEntry].self, from: data)
    {
      history.entries = entries
    }
  }
  func saveHistory() {
    lastSave = Date()
    let entries = history.entries
    let url = historyURL
    serviceQueue.async {
      do {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
      } catch { NSLog("History save: %@", error.localizedDescription) }
    }
  }
  @objc func navigate(_ sender: NSButton) { showPage(Page.allCases[sender.tag]) }
  @objc func menuNavigate(_ sender: NSMenuItem) { showPage(Page.allCases[sender.tag]) }
  @objc func openSettings() { showPage(.settings) }
  func showPage(_ next: Page) {
    page = next
    commandSurface.isHidden = page == .settings
    commandRule.isHidden = page == .settings
    if page == .settings { syncSettings() }
    pageTitle.stringValue = page.rawValue
    subtitle.stringValue = page.subtitle
    for (p, b) in navButtons {
      (b as? FlatButton)?.selected = p == page
      b.contentTintColor = .labelColor
      b.setAccessibilityValue(p == page ? "Selected" : "")
    }
    search.isHidden = [.performance, .settings].contains(page)
    scroll.isHidden = [.performance, .settings].contains(page)
    perf.isHidden = page != .performance
    settingsView.isHidden = page != .settings
    sortKey =
      page == .history ? "time" : ([.startup, .services, .users].contains(page) ? "name" : "cpu")
    ascending = [.startup, .services, .users].contains(page)
    configureColumns()
    updateContent()
    updateActions()
    if !rows.isEmpty { table.scrollRowToVisible(0) }
  }
  @objc func toggleSidebar() {
    collapsed.toggle()
    sidebarWidth.constant = collapsed ? 48 : 240
    for (p, b) in navButtons {
      b.title = collapsed ? "" : p.rawValue
      b.toolTip = p.rawValue
    }
  }
  @objc func runNewTask() {
    let (accepted, value) = WindowsDialog(
      title: "Create new task",
      message:
        "Type the name of an application, or the full path of a program or document to open.",
      confirm: "OK", input: true
    ).run()
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard accepted, !name.isEmpty else { return }
    let path = (name as NSString).expandingTildeInPath
    if path.hasPrefix("/") {
      if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
        showError("Could not open \(name).")
      }
    } else {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      task.arguments = ["-a", name]
      task.standardError = FileHandle.nullDevice
      do { try task.run() } catch { showError(error.localizedDescription) }
    }
  }
  @objc func focusSearch() {
    if search.isHidden { showPage(.processes) }
    window.makeFirstResponder(search)
  }
  @objc func refreshNow() {
    poll(force: true)
    scanServices(force: true)
  }
  @objc func togglePause() {
    speed = speed == .paused ? .normal : .paused
    updateContent()
  }
  func controlTextDidChange(_ obj: Notification) { updateContent() }
  func configureColumns() {
    table.autosaveTableColumns = false
    table.autosaveName = nil
    for c in table.tableColumns { table.removeTableColumn(c) }
    let processColumns: [Column] = [
      Column(key: "name", title: "Name", width: 290),
      Column(key: "pid", title: "PID", width: 70, numeric: true, hidden: true),
      Column(key: "status", title: "Status", width: 94),
      Column(key: "user", title: "User", width: 130, hidden: true),
      Column(key: "cpu", title: "CPU", width: 95, numeric: true),
      Column(key: "memory", title: "Memory", width: 116, numeric: true),
      Column(key: "disk", title: "Disk", width: 108, numeric: true),
      Column(key: "network", title: "Network", width: 92, numeric: true),
      Column(key: "gpu", title: "GPU", width: 75, numeric: true, hidden: true),
      Column(key: "engine", title: "GPU engine", width: 110, hidden: true),
      Column(key: "time", title: "CPU time", width: 108, numeric: true, hidden: true),
      Column(key: "mempercent", title: "Memory %", width: 94, numeric: true, hidden: true),
      Column(key: "threads", title: "Threads", width: 78, numeric: true, hidden: true),
      Column(key: "energy", title: "Energy", width: 85, hidden: true),
      Column(key: "arch", title: "Architecture", width: 98, hidden: true),
      Column(key: "start", title: "Start time", width: 172, hidden: true),
      Column(key: "ppid", title: "Parent PID", width: 84, numeric: true, hidden: true),
      Column(key: "nice", title: "Nice", width: 68, numeric: true, hidden: true),
      Column(key: "path", title: "Executable path", width: 400, hidden: true),
      Column(key: "bundle", title: "Bundle ID", width: 260, hidden: true),
    ]
    switch page {
    case .processes, .details:
      columns = processColumns
      if page == .details {
        let visible: Set<String> = ["name", "pid", "status", "user", "cpu", "memory", "arch"]
        columns = columns.map {
          var c = $0
          c.hidden = !visible.contains(c.key)
          return c
        }
      }
    case .history:
      columns = [
        Column(key: "name", title: "Name", width: 280),
        Column(key: "time", title: "CPU time", width: 120, numeric: true),
        Column(key: "memory", title: "Peak process memory", width: 165, numeric: true),
        Column(key: "duration", title: "Observed duration", width: 155, numeric: true),
        Column(key: "disk", title: "Disk I/O", width: 130, numeric: true),
        Column(key: "path", title: "Path", width: 430),
      ]
    case .startup, .services:
      columns = [
        Column(key: "name", title: page == .services ? "Label" : "Name", width: 350),
        Column(key: "status", title: "Status", width: 100),
        Column(key: "publisher", title: "Publisher hint", width: 115),
        Column(key: "mechanism", title: "Mechanism", width: 120),
        Column(key: "domain", title: "Domain", width: 95),
        Column(key: "pid", title: "PID", width: 65, numeric: true),
        Column(key: "enabled", title: "Enabled", width: 90),
        Column(key: "managed", title: "Managed by", width: 120),
        Column(key: "path", title: "Property list", width: 380),
        Column(key: "program", title: "Program", width: 400),
        Column(key: "modified", title: "Modified", width: 175),
        Column(key: "impact", title: "Startup impact", width: 120),
      ]
    case .users:
      columns = [
        Column(key: "name", title: "User / process", width: 270),
        Column(key: "session", title: "Session", width: 190),
        Column(key: "count", title: "Processes", width: 100, numeric: true),
        Column(key: "cpu", title: "CPU", width: 110, numeric: true),
        Column(key: "memory", title: "Memory", width: 140, numeric: true),
        Column(key: "pid", title: "PID", width: 90, numeric: true),
        Column(key: "status", title: "Status", width: 110),
      ]
    default: columns = []
    }
    if page == .startup || page == .services {
      let keys =
        page == .startup
        ? ["name", "publisher", "status", "impact"]
        : ["name", "pid", "program", "status", "domain"]
      columns = columns.map {
        var column = $0
        column.hidden = !keys.contains(column.key)
        return column
      }
      columns.sort { (keys.firstIndex(of: $0.key) ?? 99) < (keys.firstIndex(of: $1.key) ?? 99) }
      if page == .services {
        for i in columns.indices {
          let c = columns[i]
          let titles = ["name": "Name", "program": "Description", "domain": "Group"]
          if let title = titles[c.key] {
            columns[i] = Column(
              key: c.key, title: title, width: c.key == "program" ? 300 : c.width,
              numeric: c.numeric, hidden: c.hidden)
          }
        }
      }
    }
    for c in columns {
      let tc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.key))
      tc.title = c.title
      tc.width = c.width
      tc.minWidth = 55
      tc.maxWidth = 1600
      tc.resizingMask = .userResizingMask
      tc.headerCell = MetricHeader(textCell: c.title)
      let key = "columns.\(page.rawValue).\(c.key)"
      tc.isHidden = defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : c.hidden
      if !["network", "gpu", "engine", "energy", "impact"].contains(c.key) {
        tc.sortDescriptorPrototype = NSSortDescriptor(key: c.key, ascending: !c.numeric)
      }
      table.addTableColumn(tc)
    }
    table.autosaveName = "TaskManager.Reference3.\(page.rawValue)"
    table.autosaveTableColumns = true
    table.headerView?.frame.size.height = [.processes, .users].contains(page) ? 52 : 26
    table.sortDescriptors = [NSSortDescriptor(key: sortKey, ascending: ascending)]
    columnsButton.removeAllItems()
    columnsButton.addItem(withTitle: "View")
    for (title, action) in [
      ("Refresh now", #selector(refreshNow)),
      ("Pause / resume", #selector(togglePause)),
    ] {
      columnsButton.addItem(withTitle: title)
      columnsButton.lastItem?.target = self
      columnsButton.lastItem?.action = action
    }
    columnsButton.menu?.addItem(.separator())
    let selectColumns = NSMenuItem(title: "Select columns", action: nil, keyEquivalent: "")
    let columnMenu = NSMenu()
    columnMenu.autoenablesItems = false
    columnsButton.menu?.addItem(selectColumns)
    selectColumns.submenu = columnMenu
    for (i, c) in columns.enumerated() {
      let item = columnMenu.addItem(withTitle: c.title, action: nil, keyEquivalent: "")
      item.tag = i
      item.representedObject = c.key
      item.state = table.tableColumns[i].isHidden ? .off : .on
      item.target = self
      item.action = #selector(toggleColumn(_:))
    }
    columnsButton.isHidden = page == .settings
    if page == .performance {
      columnsButton.removeAllItems()
      columnsButton.addItem(withTitle: "•••")
      for (title, selector) in [
        ("Copy", #selector(copyPerformanceInfo)),
        ("Resource Monitor", #selector(openResourceMonitor)),
      ] {
        columnsButton.addItem(withTitle: title)
        columnsButton.lastItem?.target = self
        columnsButton.lastItem?.action = selector
      }
    }
  }
  @objc func copyPerformanceInfo() { perf.copyPerformance() }
  @objc func openResourceMonitor() {
    NSWorkspace.shared.open(
      URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
  }
  @objc func toggleColumn(_ item: NSMenuItem) {
    guard columns.indices.contains(item.tag) else { return }
    guard let key = item.representedObject as? String,
      let tc = table.tableColumns.first(where: { $0.identifier.rawValue == key })
    else { return }
    if tc.identifier.rawValue == "name" { return }
    tc.isHidden.toggle()
    item.state = tc.isHidden ? .off : .on
    defaults.set(tc.isHidden, forKey: "columns.\(page.rawValue).\(tc.identifier.rawValue)")
  }
  func processRow(_ p: ProcessRecord, indent: CGFloat = 0) -> DisplayRow {
    let name = (page == .details || indent > 0) ? p.name : (p.appName.isEmpty ? p.name : p.appName)
    var v: [String: String] = [
      "name": name, "pid": "\(p.pid)", "ppid": "\(p.ppid)", "status": p.status, "user": p.user,
      "cpu": p.metricsValid ? String(format: "%.1f%%", p.cpu) : "—",
      "memory": p.metricsValid ? bytes(Double(p.memory)) : "—",
      "mempercent": p.metricsValid
        ? String(format: "%.1f%%", Metrics.memoryPercent(p.memory, total: system.raw.ram)) : "—",
      "disk": p.ioValid ? bytes(p.diskRead + p.diskWrite) + "/s" : "—",
      "time": p.metricsValid ? duration(Double(p.cpuNS) / 1e9) : "—",
      "threads": p.metricsValid ? "\(p.threads)" : "—", "nice": "\(p.nice)", "arch": p.architecture,
      "path": p.path.isEmpty ? "Unavailable" : p.path,
      "bundle": p.bundleID.isEmpty ? "—" : p.bundleID,
      "start": dateFormat.string(from: Date(timeIntervalSince1970: Double(p.start))),
    ]
    for key in ["gpu", "engine", "network", "energy"] { v[key] = "—" }
    var n: [String: Double] = [:]
    for c in columns { n[c.key] = p.number(c.key, total: system.raw.ram) }
    return DisplayRow(
      id: p.id, values: v, numbers: n, process: p, indent: indent,
      iconPath: p.appPath.isEmpty ? p.path : p.appPath)
  }
  func updateContent() {
    updateActivity()
    let q = search.stringValue
    let selection = Set(
      table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
    var next: [DisplayRow] = []
    switch page {
    case .processes where grouped:
      var groups: [DisplayRow] = []
      for g in ProcessLogic.groups(records) {
        let match = g.members.filter { $0.matches(q) }
        guard !match.isEmpty || g.name.localizedCaseInsensitiveContains(q) else { continue }
        if g.members.count == 1 {
          groups.append(processRow(g.members[0]))
          continue
        }
        var row = processRow(g.members[0])
        row.id = g.key
        row.group = true
        row.process = nil
        row.members = g.members
        row.values["name"] = "\(g.name) (\(g.members.count))"
        row.values["pid"] = ""
        row.values["status"] = ""
        row.values["cpu"] = String(format: "%.1f%%", g.cpu)
        row.values["memory"] = bytes(Double(g.memory))
        row.values["disk"] = bytes(g.members.reduce(0) { $0 + $1.diskRead + $1.diskWrite }) + "/s"
        row.numbers["cpu"] = g.cpu
        row.numbers["memory"] = Double(g.memory)
        row.numbers["disk"] = g.members.reduce(0) { $0 + $1.diskRead + $1.diskWrite }
        row.iconPath = g.key
        row.values["time"] = duration(g.members.reduce(0) { $0 + Double($1.cpuNS) / 1e9 })
        row.numbers["time"] = g.members.reduce(0) { $0 + Double($1.cpuNS) / 1e9 }
        row.values["threads"] = "\(g.members.reduce(0){$0+Int($1.threads)})"
        row.numbers["threads"] = Double(g.members.reduce(0) { $0 + Int($1.threads) })
        row.values["mempercent"] = String(
          format: "%.1f%%", Metrics.memoryPercent(g.memory, total: system.raw.ram))
        row.numbers["mempercent"] = Metrics.memoryPercent(g.memory, total: system.raw.ram)
        for key in ["pid", "ppid", "nice"] {
          row.values[key] = ""
          row.numbers[key] = nil
        }
        let owners = Set(g.members.map(\.user))
        row.values["user"] = owners.count == 1 ? owners.first! : "Mixed"
        let architectures = Set(g.members.map(\.architecture))
        row.values["arch"] = architectures.count == 1 ? architectures.first! : "Mixed"
        let earliest = g.members.map(\.start).min() ?? 0
        row.values["start"] = dateFormat.string(from: Date(timeIntervalSince1970: Double(earliest)))
        row.numbers["start"] = Double(earliest)
        row.values["path"] = g.key
        let restricted = g.members.filter { !$0.metricsValid }.count
        if restricted > 0 { row.values["status"] = "\(restricted) restricted" }
        if restricted == g.members.count {
          for key in ["cpu", "memory", "time", "threads", "mempercent"] {
            row.values[key] = "—"
            row.numbers[key] = nil
          }
        }
        if !g.members.contains(where: { $0.ioValid }) {
          row.values["disk"] = "—"
          row.numbers["disk"] = nil
        }
        groups.append(row)
      }
      let categories = ["Apps", "Background processes", "macOS processes"]
      let applicationPaths = Set(
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap
        { $0.bundleURL?.path })
      func category(_ row: DisplayRow) -> Int {
        let members = row.members.isEmpty ? [row.process].compactMap { $0 } : row.members
        if members.contains(where: { applicationPaths.contains($0.appPath) }) { return 0 }
        if members.contains(where: {
          $0.path.hasPrefix("/System/") || $0.path.hasPrefix("/usr/libexec/")
            || $0.path.hasPrefix("/usr/sbin/")
        }) {
          return 2
        }
        return 1
      }
      for categoryIndex in categories.indices {
        let members = groups.filter { category($0) == categoryIndex }
        if members.isEmpty { continue }
        next.append(
          DisplayRow(
            id: "section:\(categoryIndex)",
            values: ["name": "\(categories[categoryIndex]) (\(members.count))"], section: true))
        for row in sortedRows(members) {
          next.append(row)
          if row.group && (expanded.contains(row.id) || !q.isEmpty) {
            next += ProcessLogic.sorted(
              row.members, key: sortKey, ascending: ascending, total: system.raw.ram
            ).map { processRow($0, indent: 24) }
          }
        }
      }
    case .processes, .details:
      next = ProcessLogic.sorted(
        records.filter { $0.matches(q) }, key: sortKey, ascending: ascending, total: system.raw.ram
      ).map { processRow($0) }
    case .history:
      for (key, h) in history.entries
      where q.isEmpty || h.name.localizedCaseInsensitiveContains(q)
        || h.path.localizedCaseInsensitiveContains(q)
      {
        next.append(
          DisplayRow(
            id: key,
            values: [
              "name": h.name, "time": duration(h.cpuSeconds), "memory": bytes(Double(h.peakMemory)),
              "duration": duration(h.observedSeconds), "disk": bytes(h.diskBytes), "path": h.path,
            ],
            numbers: [
              "time": h.cpuSeconds, "memory": Double(h.peakMemory), "duration": h.observedSeconds,
              "disk": h.diskBytes,
            ], iconPath: h.path))
      }
      next = sortedRows(next)
    case .startup, .services:
      for s in services
      where (page == .services || s.path != "—")
        && (q.isEmpty
          || [s.label, s.program, s.path, s.publisher, s.domain].contains {
            $0.localizedCaseInsensitiveContains(q)
          })
      {
        next.append(
          DisplayRow(
            id: s.id,
            values: [
              "name": s.label, "status": s.status, "publisher": s.publisher,
              "mechanism": s.mechanism, "domain": s.domain, "pid": s.pid.map { String($0) } ?? "—",
              "enabled": s.disabled ? "No" : "Yes",
              "managed": s.mutable ? "Current user" : "System / vendor", "path": s.path,
              "program": s.program,
              "modified": s.modified.map { dateFormat.string(from: $0) } ?? "—",
              "impact": "Not measured",
            ],
            numbers: [
              "pid": Double(s.pid ?? 0), "modified": s.modified?.timeIntervalSince1970 ?? 0,
            ], service: s))
      }
      next = sortedRows(next)
    case .users:
      let users = Dictionary(grouping: records, by: { $0.user })
      var parents: [DisplayRow] = []
      for (user, members) in users {
        guard
          q.isEmpty || user.localizedCaseInsensitiveContains(q)
            || members.contains(where: { $0.matches(q) })
        else { continue }
        let cpu = members.reduce(0) { $0 + $1.cpu }
        let mem = members.reduce(UInt64(0)) { $0 + $1.memory }
        let session = sessions[user]?.joined(separator: ", ") ?? "Background owner"
        parents.append(
          DisplayRow(
            id: "user:" + user,
            values: [
              "name": user, "session": session, "count": "\(members.count)",
              "cpu": members.contains(where: { $0.metricsValid })
                ? String(format: "%.1f%%", cpu) : "—",
              "memory": members.contains(where: { $0.metricsValid }) ? bytes(Double(mem)) : "—",
              "status": members.contains(where: { !$0.metricsValid }) ? "Partial data" : "",
            ], numbers: ["count": Double(members.count), "cpu": cpu, "memory": Double(mem)],
            members: members, group: true))
      }
      for row in sortedRows(parents) {
        next.append(row)
        if expanded.contains(row.id) {
          next += ProcessLogic.sorted(
            row.members.filter {
              $0.matches(q) || row.values["name"]!.localizedCaseInsensitiveContains(q)
            }, key: sortKey, ascending: ascending, total: system.raw.ram
          ).map { processRow($0, indent: 24) }
        }
      }
    case .performance: perf.update(system: system, samples: samples, processes: records)
    case .settings: break
    }
    let sameIDs = rows.map(\.id) == next.map(\.id)
    rows = next
    if sameIDs {
      let visible = table.rows(in: scroll.contentView.bounds)
      if visible.location != NSNotFound && visible.length > 0 {
        let range = visible.location..<min(rows.count, visible.location + visible.length)
        table.reloadData(
          forRowIndexes: IndexSet(integersIn: range),
          columnIndexes: IndexSet(integersIn: 0..<columns.count))
      }
    } else {
      table.reloadData()
      table.selectRowIndexes(
        IndexSet(rows.indices.filter { selection.contains(rows[$0].id) }),
        byExtendingSelection: false)
    }
    for tc in table.tableColumns {
      guard let header = tc.headerCell as? MetricHeader else { continue }
      header.summary =
        [.processes, .users].contains(page)
        ? ([
          "cpu": String(format: "%.0f%%", system.cpu),
          "memory": String(format: "%.0f%%", system.memoryPercent),
          "disk": bytes(system.read + system.write) + "/s",
          "network": bytes(system.sent + system.received) + "/s",
        ][tc.identifier.rawValue] ?? "") : ""
    }
    table.headerView?.needsDisplay = true
    let threadCount = records.reduce(0) { $0 + Int($1.threads) }
    footer.stringValue =
      "\(records.count) processes   ·   \(threadCount) threads   ·   CPU \(String(format:"%.1f%%",system.cpu))   ·   Memory \(bytes(Double(system.used))) / \(bytes(Double(system.raw.ram)))   ·   \(rows.count) rows   ·   \(dateFormat.string(from:system.timestamp))"
    if page == .startup {
      footer.stringValue =
        "\(rows.count) launch entries · Login Items & Extensions opens the authoritative macOS list · Only user-owned agents can be toggled"
    }
    if page == .services {
      footer.stringValue =
        "\(rows.count) jobs · Refreshes every 15 s · On demand ≠ disabled · Protected system/vendor jobs are read-only"
    }
    if page == .history {
      footer.stringValue =
        "Observed while sampling · CPU uses core-seconds · Memory is peak single-process RSS · History persists locally"
    }
    if page == .settings {
      footer.stringValue =
        "No administrator privileges required · Unavailable metrics are displayed as —"
    }
    updateActions()
  }
  func sortedRows(_ input: [DisplayRow]) -> [DisplayRow] {
    input.sorted { a, b in
      if let x = a.numbers[sortKey], let y = b.numbers[sortKey], x != y {
        return ascending ? x < y : x > y
      }
      let cmp = (a.values[sortKey] ?? "").localizedStandardCompare(b.values[sortKey] ?? "")
      if cmp != .orderedSame {
        return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
      }
      return a.id < b.id
    }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !rows[row].section }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    rows[row].section ? 40 : ([.details, .services].contains(page) ? 22 : 28)
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    WindowsTableRow()
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard rows.indices.contains(row), let col = tableColumn else { return nil }
    let r = rows[row]
    let key = col.identifier.rawValue
    let cell =
      (table.makeView(withIdentifier: col.identifier, owner: self) as? HeatCell)
      ?? HeatCell(frame: NSRect(x: 0, y: 0, width: col.width, height: 29))
    cell.identifier = col.identifier
    cell.frame.size.width = col.width
    let numeric = columns.first { $0.key == key }?.numeric ?? false
    if r.section {
      cell.configure(text: r.values[key] ?? "")
      cell.title.font = winFont(16)
      cell.title.textColor = .secondaryLabelColor
      cell.heat = 0
      return cell
    }
    cell.title.textColor = .labelColor
    var icon: NSImage?
    if key == "name" && !r.iconPath.isEmpty && r.iconPath != "—" {
      if icons[r.iconPath] == nil {
        if icons.count > 1000 { icons.removeAll() }
        icons[r.iconPath] = NSWorkspace.shared.icon(forFile: r.iconPath)
      }
      icon = icons[r.iconPath]
    }
    if key == "name", icon == nil {
      icon = windowsIcon(page == .users && r.group ? "users" : "app")
    }
    let text =
      key == "memory" && defaults.bool(forKey: "percent.memory") && r.numbers["memory"] != nil
      ? String(format: "%.1f%%", (r.numbers["memory"] ?? 0) / max(1, Double(system.raw.ram)) * 100)
      : (r.values[key] ?? "")
    cell.configure(
      text: text, image: icon,
      indent: key == "name"
        ? (r.indent + (page == .processes && grouped && !r.group && r.indent == 0 ? 18 : 0)) : 0,
      expand: key == "name" && r.group
        ? (expanded.contains(r.id) || (page == .processes && !search.stringValue.isEmpty)) : nil,
      numeric: numeric, bold: false)
    cell.disclosure.target = self
    cell.disclosure.action = #selector(toggleGroup(_:))
    cell.disclosure.tag = row
    cell.toolTip = r.values[key]
    cell.heat = 0
    if [.processes, .details].contains(page), ["cpu", "memory", "disk"].contains(key) {
      let v = r.numbers[key] ?? 0
      cell.heat =
        key == "cpu" ? v / 100 : (key == "memory" ? v / Double(max(1, system.raw.ram)) : v / 1e8)
      if r.numbers[key] != nil { cell.heat = max(0.02, cell.heat) }
    }
    if ["gpu", "network", "energy", "engine"].contains(key) {
      cell.toolTip =
        "macOS does not expose a supported, reliable per-process metric to an ordinary monitoring app."
    }
    return cell
  }
  func tableView(
    _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) {
    if let d = table.sortDescriptors.first {
      sortKey = d.key ?? "name"
      ascending = d.ascending
      updateContent()
    }
  }
  func tableViewSelectionDidChange(_ notification: Notification) { updateActions() }
  var selectedRows: [DisplayRow] {
    table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
  }
  var selectedProcesses: [ProcessRecord] { selectedRows.compactMap(\.process) }
  var selectedActionProcesses: [ProcessRecord] {
    var seen = Set<String>()
    return selectedRows.flatMap { row -> [ProcessRecord] in
      if let process = row.process { return [process] }
      return page == .processes && row.group ? row.members : []
    }.filter { seen.insert($0.id).inserted }
  }
  var validActionSelection: Bool {
    !selectedRows.isEmpty
      && selectedRows.allSatisfy {
        !$0.section
          && ($0.process != nil || (page == .processes && $0.group && !$0.members.isEmpty))
      }
  }
  func updateActions() {
    let processPage = [Page.processes, .details, .users].contains(page)
    endButton.isHidden = !processPage
    inspectButton.isHidden = page != .details
    efficiencyButton.isHidden = page != .processes
    endButton.isEnabled =
      !selectedActionProcesses.isEmpty && validActionSelection
      && selectedActionProcesses.allSatisfy {
        $0.protectedReason(currentUID: Int32(getuid()), ownPID: getpid()) == nil
      }
    inspectButton.isEnabled = selectedProcesses.count == 1
    efficiencyButton.isEnabled = powerMode.supported && !powerMode.busy
    (efficiencyButton as? FlatButton)?.selected = powerMode.enabled
    efficiencyButton.setAccessibilityValue(
      powerMode.enabled ? "Low Power Mode on" : "Low Power Mode off")
    efficiencyButton.toolTip =
      "macOS Low Power Mode: \(powerMode.enabled ? "On":"Off"). Changes the whole Mac's \(powerMode.source.rawValue) profile."
    refreshButton.isHidden = page == .settings
    columnsButton.isHidden = page == .settings
    let expected = page == .history ? 1 : ([.startup, .services].contains(page) ? 2 : 0)
    let existing = actionBar.arrangedSubviews.filter { $0.tag == 900 }
    if existing.count != expected
      || (expected == 1 && (existing.first as? NSButton)?.title != "Reset history")
    {
      existing.forEach {
        actionBar.removeArrangedSubview($0)
        $0.removeFromSuperview()
      }
      if page == .history {
        let b = button("Reset history", "trash", target: self, action: #selector(resetHistory))
        b.tag = 900
        actionBar.addArrangedSubview(b)
      }
      if [.startup, .services].contains(page) {
        let b = button(
          "Login Items & Extensions", "arrow.up.forward.square", target: self,
          action: #selector(openLoginItems))
        b.tag = 900
        actionBar.addArrangedSubview(b)
        let t = button("Enable / Disable", "power", target: self, action: #selector(toggleService))
        t.tag = 900
        actionBar.addArrangedSubview(t)
      }
    }
    if [.startup, .services].contains(page), let t = actionBar.arrangedSubviews.last as? NSButton {
      t.isEnabled = selectedRows.count == 1 && selectedRows.first?.service?.mutable == true
    }
  }
  @objc func toggleGroup(_ sender: NSButton) {
    guard rows.indices.contains(sender.tag) else { return }
    let id = rows[sender.tag].id
    if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    updateContent()
  }
  func expandSelected(_ expand: Bool) {
    guard let row = selectedRows.first, row.group else { return }
    if expand { expanded.insert(row.id) } else { expanded.remove(row.id) }
    updateContent()
  }
  @objc func doubleClick() {
    guard table.clickedRow >= 0, rows.indices.contains(table.clickedRow) else { return }
    if rows[table.clickedRow].group {
      let b = NSButton()
      b.tag = table.clickedRow
      toggleGroup(b)
    } else {
      inspectSelected()
    }
  }
  func contextMenu(_ row: Int) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    guard rows.indices.contains(row), !rows[row].section else { return menu }
    let rowValue = rows[row]
    func add(_ title: String, _ action: Selector?, _ enabled: Bool = true) {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
      item.isEnabled = enabled
    }
    if page == .processes && (rowValue.group || rowValue.process != nil) {
      if rowValue.group {
        add(expanded.contains(rowValue.id) ? "Collapse" : "Expand", #selector(contextExpand))
        menu.items.last?.tag = -99
      }
      add("Switch to", #selector(switchToApplication), applicationForSelection() != nil)
      add("End task", #selector(endTask), endButton.isEnabled)
      let resource = NSMenuItem(title: "Resource values", action: nil, keyEquivalent: "")
      resource.submenu = resourceValuesMenu()
      menu.addItem(resource)
      add("Provide feedback", #selector(provideFeedback))
      menu.addItem(.separator())
      add("Efficiency mode", #selector(toggleEfficiencyMode), efficiencyButton.isEnabled)
      menu.items.last?.state = powerMode.enabled ? .on : .off
      add("Debug", nil, false)
      add("Create dump file", nil, false)
      menu.addItem(.separator())
      add("Go to details", #selector(goToDetails), rowValue.process != nil)
      add(
        "Open file location", #selector(reveal),
        rowValue.process != nil && !rowValue.iconPath.isEmpty)
      add("Search online", #selector(searchOnline))
      add("Properties", #selector(inspectSelected), rowValue.process != nil)
      let extra = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
      let submenu = NSMenu()
      submenu.autoenablesItems = false
      for (name, selector, enabled) in [
        ("Force quit", #selector(forceQuit), endButton.isEnabled),
        ("Copy process details", #selector(copyDetails), true),
        ("Copy PID", #selector(copyPID), rowValue.process != nil),
      ] {
        let item = submenu.addItem(withTitle: name, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
      }
      extra.submenu = submenu
      menu.addItem(extra)
    } else if let p = rowValue.process {
      add("End task", #selector(endTask), endButton.isEnabled)
      add("End process tree", #selector(endProcessTree), endButton.isEnabled)
      let priority = NSMenuItem(title: "Set priority", action: nil, keyEquivalent: "")
      let choices = NSMenu()
      choices.autoenablesItems = false
      for (title, value) in [
        ("Realtime", -20), ("High", -10), ("Above normal", -5), ("Normal", 0), ("Below normal", 5),
        ("Low", 10),
      ] {
        let item = choices.addItem(
          withTitle: title, action: #selector(setPriority(_:)), keyEquivalent: "")
        item.target = self
        item.tag = value
        item.state = p.nice == value ? .on : .off
        item.isEnabled = endButton.isEnabled && value >= p.nice && value >= 0
      }
      priority.submenu = choices
      menu.addItem(priority)
      add("Set affinity", nil, false)
      add("Create dump file", nil, false)
      menu.addItem(.separator())
      add("Open file location", #selector(reveal), !p.path.isEmpty)
      add("Search online", #selector(searchOnline))
      add("Properties", #selector(inspectSelected))
      menu.addItem(.separator())
      add("Force quit", #selector(forceQuit), endButton.isEnabled)
      add("Copy PID", #selector(copyPID))
      add("Copy executable path", #selector(copyPath))
      add("Copy process details", #selector(copyDetails))
    } else if rowValue.group {
      add(expanded.contains(rowValue.id) ? "Collapse" : "Expand", #selector(contextExpand))
      add("Manage user accounts", #selector(openUserAccounts))
      add("Copy details", #selector(copyDetails))
    } else if let service = rowValue.service {
      add(service.disabled ? "Enable" : "Disable", #selector(toggleService), service.mutable)
      add("Open file location", #selector(reveal), service.path != "—")
      add("Search online", #selector(searchOnline))
      add("Copy details", #selector(copyDetails))
      add("Open Services", #selector(openLoginItems))
    } else {
      add("Open app", #selector(openHistoryApplication))
      add("Copy details", #selector(copyDetails))
    }
    return menu
  }
  func resourceValuesMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for key in ["memory", "disk", "network"] {
      let parent = NSMenuItem(title: key.capitalized, action: nil, keyEquivalent: "")
      let choices = NSMenu()
      choices.autoenablesItems = false
      for percent in [true, false] {
        let item = choices.addItem(
          withTitle: percent ? "Percents" : "Values", action: #selector(setResourceUnits(_:)),
          keyEquivalent: "")
        item.target = self
        item.representedObject = key
        item.tag = percent ? 1 : 0
        item.state = defaults.bool(forKey: "percent." + key) == percent ? .on : .off
        item.isEnabled = !percent || key == "memory"
        if !item.isEnabled {
          item.toolTip = "macOS does not expose the required utilization denominator."
        }
      }
      parent.submenu = choices
      menu.addItem(parent)
    }
    return menu
  }
  @objc func setResourceUnits(_ item: NSMenuItem) {
    if let key = item.representedObject as? String {
      defaults.set(item.tag == 1, forKey: "percent." + key)
      updateContent()
    }
  }
  func applicationForSelection() -> NSRunningApplication? {
    let members = selectedRows.flatMap {
      $0.members.isEmpty ? [$0.process].compactMap { $0 } : $0.members
    }
    return NSWorkspace.shared.runningApplications.first { app in
      app.activationPolicy == .regular && members.contains { $0.pid == app.processIdentifier }
    }
  }
  @objc func switchToApplication() {
    if applicationForSelection()?.activate(options: [.activateAllWindows]) == true
      && defaults.bool(forKey: "minimizeOnUse")
    {
      window.miniaturize(nil)
    }
  }
  @objc func provideFeedback() {
    NSWorkspace.shared.open(URL(string: "https://github.com/hotredsam/task-manager-macos/issues")!)
  }
  @objc func openUserAccounts() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")!)
  }
  @objc func openHistoryApplication() {
    guard let path = selectedRows.first?.values["path"], !path.isEmpty else { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
  }
  @objc func searchOnline() {
    guard let name = selectedRows.first?.values["name"] else { return }
    var url = URLComponents(string: "https://www.bing.com/search")!
    url.queryItems = [URLQueryItem(name: "q", value: name)]
    if let url = url.url { NSWorkspace.shared.open(url) }
  }
  @objc func setPriority(_ item: NSMenuItem) {
    guard let p = selectedProcesses.first, let current = validated(p),
      item.tag >= Int(current.nice), item.tag >= 0
    else { return }
    guard
      confirm(
        "Change priority?", "Set scheduling priority for \(p.name) to \(item.title).",
        button: "Change priority"), validated(p) != nil
    else { return }
    if setpriority(PRIO_PROCESS, UInt32(p.pid), Int32(item.tag)) != 0 {
      showError(String(cString: strerror(errno)))
    }
    poll()
  }
  @objc func endProcessTree() {
    guard let process = selectedProcesses.first else { return }
    var ids: Set<Int32> = [process.pid]
    var count = 0
    while count != ids.count {
      count = ids.count
      for record in records where ids.contains(record.ppid) { ids.insert(record.pid) }
    }
    let targets = records.filter { ids.contains($0.pid) }
    terminate(force: false, targets: targets)
  }
  @objc func goToDetails() {
    guard let process = selectedProcesses.first else { return }
    search.stringValue = ""
    showPage(.details)
    if let row = rows.firstIndex(where: { $0.process?.id == process.id }) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      table.scrollRowToVisible(row)
    }
  }
  @objc func contextExpand() {
    if let row = selectedRows.first { expandSelected(!expanded.contains(row.id)) }
  }
  @objc func endTask() { terminate(force: false) }
  @objc func forceQuit() { terminate(force: true) }
  func confirm(_ title: String, _ text: String, button: String) -> Bool {
    WindowsDialog(title: title, message: text, confirm: button).run().0
  }
  func showError(_ message: String) {
    let a = NSAlert()
    a.messageText = "Task Manager"
    a.informativeText = message
    a.alertStyle = .informational
    a.runModal()
  }
  func validated(_ p: ProcessRecord) -> ProcessRecord? {
    var raw = TMProcess()
    guard tm_read_process(p.pid, &raw) == 1 else { return nil }
    let fresh = ProcessRecord(raw)
    guard fresh.id == p.id,
      fresh.protectedReason(currentUID: Int32(getuid()), ownPID: getpid()) == nil
    else { return nil }
    return fresh
  }
  func terminate(force: Bool, targets: [ProcessRecord]? = nil) {
    let processes = targets ?? selectedActionProcesses
    guard !processes.isEmpty, targets != nil || validActionSelection,
      processes.allSatisfy({ validated($0) != nil })
    else {
      showError("The selection contains a protected, unavailable, or changed process.")
      return
    }
    let names = processes.prefix(6).map { "\($0.name) (\($0.pid))" }.joined(separator: ", ")
    let warning =
      force
      ? "Force Quit stops the process immediately. Unsaved work may be lost."
      : "End Task sends SIGTERM, asking the process to stop. Unsaved work may be lost."
    guard
      confirm(
        force ? "Force quit \(processes.count) process(es)?" : "End \(processes.count) task(s)?",
        names + "\n\n" + warning, button: force ? "Force Quit" : "End Task")
    else { return }
    var errors: [String] = []
    for p in processes {
      guard validated(p) != nil else {
        errors.append("\(p.name): process changed or exited")
        continue
      }
      if kill(p.pid, force ? SIGKILL : SIGTERM) != 0 {
        errors.append("\(p.name): \(String(cString:strerror(errno)))")
      }
    }
    if !errors.isEmpty { showError(errors.joined(separator: "\n")) }
    poll()
  }
  @objc func toggleEfficiencyMode() {
    powerMode.toggle(
      confirm: { [weak self] title, message, button in
        self?.confirm(title, message, button: button) ?? false
      }, report: { [weak self] message in self?.showError(message) })
  }
  @objc func lowerPriority() {
    guard let p = selectedProcesses.first, let current = validated(p) else { return }
    let nice = min(19, current.nice + 5)
    guard
      confirm(
        "Lower priority of \(p.name)?",
        "Set nice from \(current.nice) to \(nice). Restoring a higher priority may require administrator privileges.",
        button: "Lower priority")
    else { return }
    guard validated(p) != nil else { return }
    if setpriority(PRIO_PROCESS, UInt32(p.pid), nice) != 0 {
      showError(String(cString: strerror(errno)))
    }
    poll()
  }
  @objc func copyDetails() {
    let text = selectedRows.map { r in
      columns.map { "\($0.title): \(r.values[$0.key] ?? "—")" }.joined(separator: "\n")
    }.joined(separator: "\n\n")
    copy(text)
  }
  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  @objc func copyPID() { copy(selectedProcesses.map { String($0.pid) }.joined(separator: "\n")) }
  @objc func copyPath() { copy(selectedProcesses.map(\.path).joined(separator: "\n")) }
  @objc func reveal() {
    let paths = selectedRows.compactMap { $0.process?.path ?? $0.service?.path }.filter {
      !$0.isEmpty && $0 != "—"
    }
    NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
  }
  @objc func resetHistory() {
    guard
      confirm(
        "Reset application history?",
        "Deletes locally accumulated history. New samples begin immediately.", button: "Reset")
    else { return }
    history.reset()
    saveHistory()
    updateContent()
  }
  @objc func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
  @objc func toggleService() {
    guard let s = selectedRows.first?.service, s.mutable else { return }
    let action = s.disabled ? "enable" : "disable"
    guard
      confirm(
        "\(action.capitalized) \(s.label)?",
        "Changes the launchd override for this user-owned agent. It does not stop a running job or load an unloaded job. The change affects future launches. System/vendor entries are never modified.",
        button: action.capitalized)
    else { return }
    serviceQueue.async {
      let result = LaunchServices.command([action, s.id])
      DispatchQueue.main.async {
        if result.0 != 0 { self.showError(result.1) }
        self.scanServices()
      }
    }
  }
  @objc func inspectSelected() {
    guard let p = selectedProcesses.first else { return }
    showInspector(p)
  }
  @objc func about() {
    showError(
      "Task Manager for macOS\nNative Swift + AppKit · Version 1.0\n\nCPU is normalized across all logical processors. Process memory is resident memory (RSS). — means unavailable, never zero. See README.md in the source project for API mappings and limitations."
    )
  }
}
