# Rust release verification

Tested locally on a 16-inch MacBook Pro (2026), Mac17,8, Apple M5 Pro (18 CPU cores), 48 GB RAM, macOS 26.5.1. The app targets general arm64 and macOS 14+. Other M-series devices and older macOS versions were not physically tested.

## Build and packaging

- Optimized Rust release built successfully; primary build/test scripts and GitHub Actions now use Rust.
- Native AppKit UI and a small C system bridge. `otool -L` shows no Swift runtime or web renderer in the executable.
- Mach-O arm64, minimum OS 14.0; installed in Applications with a valid ad-hoc code signature.
- The existing Dock pin points to the installed app. Icon verification passed for all nine source representations; seven ICNS chunks preserve the original embedded PNG bytes.
- Not Developer ID signed or notarized.

## Automated and manual coverage

24 Rust tests passed: native ABI layout, live sampling, counter deltas/wrap/reset, idle versus unavailable cores, process grouping/cycles, identity protection, filtering, bounded/observed history, power-profile parsing and validation, service command timeout, column identities, sorting, navigation, scrolling bounds, and disposable process termination.

The running Rust app was inspected across Processes, Performance, App history, Startup apps, Users, Details, Services and Settings. Checks included live data, CPU overall/logical views, graph context menus and summary mode, memory composition, resource selection, both directions of CPU/Memory/Disk/Network sorting, search/clear/no-results, service search alignment, navigation collapse, Settings scrolling through refresh, keyboard routes and dialogs. AX command children were exposed and used during verification; this is not a complete VoiceOver audit.

A disposable `TaskManagerTestWorker` was selected by PID in the final Rust interface, ended using its confirmation dialog, and independently verified absent afterward. Existing user applications were not terminated. Generation-tagged inspector results prevent a previous asynchronous response from populating a later Properties dialog.

The [component audit](COMPONENT_AUDIT.md) records remaining differences and untested mutations. The old Swift suite's 32 core tests and 67 integration checks are historical baseline evidence, not Rust test results.

## Responsiveness

A final sample of **38 interactions** at a 1120×720-point window, Normal refresh, and approximately 1,200 running processes produced:

| App-side action + drawing | Count | Median | 95th percentile | Maximum |
|---|---:|---:|---:|---:|
| All sampled interactions | 38 | 2.71 ms | 5.84 ms | 7.20 ms |
| Page navigation | 17 | 2.09 ms | 7.20 ms | 7.20 ms |
| Resource-column sorting | 8 | 3.30 ms | 5.84 ms | 5.84 ms |
| Dialogs, navigation collapse and resource selection | 13 | 2.52 ms | 4.83 ms | 4.83 ms |

**All 38 sampled actions were below 8 ms.** The first Run dialog measured 4.83 ms after pre-initializing AppKit's field editor; before that change it measured 17.73 ms. Earlier Details navigation reached 12.39 ms before hidden-column and visible-cell formatting optimizations. These earlier outliers motivated the final changes; they are not represented as passing results.

[Raw final observations and context](benchmarks/final-interactions.json) are included. Percentiles use the nearest-rank method. Video encoding and app-view recording had finished before this sample; ordinary background applications remained running.

The timed `paint:` observations include action handling and synchronous drawing submission, but exclude input event delivery, compositor scheduling and physical display scanout. They are not input-to-photon measurements. A finite sample cannot guarantee every click stays below 8 ms on every workload or display. Native window management and administrator authorization also involve the operating system.

Rendering is virtualized to visible rows. Numeric cell formatting is deferred until display, fonts/drawing attributes are cached, and icons are loaded outside the click path. Sampling, service inventory, inspector commands and power changes run off the UI thread. Recording was disabled for interaction measurements.

## Resource use

A 20-second Processes-page observation with Normal refresh and approximately 1,150 processes averaged **3.40% of one CPU core** and **171.6 MiB RSS** on a Rust release candidate. A separately measured Swift baseline averaged **8.69% of one core** and **314.8 MiB RSS**. Background workload and exact execution times differed, so these are exploratory observations, not a controlled speedup claim or a guarantee. The final release adds further deferred numeric formatting; this resource observation predates that last optimization.

## Per-core and power verification

An independent Mach `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` reader reproduced the low CPU 6–11 values while their idle tick counters advanced. During a bounded four-second 18-thread workload, every core reached approximately 99.8–100% busy. Low graphs reflect scheduler activity, not missing cores; no core class is inferred from an index.

The preceding Swift implementation completed an administrator-authorized AC High Power → Low Power → High Power round trip, leaving Battery Automatic unchanged. The Rust controller implements the same source-scoped `pmset` mapping with validation/readback; parsing and restoration logic are tested, and the Rust confirmation/cancel path was checked. The privileged write was not repeated after the rewrite. Final readback remained **AC powermode 2; Battery powermode 0**. No persistent privileged helper, root monitoring, SIP change, or Full Disk Access requirement was introduced.

## Visual and functional limits

The original app icon pixels are verified. Complete pixel identity of the whole application is not certified. Font rasterization, some custom glyphs, native text editing/authorization and OS behavior differ. GPU utilization, per-process networking, Windows affinity/dumps and other unavailable data are not invented. See [PARITY.md](PARITY.md).

The promotional video contains real app-view frames, edited and composited over Apple's default macOS Tahoe wallpaper. Its opening animation and 60-fps composition are presentation, not a latency or frame-rate benchmark.
