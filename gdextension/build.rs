// build.rs — links libvgmstream.a (WEM audio decoding) for Linux and Windows.
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

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS")
        .unwrap_or_default();

    // ── cycfi/Q pitch detection wrapper (C++20, header-only library) ──────────
    // Compiles src/q_pitch_ffi.cpp against the vendored Q and infra headers.
    let q_include     = format!("{manifest_dir}/vendor/q_lib/include");
    let infra_include = format!("{manifest_dir}/vendor/infra-master/include");

    cc::Build::new()
        .cpp(true)
        .std("c++20")
        .include(&q_include)
        .include(&infra_include)
        .include(format!("{manifest_dir}/src"))
        .warnings(false)   // Q headers produce pedantic warnings — suppress them
        .file(format!("{manifest_dir}/src/q_pitch_ffi.cpp"))
        .compile("q_pitch");

    println!("cargo:rerun-if-changed=src/q_pitch_ffi.cpp");
    println!("cargo:rerun-if-changed=src/q_pitch_ffi.h");
    println!("cargo:rerun-if-changed=vendor/q_lib/include/q/pitch/pitch_detector.hpp");
    println!("cargo:rerun-if-changed=vendor/q_lib/include/q/pitch/period_detector.hpp");

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

    // Re-run if libraries change.
    println!("cargo:rerun-if-changed=lib/linux/libvgmstream.a");
    println!("cargo:rerun-if-changed=lib/windows/libvgmstream.a");
    println!("cargo:rerun-if-changed=lib/windows/libvorbisfile.a");
    println!("cargo:rerun-if-changed=lib/windows/libvorbis.a");
    println!("cargo:rerun-if-changed=lib/windows/libogg.a");
    println!("cargo:rerun-if-changed=build.rs");
}
