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
//
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
            // This environment provides versioned .so files without unversioned
            // linker symlinks, so link the exact library paths.
            println!("cargo:rustc-link-arg=/usr/lib/x86_64-linux-gnu/libvorbisfile.so.3");
            println!("cargo:rustc-link-arg=/usr/lib/x86_64-linux-gnu/libvorbis.so.0");
            println!("cargo:rustc-link-arg=/usr/lib/x86_64-linux-gnu/libogg.so.0");
            println!("cargo:rustc-link-lib=dylib=stdc++");
            println!("cargo:rustc-link-lib=dylib=m");
        }
        "windows" => {
            let lib_dir = format!("{manifest_dir}/lib/windows");
            println!("cargo:rustc-link-search=native={lib_dir}");
            if let Ok(output) = std::process::Command::new("x86_64-w64-mingw32-g++")
                .arg("-print-file-name=libstdc++.a")
                .output()
            {
                let libstdcpp = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !libstdcpp.is_empty() {
                    if let Some(parent) = std::path::Path::new(&libstdcpp).parent() {
                        println!("cargo:rustc-link-search=native={}", parent.display());
                    }
                }
            }
            // Windows: vgmstream WEM decoder (cross-compiled via MinGW, USE_VORBIS=ON).
            println!("cargo:rustc-link-lib=static=vgmstream");
            println!("cargo:rustc-link-lib=static=vorbisfile");
            println!("cargo:rustc-link-lib=static=vorbis");
            println!("cargo:rustc-link-lib=static=ogg");
        }
        _ => {}
    }

    if target_os == "windows" {
        println!("cargo:rustc-link-lib=static=stdc++");
    }

    // Re-run if libraries change.
    println!("cargo:rerun-if-changed=lib/linux/libvgmstream.a");
    println!("cargo:rerun-if-changed=lib/windows/libvgmstream.a");
    println!("cargo:rerun-if-changed=lib/windows/libvorbisfile.a");
    println!("cargo:rerun-if-changed=lib/windows/libvorbis.a");
    println!("cargo:rerun-if-changed=lib/windows/libogg.a");
    println!("cargo:rerun-if-changed=build.rs");
}
