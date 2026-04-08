// build.rs — links libvgmstream.a for WEM audio decoding on Linux.
//
// On Windows the library is not yet available as a cross-compiled static lib,
// so the vgmstream feature is disabled there at compile time (the AudioEngine
// class is still exposed to Godot but open() returns false with a warning).

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS")
        .unwrap_or_default();

    if target_os == "linux" {
        // libvgmstream.a lives at gdextension/lib/linux/ relative to workspace root.
        // CARGO_MANIFEST_DIR == gdextension/src/ so we go up one level.
        let lib_dir = format!("{manifest_dir}/../lib/linux");
        println!("cargo:rustc-link-search=native={lib_dir}");
        println!("cargo:rustc-link-lib=static=vgmstream");

        // vgmstream is a C/C++ library; link the C++ standard library.
        println!("cargo:rustc-link-lib=dylib=stdc++");
        // math library (used internally by some codecs)
        println!("cargo:rustc-link-lib=dylib=m");
    }

    // Re-run if the native library changes.
    println!("cargo:rerun-if-changed=../lib/linux/libvgmstream.a");
    println!("cargo:rerun-if-changed=build.rs");
}
