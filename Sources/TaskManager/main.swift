import AppKit

let app = NSApplication.shared
registerWindowsFonts()
let delegate = AppController()
app.delegate = delegate
app.run()
