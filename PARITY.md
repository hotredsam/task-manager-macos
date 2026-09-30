# Windows 11 parity status

The target is the Windows 11 Task Manager interface and workflow. This is a native macOS implementation with real macOS data. It does not claim certified pixel-for-pixel or feature-complete equivalence.

## Implemented

| Area | Behavior |
|---|---|
| Window | Windows-style top-right minimize, maximize/restore, close; no traffic lights; draggable caption; double-click maximize; title-bar context menu; left/right/quarter snap commands; Option-F4 and Option-Space |
| Shell | Centered rectangular search, compact command bar, 48-point icon rail with expanded navigation, eight main sections, light/dark appearance |
| Processes | Apps/background/macOS process categories, expandable groups, icons, resource cells, ascending/descending sort, column resize/reorder/visibility, live search, retained selections |
| Actions | Run new task, Properties, Go to details, Open file location, individual/group termination with confirmation and protection checks, copy PID/path/details |
| CPU | Overall utilization, logical-processor grid sized dynamically for the Mac, per-core tooltips, kernel-time overlays, persistent graph selection |
| Performance | CPU, Memory, Disk, Network, GPU; context-menu Copy and graph summary view; no extra Battery/Swap/Thermal navigation entries |
| Other sections | Observed app history and reset, launchd startup inventory and eligible toggles, users and their processes, dense Details, launchd Services, settings |
| Font and icon | Original Windows icon PNG bytes; Segoe UI when installed, otherwise Microsoft's SIL-licensed Selawik |

## Adaptations and remaining differences

- The macOS application-menu bar, file pickers, text editing, accessibility, and rasterization do not exactly reproduce WinUI. Snap commands are available through the title-bar menu; the Windows Snap Layout hover flyout is not reproduced.
- macOS process names, ownership, status, memory accounting, launchd labels, and available system details differ from Windows. “macOS processes” replaces “Windows processes.”
- CPU graphs use real Mach processor counters. The CPU details panel reports information exposed on the current Mac; Windows fields without a supported counterpart are not invented.
- Disk and network currently aggregate the published block-storage / physical-interface counters. Separate Windows-style per-disk/per-adapter pages and disk active-time graphs are not implemented.
- GPU engine/utilization, per-process network accounting, Energy Impact, and dynamic CPU clock readings are not exposed by the supported APIs used here. GPU shows real Metal capabilities and explicitly unavailable utilization.
- Efficiency mode deliberately maps to system-wide macOS Low Power Mode, not per-process Windows EcoQoS. It uses explicit confirmation and macOS administrator authorization, preserves the other power-source profile, and restores the previous mode when toggled off. Per-process priority is a separate Details action.
- Windows affinity masks, Windows memory dumps, service start/stop controls, UAC elevation, registry startup entries, and Windows login/session commands are not mapped to unsafe or misleading substitutes.
- Startup management is limited to eligible current-user LaunchAgents; the authoritative modern Login Items & Extensions page opens in System Settings.
- Process termination protects critical/system/other-user processes and revalidates identity. A group with a protected member cannot be terminated through the group action.
- Hardware validation currently covers the documented M5 Pro MacBook Pro. General M-series compatibility is a build target, not a claim that every model was physically tested.

See [README.md](README.md) for API mappings and [VERIFICATION.md](VERIFICATION.md) for test evidence.

## Reference-driven update

The light reference now drives the default appearance, expanded navigation, graph/gray-frame app icon, navigation glyphs, command icons, process menu ordering, custom flyouts and submenus, selectors, checkboxes, and Settings layout. CPU statistics use the Windows live-values/metadata arrangement. Details and Services use compact rows. Startup and Services initially show the reference-style column subset, with extra macOS fields available through Select columns. Windows-only debug, dump, NUMA, and affinity entries remain disabled. The checked-in reference list identifies the precise images used; custom glyph outlines and macOS font rasterization have not been proven pixel-identical.

The follow-up visual pass adds persistent sort-header shading and direction arrows, fixes the Services search field's centered text/editor bounds, redraws the Services puzzle-piece socket and service-row gear icons, and uses a fixed resource palette instead of macOS system colors. Performance thumbnails have simple borders without a dense grid; main graphs use thin traces, light fill, and a square neutral grid. Resource rows use a compact, neutral selection treatment.

Tables, Settings, performance resource lists, and the inspector use space-reserving scrollbars with a pale track and rectangular thumb. AppKit continues to handle wheel/trackpad, dragging, paging, and accessibility.
