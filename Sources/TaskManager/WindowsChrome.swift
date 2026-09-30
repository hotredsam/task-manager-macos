import AppKit
import CoreText

func winColor(_ light: CGFloat, _ dark: CGFloat) -> NSColor {
  NSColor(name: nil) { appearance in
    let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return NSColor(white: darkMode ? dark : light, alpha: 1)
  }
}
let winBackdrop = NSColor(name: nil) { appearance in
  appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    ? NSColor(white: 0.125, alpha: 1)
    : NSColor(calibratedRed: 0.935, green: 0.957, blue: 0.971, alpha: 1)
}
let winContent = winColor(1, 0.095)
let winCommand = winColor(0.98, 0.145)

func winFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
  let name = weight.rawValue >= NSFont.Weight.medium.rawValue ? "SegoeUI-Semibold" : "SegoeUI"
  return NSFont(name: name, size: size) ?? NSFont(
    name: weight.rawValue >= NSFont.Weight.medium.rawValue ? "Selawik-Semibold" : "Selawik",
    size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

final class WindowsWindow: NSWindow {
  var restoreFrame: NSRect?
  var caption: WindowsTitleBar?
  var isMaximized: Bool {
    guard let visible = screen?.visibleFrame else { return false }
    return abs(frame.minX - visible.minX) < 2 && abs(frame.minY - visible.minY) < 2
      && abs(frame.width - visible.width) < 2 && abs(frame.height - visible.height) < 2
  }
  override func zoom(_ sender: Any?) {
    if isMaximized, let previous = restoreFrame {
      setFrame(previous, display: true)
      restoreFrame = nil
    } else if let visible = screen?.visibleFrame {
      restoreFrame = frame
      setFrame(visible, display: true)
    }
    caption?.maximize.needsDisplay = true
    caption?.maximize.setAccessibilityLabel(isMaximized ? "Restore down" : "Maximize")
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.option) && event.keyCode == 49 {
      if let view = contentView {
        WindowsMenu.show(systemMenu(), at: NSPoint(x: 8, y: view.bounds.height - 40), in: view)
      }
      return true
    }
    if event.modifierFlags.contains(.option) && event.keyCode == 118 {
      performClose(nil)
      return true
    }
    if event.modifierFlags.contains(.option), let controller = NSApp.delegate as? AppController {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "n":
        controller.runNewTask()
        return true
      case "e":
        if controller.endButton.isEnabled { controller.endTask() }
        return true
      case "v":
        if controller.efficiencyButton.isEnabled { controller.toggleEfficiencyMode() }
        return true
      default: break
      }
    }
    if event.modifierFlags.contains(.control) && event.keyCode == 48,
      let controller = NSApp.delegate as? AppController,
      let index = Page.allCases.firstIndex(of: controller.page)
    {
      let step = event.modifierFlags.contains(.shift) ? -1 : 1
      controller.showPage(Page.allCases[(index + step + Page.allCases.count) % Page.allCases.count])
      return true
    }
    if event.modifierFlags.contains(.control) && event.charactersIgnoringModifiers == "f" {
      makeFirstResponder(caption?.search)
      return true
    }
    if event.keyCode == 96 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
    {
      (NSApp.delegate as? AppController)?.refreshNow()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

class FlatButton: NSButton {
  var hovering = false
  var selected = false { didSet { needsDisplay = true } }
  var navigation = false
  private var tracking: NSTrackingArea?
  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false
    setButtonType(.momentaryPushIn)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(tracking!)
  }
  override func mouseEntered(with event: NSEvent) {
    hovering = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hovering = false
    needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    if selected || hovering || isHighlighted {
      winColor(isHighlighted ? 0.84 : 0.89, isHighlighted ? 0.23 : 0.20).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 4, yRadius: 4).fill()
    }
    if selected && navigation {
      accent.setFill()
      NSBezierPath(
        roundedRect: NSRect(x: 0, y: (bounds.height - 16) / 2, width: 3, height: 16), xRadius: 1.5,
        yRadius: 1.5
      ).fill()
    }
    let tint = isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
    let iconSize: CGFloat = 16
    let textSize = (title as NSString).size(withAttributes: [.font: winFont(12)])
    let left: CGFloat =
      navigation ? 14 : max(10, (bounds.width - textSize.width - (image == nil ? 0 : 24)) / 2)
    if let image {
      let icon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        image.draw(in: rect)
        tint.setFill()
        rect.fill(using: .sourceIn)
        return true
      }
      let rect = NSRect(
        x: left, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
      icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35)
    }
    let x = left + (image == nil ? 0 : 26)
    (title as NSString).draw(
      in: NSRect(
        x: x, y: (bounds.height - 17) / 2, width: max(0, bounds.width - x - 8), height: 17),
      withAttributes: [.font: winFont(12), .foregroundColor: tint])
  }
  override var intrinsicContentSize: NSSize {
    NSSize(
      width: max(
        36,
        (title as NSString).size(withAttributes: [.font: winFont(12)]).width
          + (image == nil ? 20 : 46)), height: 32)
  }
}

final class CaptionButton: NSButton {
  enum Kind { case minimize, maximize, close }
  let kind: Kind
  var hover = false
  private var tracking: NSTrackingArea?
  init(_ kind: Kind) {
    self.kind = kind
    super.init(frame: .zero)
    isBordered = false
    title = ""
    setButtonType(.momentaryPushIn)
    setAccessibilityLabel(kind == .minimize ? "Minimize" : kind == .maximize ? "Maximize" : "Close")
    setAccessibilityIdentifier("caption-\(kind)")
    target = self
    action = #selector(activate)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(tracking!)
  }
  override func mouseEntered(with event: NSEvent) {
    hover = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hover = false
    needsDisplay = true
  }
  override func menu(for event: NSEvent) -> NSMenu? { (window as? WindowsWindow)?.systemMenu() }
  override func rightMouseDown(with event: NSEvent) {
    if let menu = menu(for: event) {
      WindowsMenu.show(menu, at: convert(event.locationInWindow, from: nil), in: self)
    }
  }
  @objc func activate() {
    switch kind {
    case .minimize: window?.miniaturize(nil)
    case .maximize: window?.zoom(nil)
    case .close: window?.performClose(nil)
    }
  }
  override func draw(_ dirtyRect: NSRect) {
    if hover || isHighlighted {
      (kind == .close
        ? NSColor(calibratedRed: 0.77, green: 0.17, blue: 0.11, alpha: 1) : winColor(0.86, 0.23))
        .setFill()
      bounds.fill()
    }
    let ink: NSColor = kind == .close && hover ? .white : .labelColor
    ink.setStroke()
    let p = NSBezierPath()
    p.lineWidth = 1
    let x = floor(bounds.midX - 5) + 0.5
    let y = floor(bounds.midY - 5) + 0.5
    switch kind {
    case .minimize:
      p.move(to: NSPoint(x: x, y: floor(bounds.midY) + 0.5))
      p.line(to: NSPoint(x: x + 10, y: floor(bounds.midY) + 0.5))
    case .close:
      p.move(to: NSPoint(x: x, y: y))
      p.line(to: NSPoint(x: x + 10, y: y + 10))
      p.move(to: NSPoint(x: x, y: y + 10))
      p.line(to: NSPoint(x: x + 10, y: y))
    case .maximize:
      if (window as? WindowsWindow)?.isMaximized == true {
        p.appendRect(NSRect(x: x, y: y, width: 8, height: 8))
        p.move(to: NSPoint(x: x + 2, y: y + 8))
        p.line(to: NSPoint(x: x + 2, y: y + 10))
        p.line(to: NSPoint(x: x + 10, y: y + 10))
        p.line(to: NSPoint(x: x + 10, y: y + 2))
        p.line(to: NSPoint(x: x + 8, y: y + 2))
      } else {
        p.appendRect(NSRect(x: x, y: y, width: 10, height: 10))
      }
    }
    p.stroke()
  }
}

final class WindowsTitleBar: NSView {
  let minimize = CaptionButton(.minimize)
  let maximize = CaptionButton(.maximize)
  let close = CaptionButton(.close)
  let search: NSSearchField
  init(search: NSSearchField, controller: AppController) {
    self.search = search
    super.init(frame: .zero)
    let hamburger = FlatButton(frame: .zero)
    hamburger.image = windowsIcon("line.3.horizontal")
    hamburger.target = controller
    hamburger.action = #selector(AppController.toggleSidebar)
    hamburger.setAccessibilityLabel("Toggle navigation")
    let icon = NSImageView()
    icon.image = NSApp.applicationIconImage
    let title = label("Task Manager", 12)
    for view in [hamburger, icon, title, search, minimize, maximize, close] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      hamburger.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
      hamburger.widthAnchor.constraint(equalToConstant: 40),
      hamburger.heightAnchor.constraint(equalToConstant: 40),
      hamburger.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.leadingAnchor.constraint(equalTo: hamburger.trailingAnchor, constant: 8),
      icon.widthAnchor.constraint(equalToConstant: 16),
      icon.heightAnchor.constraint(equalToConstant: 16),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
      title.centerYAnchor.constraint(equalTo: centerYAnchor),
      search.centerXAnchor.constraint(equalTo: centerXAnchor),
      search.centerYAnchor.constraint(equalTo: centerYAnchor),
      search.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.37),
      search.heightAnchor.constraint(equalToConstant: 32),
      search.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 30),
      close.trailingAnchor.constraint(equalTo: trailingAnchor),
      maximize.trailingAnchor.constraint(equalTo: close.leadingAnchor),
      minimize.trailingAnchor.constraint(equalTo: maximize.leadingAnchor),
      search.trailingAnchor.constraint(lessThanOrEqualTo: minimize.leadingAnchor, constant: -20),
    ])
    for b in [minimize, maximize, close] {
      b.topAnchor.constraint(equalTo: topAnchor).isActive = true
      b.widthAnchor.constraint(equalToConstant: 46).isActive = true
      b.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func menu(for event: NSEvent) -> NSMenu? { (window as? WindowsWindow)?.systemMenu() }
  override func rightMouseDown(with event: NSEvent) {
    if let menu = menu(for: event) {
      WindowsMenu.show(menu, at: convert(event.locationInWindow, from: nil), in: self)
    }
  }
  override var mouseDownCanMoveWindow: Bool { true }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
  }
}

final class WindowsSearchCell: NSSearchFieldCell {
  override func searchButtonRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.maxX - 28, y: rect.midY - 9, width: 18, height: 18)
  }
  override func cancelButtonRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.maxX - 52, y: rect.midY - 8, width: 16, height: 16)
  }
  override func searchTextRect(forBounds rect: NSRect) -> NSRect {
    NSRect(x: rect.minX + 10, y: rect.midY - 9, width: max(0, rect.width - 68), height: 19)
  }
}
final class WindowsSearchField: NSSearchField {
  override init(frame: NSRect) {
    super.init(frame: frame)
    cell = WindowsSearchCell(textCell: "")
    isBezeled = false
    drawsBackground = false
    isEditable = true
    isSelectable = true
    isEnabled = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ dirtyRect: NSRect) {
    winColor(1, 0.18).setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4).fill()
    winColor(0.6, 0.5).setFill()
    NSRect(x: 3, y: 0, width: bounds.width - 6, height: 1).fill()
    super.draw(dirtyRect)
  }
}
final class WindowsTableRow: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    winColor(0.9, 0.20).setFill()
    bounds.fill()
  }
}

final class WindowsAuxiliaryTitleBar: NSView {
  init(title: String, allControls: Bool) {
    super.init(frame: .zero)
    let text = label(title, 12)
    text.translatesAutoresizingMaskIntoConstraints = false
    addSubview(text)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
      text.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    let controls =
      allControls
      ? [CaptionButton(.minimize), CaptionButton(.maximize), CaptionButton(.close)]
      : [CaptionButton(.close)]
    let row = stack(controls, .horizontal, 0)
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.trailingAnchor.constraint(equalTo: trailingAnchor),
      row.topAnchor.constraint(equalTo: topAnchor),
      row.heightAnchor.constraint(equalToConstant: 32),
    ])
    controls.forEach {
      $0.widthAnchor.constraint(equalToConstant: 46).isActive = true
      $0.heightAnchor.constraint(equalToConstant: 32).isActive = true
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { window?.zoom(nil) } else { window?.performDrag(with: event) }
  }
}

func decorateWindowsWindow(_ window: NSWindow, title: String, allControls: Bool = true) -> NSView {
  window.styleMask.insert(.fullSizeContentView)
  window.titleVisibility = .hidden
  window.titlebarAppearsTransparent = true
  window.titlebarSeparatorStyle = .none
  window.isReleasedWhenClosed = false
  for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
    window.standardWindowButton(kind)?.isHidden = true
  }
  let root = Surface(winBackdrop)
  let body = Surface(winContent)
  let caption = WindowsAuxiliaryTitleBar(title: title, allControls: allControls)
  window.contentView = root
  for view in [caption, body] {
    view.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(view)
  }
  NSLayoutConstraint.activate([
    caption.leadingAnchor.constraint(equalTo: root.leadingAnchor),
    caption.trailingAnchor.constraint(equalTo: root.trailingAnchor),
    caption.topAnchor.constraint(equalTo: root.topAnchor),
    caption.heightAnchor.constraint(equalToConstant: 40),
    body.topAnchor.constraint(equalTo: caption.bottomAnchor),
    body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
    body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
    body.bottomAnchor.constraint(equalTo: root.bottomAnchor),
  ])
  return body
}

final class WindowsDialog: NSObject, NSWindowDelegate {
  let window = WindowsWindow(
    contentRect: NSRect(x: 0, y: 0, width: 500, height: 250), styleMask: [.titled, .closable],
    backing: .buffered, defer: false)
  var accepted = false
  let field = NSTextField()
  init(title: String, message: String, confirm: String, input: Bool = false) {
    super.init()
    window.title = title
    window.delegate = self
    window.appearance = NSApp.mainWindow?.appearance
    let body = decorateWindowsWindow(window, title: "Task Manager", allControls: false)
    let heading = label(title, 18, .semibold)
    let detail = label(message, 12)
    detail.lineBreakMode = .byWordWrapping
    detail.maximumNumberOfLines = 0
    let detailHeight =
      ceil(
        (message as NSString).boundingRect(
          with: NSSize(width: 448, height: CGFloat.greatestFiniteMagnitude),
          options: [.usesLineFragmentOrigin, .usesFontLeading],
          attributes: [.font: winFont(12)]
        ).height) + 8
    detail.heightAnchor.constraint(equalToConstant: detailHeight).isActive = true
    window.setContentSize(NSSize(width: 500, height: max(250, detailHeight + (input ? 206 : 170))))
    field.font = winFont(12)
    field.placeholderString = "Application name or full path"
    let ok = button(confirm, target: self, action: #selector(accept))
    ok.keyEquivalent = "\r"
    let cancel = button("Cancel", target: self, action: #selector(cancel))
    cancel.keyEquivalent = "\u{1b}"
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let buttons = stack([spacer, ok, cancel], .horizontal, 10)
    if input {
      let browse = button("Browse…", target: self, action: #selector(browse))
      buttons.insertArrangedSubview(browse, at: 1)
    }
    let verticalSpacer = NSView()
    verticalSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
    let views: [NSView] =
      input
      ? [heading, detail, field, verticalSpacer, buttons]
      : [heading, detail, verticalSpacer, buttons]
    let content = stack(views, .vertical, 12)
    pin(content, body, insets: NSEdgeInsets(top: 20, left: 24, bottom: 16, right: 24))
    for view in views { view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
    window.initialFirstResponder = input ? field : cancel
  }
  func run() -> (Bool, String) {
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.runModal(for: window)
    window.orderOut(nil)
    return (accepted, field.stringValue)
  }
  @objc func accept() {
    accepted = true
    NSApp.stopModal()
  }
  @objc func cancel() { NSApp.stopModal() }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    cancel()
    return false
  }
  @objc func browse() {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.beginSheetModal(for: window) { response in
      if response == .OK { self.field.stringValue = panel.url?.path ?? "" }
    }
  }
}

func registerWindowsFonts() {
  for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [] {
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }
  // Use the user's existing licensed Office fonts in place; never copy or redistribute them.
  for bundle in ["com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint"] {
    guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle),
      let files = FileManager.default.enumerator(
        at: app.appendingPathComponent("Contents/Resources/sdx"), includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles])
    else { continue }
    var loaded = Set<String>()
    for case let url as URL in files {
      let filename = url.lastPathComponent.lowercased()
      for face in ["regular", "semibold"]
      where filename.hasPrefix("segoeui-" + face + "_") && url.pathExtension == "woff"
        && !loaded.contains(face)
      {
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { loaded.insert(face) }
      }
      if loaded.count == 2 { return }
    }
  }
}

extension WindowsWindow {
  @objc func restoreWindow() {
    if isMiniaturized { deminiaturize(nil) }
    if let saved = restoreFrame {
      setFrame(saved, display: true)
      restoreFrame = nil
    }
  }
  @objc func snapWindow(_ item: NSMenuItem) {
    guard let visible = screen?.visibleFrame else { return }
    if restoreFrame == nil { restoreFrame = frame }
    var target = visible
    target.size.width /= 2
    if item.tag % 2 == 1 { target.origin.x += target.width }
    if item.tag >= 2 {
      target.size.height /= 2
      if item.tag < 4 { target.origin.y += target.height }
    }
    setFrame(target, display: true)
  }
  func systemMenu() -> NSMenu {
    let menu = NSMenu()
    for (title, action) in [
      ("Restore", #selector(restoreWindow)), ("Minimize", #selector(NSWindow.miniaturize(_:))),
      ("Maximize", #selector(NSWindow.zoom(_:))),
    ] {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
      item.target = self
    }
    let snap = NSMenuItem(title: "Snap layout", action: nil, keyEquivalent: "")
    let layouts = NSMenu()
    for (i, title) in [
      "Left half", "Right half", "Top left", "Top right", "Bottom left", "Bottom right",
    ].enumerated() {
      let item = layouts.addItem(
        withTitle: title, action: #selector(snapWindow(_:)), keyEquivalent: "")
      item.tag = i
      item.target = self
    }
    snap.submenu = layouts
    menu.addItem(snap)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: ""
    ).target = self
    return menu
  }
}

final class WindowsCheckbox: NSButton {
  override init(frame: NSRect) {
    super.init(frame: frame)
    setButtonType(.switch)
    isBordered = false
  }
  convenience init(title: String, target: AnyObject?, action: Selector) {
    self.init(frame: .zero)
    self.title = title
    self.target = target
    self.action = action
  }
  required init?(coder: NSCoder) { fatalError() }
  override var intrinsicContentSize: NSSize {
    NSSize(
      width: (title as NSString).size(withAttributes: [.font: winFont(12)]).width + 30, height: 22)
  }
  override func draw(_ dirtyRect: NSRect) {
    let rect = NSRect(x: 0.5, y: (bounds.height - 18) / 2, width: 18, height: 18)
    let p = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
    if state == .on {
      accent.setFill()
      p.fill()
    } else {
      winColor(0.98, 0.12).setFill()
      p.fill()
      winColor(0.55, 0.65).setStroke()
      p.lineWidth = 1
      p.stroke()
    }
    if state == .on {
      NSColor.white.setStroke()
      let tick = NSBezierPath()
      tick.lineWidth = 1.5
      tick.move(to: NSPoint(x: 4, y: bounds.midY))
      tick.line(to: NSPoint(x: 8, y: bounds.midY + 4))
      tick.line(to: NSPoint(x: 15, y: bounds.midY - 4))
      tick.stroke()
    }
    (title as NSString).draw(
      in: NSRect(x: 27, y: (bounds.height - 18) / 2, width: bounds.width - 27, height: 18),
      withAttributes: [.font: winFont(12), .foregroundColor: NSColor.labelColor])
  }
}
