// build.rs — links libvgmstream.a (WEM audio decoding) for Linux and Windows,
//            and conditionally compiles q_bridge.cpp (cycfi/q pitch detection).
//
// PSARC/SNG parsing is handled by pure-Rust crates (rocksmith2014-psarc,
// rocksmith2014-sng) — no .NET runtime, no librocksmith_shim.so needed.
//
// Pre-built libraries live at:
//   lib/linux/libvgmstream.a          — static, built from vgmstream main (USE_VORBIS=ON USE_G719=OFF)
//   lib/windows/libvgmstream.a        — static, MinGW cross-compiled USE_VORBIS=ON
//   lib/windows/libvorbisfile.a       — cross-compiled libvorbisfile
//   lib/windows/libvorbis.a           — cross-compiled libvorbis
//   lib/windows/libogg.a              — cross-compiled libogg
//
// cycfi/q pitch detection:
//   Requires the Q and infra header-only libraries as git submodules:
//     extern/q/include     — https://github.com/cycfi/q
//     extern/infra/include — https://github.com/cycfi/infra  (Q dependency)
//   When both include directories are present, q_bridge.cpp is compiled with
//   the `cc` crate and the `q_available` cfg flag is emitted so that
//   `src/q_ffi.rs` and `src/pitch_detector.rs` are compiled in.
//
//   To initialise the submodules after cloning:
//     git submodule update --init --recursive

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS")
        .unwrap_or_default();

    match target_os.as_str() {
        "linux" => {
            let lib_dir = format!("{manifest_dir}/lib/linux");
            println!("cargo:rustc-link-search=native={lib_dir}");

            // ── vgmstream WEM audio decoder (static, USE_VORBIS=ON USE_G719=OFF) ──
            println!("cargo:rustc-link-arg=-Wl,--whole-archive");
            println!("cargo:rustc-link-arg={lib_dir}/libvgmstream.a");
            println!("cargo:rustc-link-arg=-Wl,--no-whole-archive");
            // Vorbis / Ogg — required for Wwise WEM Vorbis decode.
            // Use static linking so the pre-built .so has no libvorbis runtime dep.
            println!("cargo:rustc-link-search=native=/usr/lib/x86_64-linux-gnu");
            println!("cargo:rustc-link-lib=static=vorbisfile");
            println!("cargo:rustc-link-lib=static=vorbis");
            println!("cargo:rustc-link-lib=static=ogg");
            println!("cargo:rustc-link-lib=dylib=stdc++");
            println!("cargo:rustc-link-lib=dylib=m");
        }
        "windows" => {
            let lib_dir = format!("{manifest_dir}/lib/windows");
            println!("cargo:rustc-link-search=native={lib_dir}");
            // Windows: vgmstream WEM decoder (cross-compiled via MinGW, USE_VORBIS=ON).
            println!("cargo:rustc-link-lib=static=vgmstream");
            println!("cargo:rustc-link-lib=static=vorbisfile");
            println!("cargo:rustc-link-lib=static=vorbis");
            println!("cargo:rustc-link-lib=static=ogg");
            println!("cargo:rustc-link-lib=static=stdc++");
        }
        _ => {}
    }

    // ── cycfi/q pitch-detection bridge ────────────────────────────────────────
    // Only compiled when both header trees are present (submodules initialised).
    let q_include    = format!("{manifest_dir}/extern/q/include");
    let infra_include = format!("{manifest_dir}/extern/infra/include");

    if std::path::Path::new(&q_include).exists()
        && std::path::Path::new(&infra_include).exists()
    {
        println!("cargo:rustc-cfg=q_available");

        cc::Build::new()
            .cpp(true)
            .std("c++17")
            .include(&q_include)
            .include(&infra_include)
            .file(format!("{manifest_dir}/q_bridge/q_bridge.cpp"))
            .compile("q_bridge");

        println!("cargo:rerun-if-changed=q_bridge/q_bridge.cpp");
        println!("cargo:rerun-if-changed=q_bridge/q_bridge.h");
        println!("cargo:rerun-if-changed=extern/q/include");
        println!("cargo:rerun-if-changed=extern/infra/include");
    } else {
        println!("cargo:warning=cycfi/q submodules not found — pitch detection disabled. \
                  Run: git submodule update --init --recursive");
    }

    // Re-run if libraries change.
    println!("cargo:rerun-if-changed=lib/linux/libvgmstream.a");
    println!("cargo:rerun-if-changed=lib/windows/libvgmstream.a");
    println!("cargo:rerun-if-changed=lib/windows/libvorbisfile.a");
    println!("cargo:rerun-if-changed=lib/windows/libvorbis.a");
    println!("cargo:rerun-if-changed=lib/windows/libogg.a");
    println!("cargo:rerun-if-changed=build.rs");
}
