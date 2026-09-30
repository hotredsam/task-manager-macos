fn main() {
    cc::Build::new()
        .file("../Sources/SystemBridge/SystemBridge.c")
        .include("../Sources/SystemBridge/include")
        .compile("systembridge");
    println!("cargo:rustc-link-lib=framework=IOKit");
    println!("cargo:rustc-link-lib=framework=CoreFoundation");
    println!("cargo:rerun-if-changed=../Sources/SystemBridge/SystemBridge.c");
}
