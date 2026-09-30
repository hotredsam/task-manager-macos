import AppKit

/// Windows-style, space-reserving scrollbars with AppKit's native tracking and accessibility.
final class WindowsScroller: NSScroller {
  override class var isCompatibleWithOverlayScrollers: Bool { false }
  override func draw(_ dirtyRect: NSRect) {
    drawKnobSlot(in: bounds, highlight: false)
    if isEnabled && knobProportion < 1 { drawKnob() }
  }
  override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
    winColor(0.965, 0.14).setFill()
    slotRect.fill()
  }
  override func drawKnob() {
    let knob = rect(for: .knob)
    guard knob.width > 0, knob.height > 0 else { return }
    let vertical = bounds.height >= bounds.width
    let thumb = knob.insetBy(dx: vertical ? 3 : 1, dy: vertical ? 1 : 3)
    guard thumb.width > 0, thumb.height > 0 else { return }
    winColor(0.54, 0.58).setFill()
    thumb.fill()
  }
}

final class WindowsScrollView: NSScrollView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    scrollerStyle = .legacy
    verticalScroller = WindowsScroller(frame: NSRect(x: 0, y: 0, width: 15, height: 100))
    horizontalScroller = WindowsScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 15))
    hasVerticalScroller = false
    hasHorizontalScroller = false
    autohidesScrollers = true
  }
  required init?(coder: NSCoder) { fatalError() }
}
