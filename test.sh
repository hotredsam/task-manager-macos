#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
cargo test --locked --manifest-path rust/Cargo.toml
