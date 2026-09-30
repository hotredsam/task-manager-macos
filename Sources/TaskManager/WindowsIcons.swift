import AppKit

/// Small, unfilled Windows-style glyphs, drawn on a 24-unit grid.
/// Geometry is kept in source so every display scale uses the same outlines.
func windowsIcon(_ name: String) -> NSImage {
  let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
    let transform = NSAffineTransform()
    transform.translateX(by: 0, yBy: 24)
    transform.scaleX(by: 1, yBy: -1)
    transform.concat()
    NSColor.labelColor.setStroke()
    NSColor.labelColor.setFill()
    func path(_ points: [(CGFloat, CGFloat)], close: Bool = false) {
      guard let first = points.first else { return }
      let p = NSBezierPath()
      p.lineWidth = 1.5
      p.lineCapStyle = .round
      p.lineJoinStyle = .round
      p.move(to: NSPoint(x: first.0, y: first.1))
      for v in points.dropFirst() { p.line(to: NSPoint(x: v.0, y: v.1)) }
      if close { p.close() }
      p.stroke()
    }
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat = 1.5) {
      let p = NSBezierPath(
        roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius)
      p.lineWidth = 1.5
      p.stroke()
    }
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
      let p = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
      p.lineWidth = 1.5
      p.stroke()
    }
    switch name {
    case "processes", "square.stack.3d.up":
      box(3, 3, 18, 9)
      box(3, 3, 8, 18)
      path([(11, 3), (11, 12)])
    case "performance", "waveform.path.ecg":
      box(2.5, 2.5, 19, 19, 3)
      path([(5, 13), (8, 13), (10, 7), (13, 17), (15, 11), (19, 11)])
    case "history", "clock.arrow.circlepath":
      let p = NSBezierPath()
      p.lineWidth = 1.5
      p.appendArc(
        withCenter: NSPoint(x: 12, y: 12), radius: 10, startAngle: 220, endAngle: 185,
        clockwise: false)
      p.stroke()
      path([(2, 3), (2, 8), (7, 8)])
      path([(12, 6), (12, 12), (17, 12)])
    case "startup", "power":
      let p = NSBezierPath()
      p.lineWidth = 1.5
      p.appendArc(withCenter: NSPoint(x: 12, y: 15), radius: 10, startAngle: 180, endAngle: 360)
      p.stroke()
      path([(3, 14), (6, 14)])
      path([(5, 7), (7, 9)])
      path([(12, 5), (12, 8)])
      path([(19, 7), (17, 9)])
      path([(18, 15), (22, 15)])
      path([(10, 17), (16, 6), (14, 19), (10, 17)], close: true)
    case "users", "person.2", "person.crop.circle":
      circle(8, 7, 4)
      circle(18, 8, 3)
      let p = NSBezierPath()
      p.lineWidth = 1.5
      p.move(to: NSPoint(x: 2, y: 14))
      p.line(to: NSPoint(x: 14, y: 14))
      p.curve(
        to: NSPoint(x: 8, y: 22), controlPoint1: NSPoint(x: 17, y: 22),
        controlPoint2: NSPoint(x: 11, y: 22))
      p.curve(
        to: NSPoint(x: 2, y: 14), controlPoint1: NSPoint(x: 2, y: 22),
        controlPoint2: NSPoint(x: 1, y: 17))
      p.stroke()
      path([(17, 14), (22, 14), (22, 17), (20, 20), (17, 20)])
    case "details", "list.bullet.rectangle":
      for y: CGFloat in [5, 12, 19] {
        circle(2.5, y, 0.7)
        path([(7, y), (22, y)])
      }
    case "services", "gearshape.2":
      let p = NSBezierPath()
      p.lineWidth = 1.5
      p.lineJoinStyle = .round
      p.move(to: NSPoint(x: 8.5, y: 5))
      p.line(to: NSPoint(x: 8.5, y: 3.5))
      p.curve(
        to: NSPoint(x: 15.5, y: 3.5), controlPoint1: NSPoint(x: 8.5, y: 0.2),
        controlPoint2: NSPoint(x: 15.5, y: 0.2))
      p.line(to: NSPoint(x: 15.5, y: 5))
      p.line(to: NSPoint(x: 19, y: 5))
      p.line(to: NSPoint(x: 19, y: 9))
      p.curve(
        to: NSPoint(x: 19, y: 15), controlPoint1: NSPoint(x: 13, y: 8),
        controlPoint2: NSPoint(x: 13, y: 16))
      p.line(to: NSPoint(x: 19, y: 19))
      p.line(to: NSPoint(x: 15.5, y: 19))
      p.line(to: NSPoint(x: 15.5, y: 20.5))
      p.curve(
        to: NSPoint(x: 8.5, y: 20.5), controlPoint1: NSPoint(x: 15.5, y: 23.8),
        controlPoint2: NSPoint(x: 8.5, y: 23.8))
      p.line(to: NSPoint(x: 8.5, y: 19))
      p.line(to: NSPoint(x: 5, y: 19))
      p.line(to: NSPoint(x: 5, y: 15))
      p.line(to: NSPoint(x: 3.5, y: 15))
      p.curve(
        to: NSPoint(x: 3.5, y: 9), controlPoint1: NSPoint(x: 0.2, y: 15),
        controlPoint2: NSPoint(x: 0.2, y: 9))
      p.line(to: NSPoint(x: 5, y: 9))
      p.line(to: NSPoint(x: 5, y: 5))
      p.close()
      p.stroke()
    case "settings", "gearshape":
      var pts: [(CGFloat, CGFloat)] = []
      for i in 0..<32 {
        let a = CGFloat(i) * CGFloat.pi / 16
        let r: CGFloat = [0, 3].contains(i % 4) ? 8 : 11
        pts.append((12 + cos(a) * r, 12 + sin(a) * r))
      }
      path(pts, close: true)
      circle(12, 12, 4)
    case "line.3.horizontal": for y: CGFloat in [5, 12, 19] { path([(2, y), (22, y)]) }
    case "xmark.circle":
      circle(12, 12, 10)
      path([(5, 19), (19, 5)])
    case "plus.square":
      box(2, 2, 17, 17)
      path([(9, 2), (9, 10), (2, 10)])
      NSBezierPath(ovalIn: NSRect(x: 11, y: 11, width: 13, height: 13)).fill()
      NSColor.windowBackgroundColor.setStroke()
      path([(17.5, 14), (17.5, 21)])
      path([(14, 17.5), (21, 17.5)])
    case "leaf":
      let p = NSBezierPath()
      p.lineWidth = 1.5
      p.move(to: NSPoint(x: 12, y: 20))
      p.curve(
        to: NSPoint(x: 22, y: 4), controlPoint1: NSPoint(x: 24, y: 22),
        controlPoint2: NSPoint(x: 23, y: 10))
      p.curve(
        to: NSPoint(x: 12, y: 20), controlPoint1: NSPoint(x: 8, y: 1),
        controlPoint2: NSPoint(x: 8, y: 12))
      p.stroke()
      path([(12, 20), (18, 10)])
      path([(9, 16), (5, 14), (2, 9), (2, 2), (9, 2), (13, 5)])
    case "chevron.right": path([(9, 5), (16, 12), (9, 19)])
    case "chevron.down": path([(5, 9), (12, 16), (19, 9)])
    case "magnifyingglass":
      circle(10, 10, 7)
      path([(15, 15), (22, 22)])
    case "arrow.up.right.square":
      box(2, 7, 15, 15)
      path([(9, 2), (22, 2), (22, 15)])
      path([(9, 15), (22, 2)])
    case "checkmark": path([(3, 12), (9, 18), (21, 5)])
    case "pause":
      box(6, 3, 3, 18, 0)
      box(15, 3, 3, 18, 0)
    case "info.circle":
      circle(12, 12, 10)
      circle(12, 6, 0.5)
      path([(12, 10), (12, 18)])
    case "arrow.clockwise":
      let p = NSBezierPath()
      p.lineWidth = 1.5
      p.appendArc(
        withCenter: NSPoint(x: 12, y: 12), radius: 9, startAngle: 45, endAngle: 355,
        clockwise: false)
      p.stroke()
      path([(21, 3), (21, 10), (14, 10)])
    default:
      box(3, 3, 18, 18)
      path([(3, 8), (21, 8)])
    }
    return true
  }
  image.isTemplate = true
  return image
}
