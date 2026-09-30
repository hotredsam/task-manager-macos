# Windows 11 parity status — Rust edition

The [reference list](VISUAL_REFERENCES.md) identifies the Windows screenshots used. The goal is close visual and interaction parity with real macOS data. It is not a certification of exact pixel identity.

Implemented: eight pages; collapsible navigation; custom caption controls; title dragging, maximize/restore and left/right snapping; centered search; application groups; resource heat cells; active sort shading/chevrons; resizable and selectable columns; multi-selection; context menus; live CPU/core/kernel graphs; memory composition; disk/network counters; launchd inventory; observed history; guarded process/service actions; power-mode integration; settings; keyboard navigation; accessible commands; rectangular inset scrollbars.

Remaining differences:

- Font rasterization and some glyph outlines differ from WinUI. The app icon's source pixels are preserved, but macOS controls display scaling/compositing.
- Native text editing and authorization, property dialogs, and macOS's application menu differ from Windows. The Windows maximize-hover Snap Layout chooser and drag-to-reorder columns are not reproduced.
- CPU, memory, process, service and user data have macOS meanings. Windows-only metrics/actions show unavailable or disabled states.
- Disk/network views aggregate counters; separate device/adapter graphs and disk active-time percentages are not supplied. GPU utilization is unavailable.
- Efficiency mode maps to whole-Mac Low Power Mode at the user's request. It is distinct from per-process EcoQoS. Priority lowering is a separate Details operation.
- Startup management covers eligible user LaunchAgents, with a link to the authoritative macOS settings page; it cannot enumerate or control every protected background-item mechanism.
- Only the documented M5 Pro Mac was physically tested. The app-side timing target does not guarantee input-to-photon latency on every display or workload.

See [COMPONENT_AUDIT.md](COMPONENT_AUDIT.md) for verification coverage rather than assuming that every state on every Windows release has been tested.
