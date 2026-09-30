# Windows 11 component audit — Rust release

Target: the Windows 11 Task Manager layout with left navigation and a search field. The supplied references span Windows versions. This inventory records the components inspected; it is not a claim that every possible Windows state, accessibility tool, or hardware configuration was tested.

| Component | Implementation and verification | Remaining difference or untested state |
|---|---|---|
| Caption and icon | Original icon representations verified; right-hand minimize/maximize/close; drag, double-click, restore and system menu implemented | Windows maximize-hover Snap Layout chooser is absent; platform animation differs |
| Navigation | All eight pages inspected; expanded/collapsed navigation and Command-1…8 exercised; active/hover states drawn | Glyphs use custom paths; not certified pixel-identical |
| Search | Native editing; live filtering, clear, PID query, empty/no-results states exercised; Services baseline and clipping corrected | Native caret and text selection remain AppKit |
| Processes | Application groups, expansion, selection, heat cells and all four resource sort directions exercised; selected header shading and chevron visible | macOS metrics and process grouping semantics; unavailable network cells show a dash |
| Details | Identity, status, architecture, sortable columns, context menu and properties inspected; optional extended columns | Column drag-to-reorder absent |
| Users | Human user aggregation and expansion; service accounts excluded | Windows disconnect/sign-out behavior unavailable |
| App history | Observed CPU time, reset and persisted history; optional all-process history | No fabricated pre-observation or Windows network/notification history |
| Startup apps | Current-user third-party launchd entries, publisher/status and guarded management | Protected/modern login-item mechanisms require System Settings; not all entries are mutable |
| Services | Puzzle navigation glyph and two-gear row icon; PID, status, domain and available program description; linked process | Real start/stop/restart of existing user services not performed during final QA |
| CPU | Overall/logical processor views, kernel overlay, metadata and live traces inspected; context menu switching and summary exercised | Dynamic frequency and cache fields unavailable; macOS scheduling differs |
| Idle cores | Independent Mach counter probe confirmed idle ticks on CPUs 6–11; bounded load activated all 18 cores | CPU index does not identify performance class |
| Memory | Usage graph, composition bar and VM statistics inspected | Apple unified-memory accounting is not Windows commit/private working set |
| Disk / Network | Live aggregate rates and available device/network information; muted Windows reference colors | Per-device graphs and Windows disk active-time percentage absent |
| GPU | Device capabilities and explicit unavailable state | Utilization/engine graphs not supplied by current implementation |
| Graph menu | Overall/logical, kernel, summary and copy implemented; graph summary fills the view and Escape restores it | NUMA unavailable |
| Scrollbars | Rectangular inset tracks; wheel, thumb dragging and horizontal overflow; Settings retains scroll through refresh | AppKit momentum behavior is not Windows scrolling physics |
| Process menus | Expand, switch, end, units, details, location, search and properties; protected actions disabled | Windows dumps, affinity and EcoQoS unavailable |
| Process actions | Final Rust UI ended a disposable worker after confirmation; PID disappearance verified independently; stale identity test passed | Force-quit and priority UI paths were exercised on the preceding Swift baseline, not repeated against user apps |
| Settings | Default page, speed, pause, theme, grouping, units, graph interval and window options implemented; lower controls remain reachable | Launch-at-login registration and actual service settings were not enabled during QA |
| Dialogs | Run, properties, error/confirmation layout; Return/Escape; modal action guard; asynchronous inspector uses a request generation to reject stale results | Native administrator prompts remain macOS |
| Efficiency | Actual source-scoped Low Power Mode controller, readback and restore; final Rust confirmation/cancel checked | Live high→low→high write was tested on the Swift baseline; not repeated after Rust rewrite |
| Accessibility / keyboard | Native AX command children exposed; page shortcuts, search, Escape, Delete and command activation exercised | Full VoiceOver audit not performed; custom table is not a native Windows accessibility tree |
| Persistence | Settings/history files and window frame restored through multiple relaunches | No multi-day endurance test |
| Concurrency | Sampling, service discovery, inspector and power work off the UI thread; bounded buffers and deferred icon loading | Timings are workload-dependent; see VERIFICATION.md |
| Packaging | Rust release builds; 24 tests pass; installed arm64 bundle, valid ad-hoc signature, original icon, existing Dock pin retained | Only the named M5 Pro Mac physically tested; not notarized |

The app is a working macOS adaptation with documented gaps. Neither this audit nor the promotional edit claims complete Windows equivalence or a universal input-latency guarantee.
