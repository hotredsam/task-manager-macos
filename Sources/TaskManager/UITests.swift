import AppKit
import TaskCore

extension AppController {
  func runUITests() {
    var results: [String] = []
    var failed = false
    func check(_ condition: Bool, _ name: String) {
      results.append("\(condition ? "PASS":"FAIL") \(name)")
      if !condition { failed = true }
    }
    let qaArg = CommandLine.arguments.firstIndex(of: "--qa-dir")
    let directory =
      qaArg.flatMap {
        CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil
      } ?? NSTemporaryDirectory() + "TaskManager-QA"
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    if collapsed { toggleSidebar() }
    check(search.isEditable && search.isSelectable, "Windows search remains editable")
    let originalWidth = sidebarWidth.constant
    toggleSidebar()
    check(sidebarWidth.constant == 48, "Sidebar collapses")
    toggleSidebar()
    check(sidebarWidth.constant == originalWidth, "Sidebar expands")
    check(records.count > 10, "Native process list contains live processes")
    check(sampleCount >= 2, "Live sampler delivered multiple updates")
    check(system.raw.ram > 0, "Physical memory populated")
    check(!powerMode.profiles.isEmpty, "Real macOS power profiles loaded")
    check(
      powerMode.enabled == ProcessInfo.processInfo.isLowPowerModeEnabled,
      "Efficiency state follows macOS Low Power Mode")
    check(
      efficiencyButton.action == #selector(toggleEfficiencyMode),
      "Efficiency action changes system power mode rather than process priority")
    search.stringValue = ""
    showPage(.processes)
    check(table.numberOfRows > 0, "Processes table populated")
    for key in ["cpu", "memory", "disk", "network"] {
      for direction in [false, true] {
        table.sortDescriptors = [NSSortDescriptor(key: key, ascending: direction)]
        let active = table.tableColumns.filter {
          ($0.headerCell as? MetricHeader)?.sortAscending != nil
        }
        check(
          active.count == 1 && active.first?.identifier.rawValue == key
            && active.first?.sortDescriptorPrototype?.key == key
            && (active.first?.headerCell as? MetricHeader)?.sortAscending == direction,
          "\(key) header indicates \(direction ? "ascending" : "descending") sort")
      }
    }
    showPage(.services)
    window.contentView?.layoutSubtreeIfNeeded()
    if let cell = search.cell as? WindowsSearchCell {
      let rect = cell.textRect(search.bounds)
      check(
        search.bounds.contains(rect) && abs(rect.midY - search.bounds.midY) < 1,
        "Services search text is inset and vertically centered")
    } else {
      check(false, "Services search uses centered text cell")
    }
    showPage(.processes)

    search.stringValue = String(getpid())
    controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
    check(
      rows.contains { $0.process?.pid == getpid() || $0.members.contains { $0.pid == getpid() } },
      "Process search by PID")
    check(rows.count < 20, "Search filters table")
    search.stringValue = ""
    showPage(.details)
    table.sortDescriptors = [NSSortDescriptor(key: "pid", ascending: true)]
    check(rows.compactMap { $0.process?.pid } == records.map(\.pid).sorted(), "Ascending PID sort")
    table.sortDescriptors = [NSSortDescriptor(key: "pid", ascending: false)]
    check(
      rows.compactMap { $0.process?.pid } == records.map(\.pid).sorted(by: >), "Descending PID sort"
    )
    if let index = rows.firstIndex(where: { $0.process?.pid == getpid() }) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      check(inspectButton.isEnabled, "Selecting a process enables inspector")
      check(!endButton.isEnabled, "Own process is protected from termination")
      let menu = contextMenu(index)
      check(menu.items.contains { $0.title == "Copy PID" }, "Process context menu has copy PID")
      inspectSelected()
      check(inspector?.isVisible == true, "Inspector opens")
      inspector?.close()
    }
    showPage(.processes)
    if let index = rows.firstIndex(where: { $0.group }) {
      let id = rows[index].id
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      check(
        Set(selectedActionProcesses.map(\.id)) == Set(rows[index].members.map(\.id)),
        "Application action includes every group member")
      let expectedEnabled = rows[index].members.allSatisfy {
        $0.protectedReason(currentUID: Int32(getuid()), ownPID: getpid()) == nil
      }
      check(
        endButton.isEnabled == expectedEnabled,
        "Application action enforces every member's protection policy")
      let before = rows.count
      let b = NSButton()
      b.tag = index
      toggleGroup(b)
      check(expanded.contains(id) && rows.count > before, "Application group expands")
      expanded.remove(id)
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      let menu = contextMenu(index)
      check(
        menu.items.prefix(4).map(\.title) == [
          "Expand", "Switch to", "End task", "Resource values",
        ], "Windows process menu ordering")
      WindowsMenu.show(menu, at: NSPoint(x: 80, y: 100), in: table)
      check(WindowsMenu.active?.panel.isVisible == true, "Windows context flyout opens")
      if let flyout = WindowsMenu.active,
        let resource = flyout.rows.first(where: { $0.item.title == "Resource values" })
      {
        flyout.highlight(resource)
        check(flyout.child?.panel.isVisible == true, "Windows submenu opens")
        if let child = flyout.child,
          let memory = child.rows.first(where: { $0.item.title == "Memory" })
        {
          child.highlight(memory)
          check(
            child.child?.rows.count == 2, "Resource units submenu has percent and value actions")
          if let units = child.child, let percent = units.rows.first {
            let old = defaults.bool(forKey: "percent.memory")
            units.activate(percent)
            check(
              defaults.bool(forKey: "percent.memory") && WindowsMenu.active == nil,
              "Menu action applies and dismisses flyout")
            defaults.set(old, forKey: "percent.memory")
          }
        }
      }
      WindowsMenu.active?.dismiss()
    }
    for page in Page.allCases {
      navButtons[page]?.performClick(nil)
      check(self.page == page, "Navigation: \(page.rawValue)")
    }
    showPage(.performance)
    for r in Resource.allCases {
      perf.cards[r]?.performClick(nil)
      check(
        perf.selected == r && perf.heading.stringValue == r.rawValue,
        "Resource switch: \(r.rawValue)")
    }
    perf.selected = .cpu
    let graphChoice = NSMenuItem()
    graphChoice.tag = 1
    perf.changeGraph(graphChoice)
    check(!perf.coreGrid.isHidden && perf.graph.isHidden, "Logical processor graph mode")
    check(perf.coreGrid.graphs.count == Int(system.raw.logical), "One graph per logical processor")
    check(
      perf.coreGrid.graphs.allSatisfy { !$0.points.isEmpty },
      "Per-processor graphs have real samples")
    check(perf.graphMenu().items.first?.submenu?.items.count == 3, "CPU graph context menu")
    let oldKernel = perf.kernelTimes
    if !oldKernel { perf.toggleKernel() }
    check(
      perf.coreGrid.graphs.allSatisfy { !$0.second.isEmpty }, "Per-processor kernel-time series")
    if !oldKernel { perf.toggleKernel() }
    graphChoice.tag = 0
    perf.changeGraph(graphChoice)
    check(!perf.graph.isHidden && perf.coreGrid.isHidden, "Restore overall CPU graph")
    let initialFrame = window.frame
    window.zoom(nil)
    check((window as? WindowsWindow)?.isMaximized == true, "Windows maximize fills usable screen")
    window.zoom(nil)
    check(window.frame == initialFrame, "Windows restore returns previous frame")
    check(
      window.standardWindowButton(.closeButton)?.isHidden == true, "Native traffic lights hidden")
    check(
      caption.close.frame.minX > caption.maximize.frame.minX
        && caption.maximize.frame.minX > caption.minimize.frame.minX, "Windows caption button order"
    )
    check(perf.history.count >= 2, "Performance graph retains live points")
    check(!services.isEmpty, "Service inventory populated")
    showPage(.users)
    if let index = rows.firstIndex(where: { $0.group }) {
      let count = rows.count
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      check(
        selectedActionProcesses.isEmpty && !endButton.isEnabled,
        "User groups cannot be bulk terminated")
      expandSelected(true)
      check(rows.count > count, "User expands into processes")
    }
    showPage(.settings)
    func findPopup(_ view: NSView, _ identifier: String) -> NSPopUpButton? {
      if let p = view as? NSPopUpButton, p.identifier?.rawValue == identifier { return p }
      for child in view.subviews { if let p = findPopup(child, identifier) { return p } }
      return nil
    }
    if let p = findPopup(settingsView, "units") {
      let old = p.titleOfSelectedItem!
      p.selectItem(withTitle: "Decimal")
      settingPopup(p)
      check(bytes(1000) == "1.0 KB", "Units setting updates formatting")
      p.selectItem(withTitle: old)
      settingPopup(p)
    } else {
      check(false, "Units setting exists")
    }
    let savedSpeed = speed
    speed = .paused
    let before = sampleCount
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      check(self.sampleCount == before, "Pause freezes periodic sampling")
      self.speed = .high
      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        check(self.sampleCount > before, "Resume restarts live sampling")
        self.speed = savedSpeed
        self.search.stringValue = ""
        self.showPage(.processes)
        self.expanded = []
        self.updateContent()
        let report = (failed ? "FAILED" : "PASSED") + "\n" + results.joined(separator: "\n") + "\n"
        try? report.write(toFile: directory + "/ui-tests.txt", atomically: true, encoding: .utf8)
        print(report)
        self.window.makeKeyAndOrderFront(nil)
      }
    }
  }
}
