# Development and measurement

`./test.sh` runs Rust unit/regression tests, including a live sampler and a disposable process identity/termination test. `./build.sh` builds the release app. The C bridge is shared with the retained Swift baseline, but the primary executable and UI are Rust.

The app writes bounded timing observations to `~/Library/Application Support/TaskManager/rust-timings.json` approximately every 30 seconds. Restart to begin a new interaction buffer. Entries named `paint:<action>` include action handling, synchronous view drawing submission, and the accessibility notification. Plain action entries omit drawing. These measurements exclude input delivery and display scanout; they cannot establish input-to-photon latency.

To reproduce a basic interaction sample, launch a release build, allow initial sampling/icon loading to settle, visit all eight pages, click resource headers in both directions, and exercise search and menus. Record the process count, refresh interval, window size, hardware, concurrent workload, and warm/cold status. Keep the recorder off during measurements. Native window management and administrative operations may involve OS work beyond the application handler.

`rust/target/release/task-manager --bench-model` reports model rebuilding separately from rendering. `--sample` performs a one-shot native sample. Neither is a full UI responsiveness benchmark.

For explicitly enabled demo capture, create `demo-export-path.txt` in the application's support directory containing an absolute output directory, then press Command-Shift-R in the app to start/stop. It exports only the application's own view as timestamped PNG frames at approximately 10 fps, with a bounded queue and a 1,800-frame cap. It does not record other apps or the display. Remove the configuration file when finished. The feature is inactive by default.
