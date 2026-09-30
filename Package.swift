// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TaskManager", platforms: [.macOS(.v14)], products: [.executable(name: "TaskManager", targets: ["TaskManager"])], targets: [
.target(name: "SystemBridge", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
.target(name: "TaskCore", dependencies: ["SystemBridge"]),
.executableTarget(name: "TaskManager", dependencies: ["TaskCore"], linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Metal"), .linkedFramework("ServiceManagement"), .linkedFramework("Security")]),
.testTarget(name: "TaskCoreTests", dependencies: ["TaskCore"])
])
