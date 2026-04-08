// build.rs — links vgmstream.a (WEM audio decoding) for Linux and Windows.
//
// The .NET bridge (RocksmithBridge.dll) is now loaded at runtime by the Rust
// GDExtension via the netcorehost crate (CLR hosting API).  No NativeAOT shim,
// no import library — the CLR is hosted in-process, no link-time dependency.
//
// Pre-built libraries:
//   gdextension/lib/linux/libvgmstream.a         — static, built from vgmstream main
//   gdextension/lib/windows/libvgmstream.a       — static, MinGW cross-compiled USE_VORBIS=ON
//   gdextension/lib/windows/libvorbisfile.a      — cross-compiled libvorbisfile
//   gdextension/lib/windows/libvorbis.a          — cross-compiled libvorbis
//   gdextension/lib/windows/libogg.a             — cross-compiled libogg

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    match target_os.as_str() {
        "linux" => {
            let lib_dir = format!("{manifest_dir}/../lib/linux");
            println!("cargo:rustc-link-search=native={lib_dir}");

            // vgmstream WEM audio decoder (static)
            println!("cargo:rustc-link-lib=static=vgmstream");
            println!("cargo:rustc-link-lib=dylib=stdc++");
            println!("cargo:rustc-link-lib=dylib=m");
        }
        "windows" => {
            let lib_dir = format!("{manifest_dir}/../lib/windows");
            println!("cargo:rustc-link-search=native={lib_dir}");

            // vgmstream WEM decoder + Wwise Vorbis deps (MinGW cross-compiled, USE_VORBIS=ON)
            println!("cargo:rustc-link-lib=static=vgmstream");
            println!("cargo:rustc-link-lib=static=vorbisfile");
            println!("cargo:rustc-link-lib=static=vorbis");
            println!("cargo:rustc-link-lib=static=ogg");
            println!("cargo:rustc-link-lib=static=stdc++");
        }
        _ => {}
    }

    println!("cargo:rerun-if-changed=../lib/linux/libvgmstream.a");
    println!("cargo:rerun-if-changed=../lib/windows/libvgmstream.a");
    println!("cargo:rerun-if-changed=../lib/windows/libvorbisfile.a");
    println!("cargo:rerun-if-changed=../lib/windows/libvorbis.a");
    println!("cargo:rerun-if-changed=../lib/windows/libogg.a");
    println!("cargo:rerun-if-changed=build.rs");
}
