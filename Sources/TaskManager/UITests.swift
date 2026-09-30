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
    let originalWidth = sidebarWidth.constant
    toggleSidebar()
    check(sidebarWidth.constant == 64, "Sidebar collapses")
    toggleSidebar()
    check(sidebarWidth.constant == originalWidth, "Sidebar expands")
    check(records.count > 10, "Native process list contains live processes")
    check(sampleCount >= 2, "Live sampler delivered multiple updates")
    check(system.raw.ram > 0, "Physical memory populated")
    search.stringValue = ""
    showPage(.processes)
    check(table.numberOfRows > 0, "Processes table populated")
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
      let before = rows.count
      let b = NSButton()
      b.tag = index
      toggleGroup(b)
      check(expanded.contains(id) && rows.count > before, "Application group expands")
      expanded.remove(id)
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
    check(perf.history.count >= 2, "Performance graph retains live points")
    check(!services.isEmpty, "Service inventory populated")
    showPage(.users)
    if let index = rows.firstIndex(where: { $0.group }) {
      let count = rows.count
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
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
