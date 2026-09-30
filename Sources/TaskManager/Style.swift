import AppKit
import TaskCore

let accent = NSColor(calibratedRed: 0.20, green: 0.57, blue: 0.78, alpha: 1)
func label(
  _ text: String, _ size: CGFloat = 12, _ weight: NSFont.Weight = .regular,
  _ color: NSColor = .labelColor
) -> NSTextField {
  let l = NSTextField(labelWithString: text)
  l.font = NSFont.systemFont(ofSize: size, weight: weight)
  l.textColor = color
  l.lineBreakMode = .byTruncatingTail
  l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
  return l
}
func button(_ title: String, _ symbol: String? = nil, target: AnyObject?, action: Selector)
  -> NSButton
{
  let b = NSButton(title: title, target: target, action: action)
  b.bezelStyle = .rounded
  b.controlSize = .small
  b.font = NSFont.systemFont(ofSize: 12)
  if let s = symbol {
    b.image = NSImage(systemSymbolName: s, accessibilityDescription: title)
    b.imagePosition = .imageLeading
  }
  return b
}
func stack(
  _ views: [NSView], _ orientation: NSUserInterfaceLayoutOrientation = .horizontal,
  _ spacing: CGFloat = 8
) -> NSStackView {
  let s = NSStackView(views: views)
  s.orientation = orientation
  s.distribution = .fill
  s.spacing = spacing
  s.alignment = orientation == .horizontal ? .centerY : .leading
  return s
}
func pin(_ child: NSView, _ parent: NSView, insets: NSEdgeInsets = NSEdgeInsetsZero) {
  child.translatesAutoresizingMaskIntoConstraints = false
  parent.addSubview(child)
  NSLayoutConstraint.activate([
    child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
    child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
    child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
    child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
  ])
}
func rule() -> NSBox {
  let b = NSBox()
  b.boxType = .separator
  return b
}
func bytes(_ value: Double) -> String {
  let binary = UserDefaults.standard.string(forKey: "units") != "Decimal"
  let base = binary ? 1024.0 : 1000.0
  let names = binary ? ["B", "KiB", "MiB", "GiB", "TiB"] : ["B", "KB", "MB", "GB", "TB"]
  var v = max(0, value)
  var i = 0
  while v >= base && i < 4 {
    v /= base
    i += 1
  }
  return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, names[i])
}
func duration(_ seconds: Double) -> String {
  let s = Int(max(0, seconds))
  return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
}
let dateFormat: DateFormatter = {
  let d = DateFormatter()
  d.dateStyle = .short
  d.timeStyle = .medium
  return d
}()

final class Surface: NSView {
  var fill: NSColor
  init(_ color: NSColor) {
    fill = color
    super.init(frame: .zero)
    wantsLayer = true
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateLayer() { layer?.backgroundColor = fill.cgColor }
}
final class HeatCell: NSTableCellView {
  let title = label("")
  let icon = NSImageView()
  let disclosure = NSButton()
  var heat: Double = 0 { didSet { needsDisplay = true } }
  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(title)
    addSubview(icon)
    addSubview(disclosure)
    title.isSelectable = false
    disclosure.isBordered = false
    disclosure.imagePosition = .imageOnly
    disclosure.setButtonType(.momentaryPushIn)
    icon.imageScaling = .scaleProportionallyDown
  }
  required init?(coder: NSCoder) { fatalError() }
  override func draw(_ dirtyRect: NSRect) {
    if heat > 0 {
      accent.withAlphaComponent(min(0.30, 0.045 + heat * 0.22)).setFill()
      bounds.fill()
    }
    super.draw(dirtyRect)
  }
  func configure(
    text: String, image: NSImage? = nil, indent: CGFloat = 0, expand: Bool? = nil,
    numeric: Bool = false, bold: Bool = false
  ) {
    title.stringValue = text
    title.font =
      numeric
      ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
      : NSFont.systemFont(ofSize: 12, weight: bold ? .medium : .regular)
    title.alignment = numeric ? .right : .left
    icon.image = image
    icon.isHidden = image == nil
    disclosure.isHidden = expand == nil
    if let expanded = expand {
      disclosure.image = NSImage(
        systemSymbolName: expanded ? "chevron.down" : "chevron.right",
        accessibilityDescription: expanded ? "Collapse group" : "Expand group")
    }
    let left: CGFloat = 8 + indent + (expand == nil ? 0 : 18) + (image == nil ? 0 : 23)
    title.frame = NSRect(x: left, y: 5, width: max(0, bounds.width - left - 10), height: 18)
    title.autoresizingMask = [.width]
    icon.frame = NSRect(x: 8 + indent + (expand == nil ? 0 : 18), y: 5, width: 17, height: 17)
    disclosure.frame = NSRect(x: 5 + indent, y: 5, width: 17, height: 18)
  }
}
final class MetricHeader: NSTableHeaderCell {
  var summary = ""
  override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
    // AppKit reuses the final header cell with an empty title to paint the
    // trailing gutter. Do not repeat its metric in that empty region.
    if summary.isEmpty || stringValue.isEmpty {
      super.draw(withFrame: cellFrame, in: controlView)
      return
    }
    NSColor.controlBackgroundColor.setFill()
    cellFrame.fill()
    let p = NSMutableParagraphStyle()
    p.alignment = .right
    let top: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .semibold),
      .foregroundColor: NSColor.labelColor, .paragraphStyle: p,
    ]
    let bottom: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
      .paragraphStyle: p,
    ]
    (summary as NSString).draw(
      in: NSRect(
        x: cellFrame.minX + 5, y: cellFrame.minY + 4, width: cellFrame.width - 18, height: 22),
      withAttributes: top)
    (stringValue as NSString).draw(
      in: NSRect(
        x: cellFrame.minX + 5, y: cellFrame.minY + 27, width: cellFrame.width - 18, height: 17),
      withAttributes: bottom)
    NSColor.separatorColor.setFill()
    NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY, width: 0.5, height: cellFrame.height).fill()
  }
}
final class ProcessTable: NSTableView {
  var contextProvider: ((Int) -> NSMenu?)?
  var deleteAction: (() -> Void)?
  var expandAction: ((Bool) -> Void)?
  override func menu(for event: NSEvent) -> NSMenu? {
    let row = row(at: convert(event.locationInWindow, from: nil))
    if row >= 0 {
      if !selectedRowIndexes.contains(row) {
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
      }
      return contextProvider?(row)
    }
    return nil
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 51 {
      deleteAction?()
      return
    }
    if event.keyCode == 124 {
      expandAction?(true)
      return
    }
    if event.keyCode == 123 {
      expandAction?(false)
      return
    }
    super.keyDown(with: event)
  }
}

final class FlippedClipView: NSClipView { override var isFlipped: Bool { true } }
