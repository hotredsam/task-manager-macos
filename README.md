# Task Manager for macOS

A native, Apple Silicon macOS utility with the interaction structure of Windows 11 Task Manager: collapsible navigation, dense tables, resource heat cells, process groups, live graphs, an inspector, and guarded process actions. Built in Swift and AppKit with a small C bridge. Requires macOS 14 or newer; no external dependencies.

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

The project is a Swift package. Xcode is optional; Apple Command Line Tools are sufficient. The release build is optimized for the current machine's architecture.

To install, move the built `Task Manager.app` into Applications, launch it, then right-click its Dock icon and choose **Options → Keep in Dock**.

## Using the app

- Click a column header to sort; click again to reverse. Drag headers to reorder and resize. The **Columns** menu controls visibility.
- Search by name, application, PID, owner, bundle ID, or executable path. Application groups expand automatically during a search.
- Use disclosure arrows to expand application/user groups. Arrow keys navigate; left/right collapse/expand the selected group. Command-click and Shift-click select multiple processes.
- Double-click a process or choose **Inspect**. Right-click for termination, reveal, copying, and lower-priority actions.
- Select individual processes inside a group before ending tasks. Group rows summarize members and intentionally cannot kill a whole app tree indiscriminately.
- **End Task** sends SIGTERM. **Force Quit** sends SIGKILL. Both require confirmation, revalidate PID plus start time, and enforce the protected-process policy immediately before signaling.
- **Lower priority** raises the nice value by five, to a maximum of 19. Raising process priority is intentionally not offered because it may require elevated privileges.
- Command-1 through Command-8 switch sections. Command-F searches, Command-R refreshes, Command-P pauses/resumes, Command-comma opens Settings, and Command-backslash collapses the sidebar.
- In **Startup Apps**, eligible entries in the current user's `~/Library/LaunchAgents` can be enabled/disabled through launchd overrides. This affects future launches and does not stop or bootstrap an existing job. System and vendor-managed entries are read-only. The **Login Items & Extensions** button opens macOS's authoritative management interface.

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
| CPU performance | Mach host CPU ticks, sysctl processor/core metadata, load averages, uptime |
| Memory | Per-process resident bytes (RSS); host VM active, wired, compressed, free, inactive, purgeable; sysctl swap usage |
| Disk | Per-process `proc_pid_rusage` physical disk-I/O counters where permitted; IOKit block-storage totals when published; `statfs` for data-volume capacity |
| Network | 64-bit BSD routing/interface byte counters for active `en*` interfaces; interface IPv4 addresses |
| GPU | Metal device identity, unified-memory support, recommended working-set limit; no fabricated utilization |
| Energy / battery | IOKit power-source charge and supply; ProcessInfo low-power and thermal state |
| App History | Observed CPU core-seconds, peak individual-process RSS, observed duration, disk I/O; locally persisted |
| Startup Apps | LaunchAgent / LaunchDaemon property lists, launchd overrides, and a direct link to Login Items & Extensions |
| Users | Process owners, aggregated CPU/RSS, and utmpx login sessions; background-only owners are labeled explicitly |
| Services | User/system launchd jobs, labels, PIDs, loaded/on-demand/disabled state, plist programs and domains |
| End Task / Force Quit | SIGTERM / SIGKILL after confirmation, owner checks, critical-process policy, and identity revalidation |

## Accuracy and limitations

- Some processes restrict details even without App Sandbox. Missing counters display **—**. No root, Full Disk Access, SIP exceptions, private frameworks, or security bypasses are used.
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
- This local build is not sandboxed or notarized. It uses the current user's permissions and does not request administrator access. Termination cannot be made perfectly race-free with POSIX PIDs; identity is rechecked immediately before each action.

## Safety

Kernel/launchd, the monitor itself, other users' processes, critical named services, and executables under `/System`, `/usr/libexec`, or `/usr/sbin` are protected. All destructive actions retain mandatory confirmation. Startup changes are restricted to non-Apple current-user LaunchAgents. No system service is disabled by the application.

## Verification

`./test.sh` covers process parsing/sampling, CPU and memory calculations, delta resets, hierarchy grouping and cycles, sorting, all search fields, stable identities, refresh states, protected processes, launchctl parsing, and history accumulation.

The app includes an in-process AppKit UI integration harness:

```sh
open "../Task Manager.app" --args --ui-test --qa-dir "/absolute/path/to/qa"
```

It drives actual navigation buttons, process search, sorting, selection, grouping, resource selection, settings, inspector opening, and asynchronous pause/resume. It writes `ui-tests.txt`. Visual checks are performed separately against the running app. It does not terminate real user processes. This harness is distinct from Xcode's external XCUITest runner, which is not installed with Command Line Tools. See [VERIFICATION.md](VERIFICATION.md) for the completed run and manual UI checks.

## API research references

- [Apple XNU process structures](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h), cross-checked with this Mac's SDK `libproc.h`, `sys/proc_info.h`, and `sys/resource.h`.
- [Mach host processor information](https://developer.apple.com/documentation/kernel/1502854-host_processor_info).
- [IOKit](https://developer.apple.com/documentation/iokit), and this Mac's public `IOBlockStorageDriver.h` / power-source headers.
- [ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo).
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).
- Public SDK Metal, AppKit, Security, BSD routing, sysctl, statfs, and utmpx headers; local `launchctl` manual and observed command output.

## Original Windows icon

The application bundles the original Windows 11 24H2 Task Manager icon resources, credited to Microsoft and extracted from `C:\Windows\System32\Taskmgr.exe` by the uploader on [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Windows_11_TASKMGR.png). Original 16, 32, 48, 64, and 256 pixel PNGs and source SHA-256 checksums are retained in `Assets`. `Scripts/MakeIcon.py` packages supported sizes directly into ICNS chunks; it does not redraw, recolor, resample, or alter the embedded PNG bytes. macOS controls Dock display size and compositing. The resource pixels are preserved; identical on-screen rasterization across operating systems at arbitrary scales cannot be guaranteed.

## License

Original code and documentation are available under the [MIT License](LICENSE). Icon provenance and the source's public-domain designation are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
