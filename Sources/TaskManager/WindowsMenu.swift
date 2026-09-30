import AppKit

/// Draws the Windows flyout while keeping NSMenu as the action/validation model.
final class WindowsMenu {
  static var active: WindowsMenu?
  let model: NSMenu
  let panel: NSPanel
  let surface: MenuSurface
  weak var parent: WindowsMenu?
  var child: WindowsMenu?
  var monitor: Any?
  var selected = -1
  var rows: [MenuRow] = []
  var closeObserver: NSObjectProtocol?

  init(_ menu: NSMenu, parent: WindowsMenu? = nil) {
    model = menu
    self.parent = parent
    surface = MenuSurface(frame: NSRect(x:0,y:0,width:202,height:40))
    panel = WindowsMenuPanel(
      contentRect: NSRect(x:0,y:0,width:202,height:40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .popUpMenu
    panel.contentView = surface
    panel.title = "Context menu"
  }
  static func show(_ menu: NSMenu, at point: NSPoint, in view: NSView) {
    active?.dismiss()
    let flyout = WindowsMenu(menu)
    active = flyout
    flyout.panel.appearance = view.effectiveAppearance
    let screenPoint = view.window?.convertPoint(toScreen: view.convert(point, to: nil)) ?? point
    flyout.open(at: screenPoint)
    flyout.monitor = NSEvent.addLocalMonitorForEvents(matching: [
      .leftMouseDown, .rightMouseDown, .keyDown,
    ]) { [weak flyout] event in
      guard let flyout else { return event }
      if event.type == .keyDown {
        flyout.deepest.handleKey(event)
        return nil
      }
      if !flyout.contains(event.window) { flyout.dismiss() }
      return event
    }
    flyout.closeObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
    ) { [weak flyout] _ in flyout?.dismiss() }
  }
  var deepest: WindowsMenu { child?.deepest ?? self }
  func contains(_ window: NSWindow?) -> Bool { panel === window || child?.contains(window) == true }
  func open(at point: NSPoint) {
    let items = model.items.filter { !$0.isHidden }
    let width = max(
      202,
      min(
        330,
        items.map { ($0.title as NSString).size(withAttributes: [.font: winFont(12)]).width + 66 }
          .max() ?? 202))
    let height = items.reduce(CGFloat(8)) { $0 + ($1.isSeparatorItem ? 10 : 32) }
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
    var origin = NSPoint(x: point.x, y: point.y - height)
    if origin.x + width > screen.visibleFrame.maxX {
      origin.x =
        parent == nil
        ? screen.visibleFrame.maxX - width - 4
        : point.x - width - (parent?.panel.frame.width ?? 0) + 4
    }
    origin.x = max(screen.visibleFrame.minX + 4, origin.x)
    origin.y = max(
      screen.visibleFrame.minY + 4, min(origin.y, screen.visibleFrame.maxY - height - 4))
    panel.setFrame(
      NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
    var y: CGFloat = 4
    for item in items {
      let row = MenuRow(item, owner: self)
      row.frame = NSRect(x: 4, y: y, width: width - 8, height: item.isSeparatorItem ? 10 : 32)
      surface.addSubview(row)
      rows.append(row)
      y += row.frame.height
    }
    panel.makeKeyAndOrderFront(nil)
  }
  func highlight(_ row: MenuRow) {
    guard let index = rows.firstIndex(where: { $0 === row }), selected != index else { return }
    selected = index
    rows.forEach { $0.highlighted = $0 === row && row.item.isEnabled }
    child?.dismiss()
    child = nil
    if let menu = row.item.submenu, row.item.isEnabled {
      let flyout = WindowsMenu(menu, parent: self)
      child = flyout
      flyout.panel.appearance = panel.appearance
      let point = panel.convertPoint(
        toScreen: surface.convert(NSPoint(x: row.frame.maxX + 2, y: row.frame.minY - 4), to: nil))
      flyout.open(at: point)
    }
  }
  func activate(_ row: MenuRow) {
    guard row.item.isEnabled, !row.item.isSeparatorItem else { return }
    if row.item.submenu != nil {
      highlight(row)
      return
    }
    let item = row.item
    WindowsMenu.active?.dismiss()
    if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
  }
  func handleKey(_ event: NSEvent) {
    switch event.keyCode {
    case 53: WindowsMenu.active?.dismiss()
    case 123:
      if parent != nil {
        parent?.child = nil
        dismiss()
      }
    case 124: if rows.indices.contains(selected) { highlight(rows[selected]) }
    case 36, 49: if rows.indices.contains(selected) { activate(rows[selected]) }
    case 125, 126:
      let step = event.keyCode == 125 ? 1 : -1
      var i = selected
      for _ in rows.indices {
        i = (i + step + rows.count) % rows.count
        if rows[i].item.isEnabled && !rows[i].item.isSeparatorItem {
          highlight(rows[i])
          break
        }
      }
    default:
      if let text = event.charactersIgnoringModifiers?.lowercased(),
        let row = rows.first(where: {
          $0.item.isEnabled && $0.item.title.lowercased().hasPrefix(text)
        })
      {
        highlight(row)
      }
    }
  }
  func dismiss() {
    child?.dismiss()
    child = nil
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
    if let closeObserver {
      NotificationCenter.default.removeObserver(closeObserver)
      self.closeObserver = nil
    }
    panel.orderOut(nil)
    if WindowsMenu.active === self { WindowsMenu.active = nil }
  }
}
final class MenuSurface: NSView {
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    winColor(0.975, 0.17).setFill()
    let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
    p.fill()
    winColor(0.86, 0.27).setStroke()
    p.lineWidth = 1
    p.stroke()
  }
}
final class MenuRow: NSView {
  let item: NSMenuItem
  weak var owner: WindowsMenu?
  var highlighted = false { didSet { needsDisplay = true } }
  var tracking: NSTrackingArea?
  init(_ item: NSMenuItem, owner: WindowsMenu) {
    self.item = item
    self.owner = owner
    super.init(frame: .zero)
    setAccessibilityElement(!item.isSeparatorItem)
    setAccessibilityRole(.menuItem)
    setAccessibilityLabel(item.title)
    setAccessibilityEnabled(item.isEnabled)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isFlipped: Bool { true }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(tracking!)
  }
  override func mouseEntered(with event: NSEvent) { owner?.highlight(self) }
  override func mouseUp(with event: NSEvent) { owner?.activate(self) }
  override func accessibilityPerformPress() -> Bool {
    owner?.activate(self)
    return item.isEnabled
  }
  override func draw(_ dirtyRect: NSRect) {
    if item.isSeparatorItem {
      winColor(0.88, 0.25).setFill()
      NSRect(x: 0, y: 4, width: bounds.width, height: 0.5).fill()
      return
    }
    if highlighted {
      winColor(0.935, 0.23).setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
    }
    let color = winColor(item.isEnabled ? 0.06 : 0.62, item.isEnabled ? 0.96 : 0.48)
    (item.title as NSString).draw(
      in: NSRect(x: 32, y: 7, width: bounds.width - 50, height: 20),
      withAttributes: [
        .font: winFont(12, item.tag == -99 ? .semibold : .regular), .foregroundColor: color,
      ])
    color.setStroke()
    let p = NSBezierPath()
    p.lineWidth = 1
    if item.submenu != nil {
      p.move(to: NSPoint(x: bounds.width - 14, y: 12))
      p.line(to: NSPoint(x: bounds.width - 10, y: 16))
      p.line(to: NSPoint(x: bounds.width - 14, y: 20))
    }
    if item.state != .off {
      p.move(to: NSPoint(x: 10, y: 16))
      p.line(to: NSPoint(x: 13, y: 19))
      p.line(to: NSPoint(x: 19, y: 12))
    }
    p.stroke()
  }
}

final class WindowsPopupButton: NSPopUpButton {
  override func draw(_ dirtyRect: NSRect) {
    let text = pullsDown ? (itemTitle(at: 0)) : (titleOfSelectedItem ?? "")
    if !pullsDown {
      winColor(0.99, 0.20).setFill()
      let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
      p.fill()
      winColor(0.83, 0.32).setStroke()
      p.lineWidth = 0.5
      p.stroke()
    }
    (text as NSString).draw(
      in: NSRect(x: 10, y: (bounds.height - 18) / 2, width: bounds.width - 30, height: 18),
      withAttributes: [.font: winFont(12), .foregroundColor: NSColor.labelColor])
    let p = NSBezierPath()
    p.lineWidth = 0.8
    p.move(to: NSPoint(x: bounds.width - 18, y: bounds.midY - 2))
    p.line(to: NSPoint(x: bounds.width - 14, y: bounds.midY + 2))
    p.line(to: NSPoint(x: bounds.width - 10, y: bounds.midY - 2))
    NSColor.labelColor.setStroke()
    p.stroke()
  }
  override func mouseDown(with event: NSEvent) {
    guard let menu else { return }
    let copy = NSMenu()
    copy.autoenablesItems = false
    for (index, item) in menu.items.enumerated() where !pullsDown || index > 0 {
      let row = item.copy() as! NSMenuItem
      if !pullsDown {
        row.tag = index
        row.target = self
        row.action = #selector(selectWindowsItem(_:))
        row.state = index == indexOfSelectedItem ? .on : .off
      }
      copy.addItem(row)
    }
    WindowsMenu.show(copy, at: NSPoint(x: 0, y: 0), in: self)
  }
  @objc func selectWindowsItem(_ item: NSMenuItem) {
    selectItem(at: item.tag)
    needsDisplay = true
    if let action { NSApp.sendAction(action, to: target, from: self) }
  }
}

final class WindowsMenuPanel: NSPanel { override var canBecomeKey: Bool { true } }
