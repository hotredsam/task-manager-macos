# Verification report

Verified on an Apple Silicon Mac running macOS 26.5.1 with Swift 6.3.3 and Apple Command Line Tools. The package declares macOS 14 as its minimum; older supported versions have not been separately tested.

## Build and launch

- Optimized release build completed successfully with no compiler warnings.
- Built a native `.app` bundle and verified its ad-hoc code signature.
- Installed into Applications and launched successfully; left running on Processes with Normal refresh.
- Pinned the installed application to the Dock, preserving existing pinned applications.
- Verified all seven ICNS representations contain the corresponding original Windows PNG bytes, unchanged.

## Automated checks

- **23 core tests passed:** CPU calculations, native Mach clock-unit conversion, live process sampling, restricted-process identity fallback, memory formulas, delta resets, hierarchy grouping, cycle handling, sorting, filtering, refresh state, protected-process policy, stable process identity, launchd output parsing, and history accumulation.
- **37 AppKit integration checks passed:** all eight screens, all eight performance resources, sidebar collapse/expand, live sampling, search by PID, filtering, ascending/descending sorting, selection, inspector, context menu, protected self-process, app and user expansion, service inventory, units, rolling graph history, pause, and resume.
- UI integration runs inside the real application and exercises its controls and model state; it is not an external XCUITest suite.

## Manual checks

Inspected Processes, Performance, App History, Startup Apps, Users, Details, Services, and Settings in the running application. Verified live metrics and performance graphs, search, column sorting, contextual menus, and responsive navigation.

Used disposable test-worker processes to verify the complete action flow: End Task confirmation and SIGTERM termination; lower-priority confirmation and nice value changing from 0 to 5; Force Quit confirmation and SIGKILL termination. Existing user applications were not terminated. Actual startup-item changes and launch-at-login approval were not exercised against the user's settings.

## Resource-use sample

With more than 1,100 processes and Normal (two-second) refresh, a 60-second observation of the release build averaged **9.40% of one CPU core**, approximately **0.52% of total 18-core capacity**. RSS ranged from **354.4 to 367.0 MiB**, ending at 357.7 MiB after interface inspection. This is a short observational sample, not a long-duration leak test or a guarantee on other Macs. Graph and history storage and the icon cache have explicit bounds.

## Permissions and limits

No administrator privileges, root, Full Disk Access, or SIP changes are required. Protected-process details display unavailable values. Modern third-party login items are managed through the linked System Settings page; eligible current-user LaunchAgents have guarded enable/disable controls.

GPU utilization/engines, per-process network traffic, Energy Impact, dynamic CPU frequency, disk active time, and other unavailable metrics are explicitly identified in the interface. Memory is macOS RSS and VM accounting, not Windows private working set. The [README](README.md) documents the APIs, Windows-to-macOS mappings, calculation formulas, and remaining limitations.

The Windows icon source pixels are preserved exactly. AppKit fonts, window controls, and OS scaling mean the entire rendered interface is not a pixel-for-pixel Windows screenshot. The bundle is locally signed, not Developer ID signed or notarized for public binary distribution.
