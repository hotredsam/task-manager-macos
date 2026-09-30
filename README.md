# Task Manager for macOS

**The Windows Task Manager workflow, rebuilt as a native Apple Silicon app.**

An Ultrafast build experiment by [hotredsam](https://github.com/hotredsam): Swift, AppKit, real process data, and a small C bridge to macOS. The project aims for Windows 11 visual and interaction parity, including its window controls and CPU graph menus. The inspected screenshots are linked in [VISUAL_REFERENCES.md](VISUAL_REFERENCES.md); remaining differences are documented in [PARITY.md](PARITY.md).

- Windows-style caption bar: minimize, maximize/restore, and close on the right; draggable title bar and double-click maximize.
- Compact command bar, centered search, collapsible navigation, process categories, sortable tables, heat cells, and context menus.
- CPU, Memory, Disk, Network, and GPU performance pages. Right-click CPU → **Change graph to → Logical processors** for live individual processor graphs. Optional kernel-time overlays.
- Eight main sections: Processes, Performance, App History, Startup Apps, Users, Details, Services, and Settings.
- Guarded individual/group process actions, persisted history, process properties, and launchd integration.

## Mac compatibility

**Designed for M1 and later M-series Macs running macOS 14 Sonoma or newer.** This includes Apple Silicon MacBook Air, MacBook Pro, iMac, Mac mini, Mac Studio, and Mac Pro models that meet the OS requirement. The release is compiled for general `arm64`, without M5-specific CPU tuning. Processor counts and available metrics are discovered at runtime.

**Built and physically tested on:**

| Component | Test machine |
|---|---|
| Mac | MacBook Pro, 16-inch, 2026 |
| Model identifier | `Mac17,8` |
| Chip | Apple M5 Pro, 18 CPU cores |
| Memory | 48 GB |
| macOS | 26.5.1 |
| Toolchain | Swift 6.3.3, Apple Command Line Tools |

The model identification matches [Apple's MacBook Pro model guide](https://support.apple.com/en-us/108052). M1–M4 and other M5 configurations are compatibility targets, **not separately hardware-tested claims**. macOS 14/15 are deployment targets, not locally tested OS versions. Driver-specific metrics may be unavailable on some machines. Intel Macs and macOS 13 or earlier are outside the distributed build's support target.

## Run and build

```sh
git clone https://github.com/hotredsam/task-manager-macos.git
cd task-manager-macos
```

The built application is `../Task Manager.app`. Open it normally in Finder. It is locally ad-hoc signed, not notarized for distribution.

```sh
./build.sh
open "../Task Manager.app"
./test.sh
```

The test script locates the bundled Swift Testing frameworks when using Command Line Tools, including their runtime libraries.

The project is a Swift package. Xcode is optional; current Apple Command Line Tools with Swift 6 and Python 3 are sufficient. `build.sh` explicitly targets `arm64`; the executable's minimum macOS version is 14.0. No package dependencies are downloaded. GitHub Actions runs the core tests and creates an Apple Silicon build artifact.

To install, move the built `Task Manager.app` into Applications, launch it, then right-click its Dock icon and choose **Options → Keep in Dock**.

## Using the app

- Click a column header to sort; click again to reverse. Drag headers to reorder and resize. The **View → Select columns** menu controls column visibility; View also exposes refresh and pause.
- Search by name, application, PID, owner, bundle ID, or executable path. Application groups expand automatically during a search.
- Use disclosure arrows to expand application/user groups. Arrow keys navigate; left/right collapse/expand the selected group. Command-click and Shift-click select multiple processes.
- Double-click a process or choose **Properties**. Right-click for termination, reveal, copying, and lower-priority actions.
- An application group can be ended only when every member passes the protection policy. Group selections are deduplicated, every target is listed or counted in the confirmation, and identities are revalidated immediately before signaling. User-owner groups cannot be bulk-terminated.
- **End Task** sends SIGTERM. **Force Quit** sends SIGKILL. Both require confirmation, revalidate PID plus start time, and enforce the protected-process policy immediately before signaling.
- **Efficiency mode** controls real **macOS Low Power Mode** for the current power source. It affects the whole Mac and works without selecting a process. The confirmation names the source and old/new modes; macOS requests administrator authorization. Turning it off restores the previous mode, including High Power on supported Macs. The battery and adapter profiles are kept separate. The button follows `ProcessInfo.isLowPowerModeEnabled` and system power notifications. Per-process scheduling remains separate under **Details → Set priority**, where only permitted priority reductions are offered.
- Command-1 through Command-8 switch sections. Command-F searches, Command-R refreshes, Command-P pauses/resumes, Command-comma opens Settings, and Command-backslash collapses the sidebar.
- In **Startup Apps**, eligible entries in the current user's `~/Library/LaunchAgents` can be enabled/disabled through launchd overrides. This affects future launches and does not stop or bootstrap an existing job. System and vendor-managed entries are read-only. The **Login Items & Extensions** button opens macOS's authoritative management interface.

## Window and graph controls

Navigation and command glyphs, context flyouts, submenu arrows, selection backgrounds, checkboxes, and selectors are custom drawn from the Windows references. Right-click a process for the Windows action order, including **Resource values → Memory → Percents / Values**. **More** contains the additional macOS Force Quit and copy actions.

Use the caption buttons on the top right. Maximize fills the current display's usable area and restores the previous frame on the next click; it does not create a macOS full-screen Space. Right-click the title bar for Restore, Minimize, Maximize, Snap layout, and Close. Option-F4 closes the window; Option-Space opens the window menu. F5 refreshes and Control-F searches, alongside the macOS Command-key shortcuts. Option-N opens Run new task, Option-E ends an eligible selection, Option-V toggles Low Power Mode, and Control-Tab cycles sections.

CPU graph settings persist across launches. Each logical processor uses its own Mach tick counters, with a separate 0–100% scale. Kernel-time overlays use the per-processor system ticks. The first observation establishes a baseline; it is not shown as a fabricated utilization reading. Right-click any performance graph for **Copy** or **Graph summary view**; double-click the main graph to toggle its summary view.

## Architecture

- `SystemBridge`: public SDK `libproc`, Mach, sysctl, BSD interface counters, IOKit, and utmpx access, with explicit ownership of allocations and Mach ports.
- `TaskCore`: snapshots, Mach-tick-to-nanosecond conversion, delta calculations, stable process identities, grouping, filtering, ordering, protection rules, bounded history, and launchd inventory/parsing.
- `TaskManager`: AppKit application/window, NSTableView cell reuse and retained selection, background sampling, native drawing for graphs, settings, service actions, inspector, and an executable UI integration harness.
- Sampling uses a serial utility queue. In-flight reads cannot overlap. Only snapshot delivery and view updates run on the main thread. Service discovery runs separately every 15 seconds.
- High / Normal / Low refresh at 1 / 2 / 4 seconds. Paused freezes automatic updates. Graph samples are bounded by 60 / 180 / 300 seconds. History is capped at 5,000 executable/application entries and saved locally once per minute.
- Preferences use UserDefaults. History resides in `~/Library/Application Support/TaskManager/history.json`. The application never uploads process data.

## Windows → macOS mapping

| Windows Task Manager concept | macOS implementation |
|---|---|
| Processes / Details | `proc_listpids`, `proc_pidinfo`, `proc_pidpath`, BSD `KERN_PROC_PID` identity fallback; names, users, states, parent PIDs, thread counts, nice values, architecture, start time |
| Application process tree | Outermost `.app` bundle metadata plus known parent ancestry; helper members are expandable |
| CPU percentage | Delta of process user + system nanoseconds, divided by wall time and logical CPU count; total machine capacity is 100% |
| CPU performance | Mach host CPU ticks and `host_processor_info` per-processor user/system/idle/nice ticks, sysctl metadata, load averages, uptime |
| Memory | Per-process resident bytes (RSS); host VM active, wired, compressed, free, inactive, purgeable; sysctl swap usage |
| Disk | Per-process `proc_pid_rusage` physical disk-I/O counters where permitted; IOKit block-storage totals when published; `statfs` for data-volume capacity |
| Network | 64-bit BSD routing/interface byte counters for active `en*` interfaces; interface IPv4 addresses |
| GPU | Metal device identity, unified-memory support, recommended working-set limit; no fabricated utilization |
| App History | Observed CPU core-seconds, peak individual-process RSS, observed duration, disk I/O; locally persisted |
| Startup Apps | LaunchAgent / LaunchDaemon property lists, launchd overrides, and a direct link to Login Items & Extensions |
| Users | Process owners, aggregated CPU/RSS, and utmpx login sessions; background-only owners are labeled explicitly |
| Services | User/system launchd jobs, labels, PIDs, loaded/on-demand/disabled state, plist programs and domains |
| Efficiency mode | macOS Low Power Mode, read through ProcessInfo/IOKit and changed via administrator-authorized `pmset`; current-source profile and previous High/Automatic mode preserved |
| End Task / Force Quit | SIGTERM / SIGKILL after confirmation, owner checks, critical-process policy, and identity revalidation |

## Accuracy and limitations

- Some processes restrict details even without App Sandbox. Missing counters display **—**. Monitoring needs no root, Full Disk Access, SIP exceptions, private frameworks, or security bypasses. Changing Low Power Mode is an explicit exception: it uses the system administrator authorization dialog to run a narrowly scoped `pmset` command. No privileged helper is installed, and the app never receives or stores the password.
- Per-process GPU utilization, GPU engine attribution, per-process network traffic, Apple's Energy Impact score, dynamic CPU frequency, reliable disk active time, and package power are not available through the supported APIs used here. The UI identifies these limitations rather than showing zero or estimating a false metric.
- Process memory is RSS, not Task Manager's Windows private working set. Shared pages can be counted more than once across processes. System memory uses a documented formula shown directly in the UI; it is not an exact recreation of Activity Monitor's categories.
- IOKit disk counters depend on the installed storage driver. No counters means unavailable throughput. The disk graph aggregates exposed block devices, while capacity describes the APFS data volume, whose space may be shared.
- Network totals omit loopback and virtual tunnel interfaces to avoid common double counting; they are not a complete accounting of every possible interface topology. Link speed is not reported. IPv4 addresses are shown.
- GPU recommended working-set size is a Metal limit, not GPU memory in use. No GPU utilization graph is drawn when measurement is unavailable.
- Grouping never guesses ownership of shared or launchd-reparented WebKit/XPC helpers. Helpers whose bundle/ancestry does not identify a host remain separate. Group CPU/RSS values are sums and may include shared memory.
- History starts counting CPU deltas after first observation. It excludes samples missed while the app is closed. It is not historical data recovered from macOS. Peak memory is the maximum of an individual observed member, not the simultaneous sum of every helper in an application.
- There is no supported public API to enumerate and toggle every other application's modern background/login item. The app inventories readable launchd plists/jobs and delegates the authoritative modern list to System Settings. `SMAppService.mainApp` manages this application's own launch-at-login setting and may require approval or a stable trusted app location.
- `launchctl` is deliberately used only for launchd inventory and user-approved overrides because the supported Service Management API does not provide a general replacement for managing arbitrary third-party jobs. It is invoked directly with argument arrays, never shell interpolation. Commands are time-bounded; their human-readable output is defensively parsed.
- Publisher labels are derived from launchd label prefixes and clearly labeled **Publisher hint**. They are not verified publisher signatures. The process inspector separately reports available code-signing identifiers and team IDs.
- utmpx sessions do not guarantee an exhaustive list of every GUI/background login state. Users without a reported session are labeled **Background owner**.
- This local build is not sandboxed or notarized. Monitoring and process actions use the current user's permissions; changing Low Power Mode explicitly requests administrator authorization. Termination cannot be made perfectly race-free with POSIX PIDs; identity is rechecked immediately before each action.

## Safety

Kernel/launchd, the monitor itself, other users' processes, critical named services, and executables under `/System`, `/usr/libexec`, or `/usr/sbin` are protected. All destructive actions retain mandatory confirmation. Startup changes are restricted to non-Apple current-user LaunchAgents. No system service is disabled by the application.

## Verification

`./test.sh` covers process parsing/sampling, CPU and memory calculations, delta resets, hierarchy grouping and cycles, sorting, all search fields, stable identities, refresh states, protected processes, launchctl parsing, and history accumulation.

The app includes an in-process AppKit UI integration harness:

```sh
open "../Task Manager.app" --args --ui-test --qa-dir "/absolute/path/to/qa"
```

It drives actual navigation buttons, process search, sorting, selection, grouping, resource selection, settings, inspector opening, and asynchronous pause/resume. It writes `ui-tests.txt`. Visual checks are performed separately against the running app. It does not terminate real user processes. This harness is distinct from Xcode's external XCUITest runner, which is not installed with Command Line Tools. See [VERIFICATION.md](VERIFICATION.md) for the completed run and manual UI checks.

## Power-mode behavior

The controller detects support with `pmset -g cap`, reads profiles with `pmset -g custom`, and identifies the current source with public IOKit power-source APIs. Newer Macs expose `powermode` (0 Automatic, 1 Low, 2 High); older models expose `lowpowermode` (0/1). The implementation handles both forms. Writes are restricted to fixed, enumerated source/mode arguments, and the resulting profile is reread before success is accepted. Cancelling either confirmation or system authorization leaves the mode unchanged. Some older macOS/model combinations do not offer Low Power Mode; the action is disabled when unavailable.

## API research references

- [Apple XNU process structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h), cross-checked with this Mac's SDK `libproc.h`, `sys/proc_info.h`, and `sys/resource.h`.
- [Mach host processor information](https://developer.apple.com/documentation/kernel/1502854-host_processor_info).
- [IOKit](https://developer.apple.com/documentation/iokit), and this Mac's public `IOBlockStorageDriver.h` / power-source headers.
- [Apple power modes](https://support.apple.com/en-us/101613), [Apple pmset source](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m).
- [ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo).
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).
- Public SDK Metal, AppKit, Security, BSD routing, sysctl, statfs, and utmpx headers; local `launchctl` manual and observed command output.

## Original Windows icon

The app uses the original gray-frame/blue-graph Task Manager artwork matching the Windows 11 22H2 reference. The source ICO contains 16, 24, 32, 48, 64, 96, 128, 192, and 256 pixel representations. Source checksums are retained in `Assets/icon-sources.json`. `Scripts/ExtractIcon.py` decodes the 32-bit source pixels without resampling; `Scripts/MakeIcon.py` embeds the corresponding PNGs into ICNS. macOS controls Dock display size and compositing. The original resource pixels are preserved, but identical on-screen rasterization across operating systems at arbitrary scales cannot be guaranteed. Provenance and the artwork's exclusion from MIT are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Original code and documentation are available under the [MIT License](LICENSE). The original Windows icon and bundled SIL-licensed Selawik fonts are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
