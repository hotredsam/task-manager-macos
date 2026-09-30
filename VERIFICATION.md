# Verification report

Verified on an Apple Silicon Mac running macOS 26.5.1 with Swift 6.3.3 and Apple Command Line Tools. The package declares macOS 14 as its minimum; older supported versions have not been separately tested.

## Build and launch

- Optimized release build completed successfully with no compiler warnings.
- Built a native `.app` bundle and verified its ad-hoc code signature.
- Installed into Applications and launched successfully; left running on Processes with Normal refresh.
- Pinned the installed application to the Dock, preserving existing pinned applications.
- Verified all seven ICNS representations contain the corresponding original Windows PNG bytes, unchanged.

## Automated checks

- **32 core tests passed:** CPU calculations, native Mach clock-unit conversion, live process sampling, restricted-process identity fallback, memory formulas, delta resets, hierarchy grouping, cycle handling, sorting, filtering, refresh state, protected-process policy, stable process identity, launchd output parsing, history accumulation, logical-processor tick deltas, 32-bit counter wrap, native processor count, per-core baseline resets, legacy/unified power-profile parsing, invalid profile rejection, source-scoped writes, and restoration of High Power mode.
- **59 AppKit integration checks passed:** all eight screens, all five performance resources, sidebar collapse/expand, live sampling, search by PID, filtering, ascending/descending sorting, selection, inspector, context menu, protected self-process, app and user expansion, service inventory, units, rolling graph history, pause, resume, editable search, group action membership/protection, per-core graph switching, per-core kernel series, Windows maximize/restore, hidden traffic lights, caption-button order, real power-profile loading, system Low Power state binding, the Efficiency action binding, both CPU sort indicator directions, and the Services search text layout.
- UI integration runs inside the real application and exercises its controls and model state; it is not an external XCUITest suite.

## Manual checks

Inspected Processes, Performance, App History, Startup Apps, Users, Details, Services, and Settings in the running application. Verified live metrics and performance graphs, search, column sorting, contextual menus, and responsive navigation.

Used disposable test-worker processes to verify the complete action flow: End Task confirmation and SIGTERM termination; lower-priority confirmation and nice value changing from 0 to 5; Force Quit confirmation and SIGKILL termination. Existing user applications were not terminated. Actual startup-item changes and launch-at-login approval were not exercised against the user's settings.

Verified both directions of the real Efficiency mode action on the M5 Pro test Mac. After native administrator authorization, the AC profile changed from High Power (`powermode 2`) to Low Power (`powermode 1`), and the button reported Low Power Mode on through ProcessInfo. Turning it off restored High Power (`powermode 2`) after authorization, and the button returned to Off. The battery profile remained Automatic (`powermode 0`) throughout. The Mac was left in its original power configuration.

## Resource-use sample

With more than 1,100 processes and Normal (two-second) refresh, a 60-second observation of the original release build (before the Windows chrome/per-core update) averaged **9.40% of one CPU core**, approximately **0.52% of total 18-core capacity**. RSS ranged from **354.4 to 367.0 MiB**, ending at 357.7 MiB after interface inspection. This is a short observational sample, not a long-duration leak test or a guarantee on other Macs. Graph and history storage and the icon cache have explicit bounds.

## Permissions and limits

Monitoring does not require administrator privileges, root, Full Disk Access, or SIP changes. Explicit Low Power Mode changes use the macOS administrator authorization dialog; no persistent privileged helper is installed. Protected-process details display unavailable values. Modern third-party login items are managed through the linked System Settings page; eligible current-user LaunchAgents have guarded enable/disable controls.

GPU utilization/engines, per-process network traffic, Energy Impact, dynamic CPU frequency, disk active time, and other unavailable metrics are explicitly identified in the interface. Memory is macOS RSS and VM accounting, not Windows private working set. The [README](README.md) documents the APIs, Windows-to-macOS mappings, calculation formulas, and remaining limitations.

The Windows icon source pixels are preserved exactly. The app now draws Windows-style window controls. Font rasterization, the macOS menu bar/file pickers, and underlying OS behavior still differ; see PARITY.md. The current release is not certified pixel-identical to Windows. The bundle is locally signed, not Developer ID signed or notarized for public binary distribution.

## Per-core activity investigation

A standalone reader of `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` reproduced the low readings for CPUs 6–11: 0–0.5% busy over four seconds of the normal workload, with idle tick counters advancing normally. During a bounded four-second, 18-thread CPU workload, each of CPUs 6–11 reached approximately 99.8% busy and every other core reached 99.8–100%. The workers exited after the sample. This confirms the low graphs reflect actual scheduler activity, not missing cores or a stuck graph. CPU index alone is not used to infer a core's performance class. Per-core tooltips report both utilization and idle percentage.
