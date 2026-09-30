import AppKit
import Security
import ServiceManagement
import SystemBridge
import TaskCore

extension AppController {
  func makeSettings() -> NSView {
    let panel = stack([], .vertical, 0)
    panel.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
    func row(_ title: String, _ detail: String, _ control: NSView) {
      let a = label(title, 13, .medium)
      let b = label(detail, 11, .regular, .secondaryLabelColor)
      b.maximumNumberOfLines = 2
      b.lineBreakMode = .byWordWrapping
      let text = stack([a, b], .vertical, 4)
      let spacer = NSView()
      spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
      let r = stack([text, spacer, control])
      r.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
      panel.addArrangedSubview(r)
      r.widthAnchor.constraint(equalTo: panel.widthAnchor, constant: -56).isActive = true
      panel.addArrangedSubview(rule())
      panel.arrangedSubviews.last!.widthAnchor.constraint(equalTo: r.widthAnchor).isActive = true
    }
    func popup(_ options: [String], _ value: String, _ key: String) -> NSPopUpButton {
      let p = NSPopUpButton()
      p.addItems(withTitles: options)
      p.selectItem(withTitle: value)
      p.identifier = NSUserInterfaceItemIdentifier(key)
      p.target = self
      p.action = #selector(settingPopup(_:))
      p.widthAnchor.constraint(equalToConstant: 180).isActive = true
      return p
    }
    func toggle(_ enabled: Bool, _ key: String) -> NSButton {
      let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(settingToggle(_:)))
      b.state = enabled ? .on : .off
      b.identifier = NSUserInterfaceItemIdentifier(key)
      return b
    }
    row(
      "Real-time update speed", "High: 1 second · Normal: 2 seconds · Low: 4 seconds",
      popup(RefreshSpeed.allCases.map(\.rawValue), speed.rawValue, "speed"))
    row(
      "Default start page", "Choose the section shown when Task Manager launches.",
      popup(
        Page.allCases.map(\.rawValue), defaults.string(forKey: "startPage") ?? "Processes",
        "startPage"))
    row(
      "Always on top", "Keep this window above other applications.",
      toggle(defaults.bool(forKey: "alwaysTop"), "alwaysTop"))
    row(
      "Group application processes",
      "Use bundle identity and parent relationships for expandable groups.",
      toggle(grouped, "grouped"))
    row(
      "Graph history",
      "Bounded rolling history. Increasing duration starts collecting more samples.",
      popup(
        ["60 seconds", "180 seconds", "300 seconds"],
        "\(defaults.integer(forKey:"graphSeconds")==0 ? 60:defaults.integer(forKey:"graphSeconds")) seconds",
        "graphSeconds"))
    row(
      "Units", "Binary: KiB / MiB / GiB · Decimal: KB / MB / GB",
      popup(["Binary", "Decimal"], defaults.string(forKey: "units") ?? "Binary", "units"))
    row(
      "Appearance", "Follow macOS, or use a light or dark interface.",
      popup(["System", "Light", "Dark"], defaults.string(forKey: "theme") ?? "System", "theme"))
    row(
      "Launch at login", "Uses Apple's Service Management. macOS may require approval.",
      toggle(SMAppService.mainApp.status == .enabled, "login"))
    row(
      "Confirm destructive actions",
      "End Task, Force Quit, priority and startup changes always require confirmation.",
      label("Always enabled", 12, .medium, .secondaryLabelColor))
    let help = label(
      "Permissions & unavailable metrics\n\nTask Manager runs as your user, without root or Full Disk Access. Protected process details may be unavailable. Other users' and critical system processes are read-only. Manage modern background items in System Settings → General → Login Items & Extensions.",
      12, .regular, .secondaryLabelColor)
    help.maximumNumberOfLines = 6
    help.lineBreakMode = .byWordWrapping
    panel.addArrangedSubview(help)
    help.widthAnchor.constraint(equalTo: panel.widthAnchor, constant: -56).isActive = true
    panel.setCustomSpacing(20, after: panel.arrangedSubviews[panel.arrangedSubviews.count - 2])
    let scroll = NSScrollView()
    scroll.contentView = FlippedClipView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.documentView = panel
    panel.translatesAutoresizingMaskIntoConstraints = false
    panel.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
    panel.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
    panel.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true
    return scroll
  }
  func syncSettings() {
    func visit(_ view: NSView) {
      if let popup = view as? NSPopUpButton, popup.identifier?.rawValue == "speed" {
        popup.selectItem(withTitle: speed.rawValue)
      }
      for child in view.subviews { visit(child) }
    }
    visit(settingsView)
  }
  @objc func settingPopup(_ sender: NSPopUpButton) {
    guard let key = sender.identifier?.rawValue, let value = sender.titleOfSelectedItem else {
      return
    }
    if key == "graphSeconds" {
      defaults.set(Int(value.split(separator: " ").first ?? "60"), forKey: key)
    } else {
      defaults.set(value, forKey: key)
    }
    if key == "speed" { startTimer() }
    if key == "theme" { applyTheme() }
    updateContent()
  }
  @objc func settingToggle(_ sender: NSButton) {
    guard let key = sender.identifier?.rawValue else { return }
    let enabled = sender.state == .on
    if key == "login" {
      do {
        if enabled {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        if SMAppService.mainApp.status == .requiresApproval {
          showError("Approve Task Manager in System Settings → General → Login Items & Extensions.")
        }
      } catch {
        sender.state = .off
        showError(
          "macOS could not change launch at login: \(error.localizedDescription)\nKeep this app bundle in a stable location and approve it in System Settings."
        )
      }
      return
    }
    defaults.set(enabled, forKey: key)
    if key == "alwaysTop" { window.level = enabled ? .floating : .normal }
    updateContent()
  }
  func applyTheme() {
    let theme = defaults.string(forKey: "theme") ?? "System"
    window.appearance =
      theme == "System" ? nil : NSAppearance(named: theme == "Dark" ? .darkAqua : .aqua)
  }
  func showInspector(_ p: ProcessRecord) {
    inspector?.close()
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    panel.title = "Inspect · \(p.name)"
    panel.minSize = NSSize(width: 560, height: 440)
    panel.isReleasedWhenClosed = false
    inspector = panel
    let icon = NSImageView()
    icon.image = NSWorkspace.shared.icon(forFile: p.appPath.isEmpty ? p.path : p.appPath)
    icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
    let heading = stack([
      icon,
      stack(
        [
          label(p.name, 22, .semibold),
          label(
            "PID \(p.pid) · \(p.user) · snapshot at \(dateFormat.string(from:system.timestamp))",
            11, .regular, .secondaryLabelColor),
        ], .vertical, 4),
    ])
    let body = NSTextView()
    body.isEditable = false
    body.isSelectable = true
    body.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    body.textContainerInset = NSSize(width: 18, height: 18)
    body.backgroundColor = .textBackgroundColor
    body.autoresizingMask = [.width]
    body.isVerticallyResizable = true
    body.isHorizontallyResizable = false
    body.textContainer?.widthTracksTextView = true
    let reason = p.protectedReason(currentUID: Int32(getuid()), ownPID: getpid())
    body.string =
      "\(reason.map{"PROTECTED: \($0)\n\n"} ?? "")Name: \(p.name)\nApplication: \(p.appName)\nPID: \(p.pid)\nParent PID: \(p.ppid)\nOwner: \(p.user) (UID \(p.uid))\nState: \(p.status)\nCPU: \(String(format:"%.2f%%",p.cpu)) of machine capacity\nCPU time: \(duration(Double(p.cpuNS)/1e9))\nResident memory: \(bytes(Double(p.memory)))\nThreads: \(p.threads)\nNice: \(p.nice)\nArchitecture: \(p.architecture)\nStarted: \(dateFormat.string(from:Date(timeIntervalSince1970:Double(p.start))))\n\nExecutable:\n\(p.path.isEmpty ? "Unavailable":p.path)\n\nBundle ID: \(p.bundleID.isEmpty ? "Unavailable":p.bundleID)\n\nReading arguments, signing information and file descriptors…"
    let scroller = NSScrollView()
    scroller.documentView = body
    scroller.hasVerticalScroller = true
    scroller.borderType = .bezelBorder
    let content = stack([heading, scroller], .vertical, 16)
    content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    scroller.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true
    pin(content, panel.contentView!)
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    queue.async {
      var buffer = [CChar](repeating: 0, count: 131072)
      let ok = tm_arguments(p.pid, &buffer, Int32(buffer.count))
      let args =
        ok == 1
        ? String(cString: buffer) : "Unavailable (process access restricted or process exited)"
      let files = tm_open_files(p.pid)
      var code: SecStaticCode?
      var signing = "Unavailable"
      if !p.path.isEmpty,
        SecStaticCodeCreateWithPath(URL(fileURLWithPath: p.path) as CFURL, [], &code)
          == errSecSuccess, let code = code
      {
        var info: CFDictionary?
        if SecCodeCopySigningInformation(
          code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let d = info as? [String: Any]
        {
          signing =
            "Identifier: \(d[kSecCodeInfoIdentifier as String] ?? "—")\nTeam: \(d[kSecCodeInfoTeamIdentifier as String] ?? "Unsigned / Apple / ad hoc")"
        }
      }
      let result =
        "Arguments:\n\(args)\n\nOpen file descriptors: \(files>=0 ? String(files):"Unavailable")\n\nSigning information:\n\(signing)\n\nArguments can contain sensitive values. This inspector is a point-in-time snapshot. Reopen it to refresh."
      DispatchQueue.main.async {
        body.string = body.string.replacingOccurrences(
          of: "Reading arguments, signing information and file descriptors…", with: result)
      }
    }
  }
}
