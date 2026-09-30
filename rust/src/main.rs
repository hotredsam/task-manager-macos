mod draw;
mod model;
mod power;
mod services;
mod state;
mod ui;
fn main() {
    if std::env::args().any(|a| a == "--bench-model") {
        state::benchmark_model();
        return;
    }
    if std::env::args().any(|a| a == "--sample") {
        let mut s = model::Sampler::default();
        let a = s.sample();
        println!(
            "{} processes, {} logical CPUs; {:0.2} ms",
            a.processes.len(),
            a.system.raw.logical,
            a.system.sample_ms
        );
    } else {
        ui::run();
    }
}
