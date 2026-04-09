// build.rs — links librocksmith_shim.so (Rocksmith2014.NET NativeAOT) and
//            libvgmstream.a (WEM audio decoding) on Linux and Windows.
//
// Pre-built libraries live at:
//   gdextension/lib/linux/librocksmith_shim.so   — NativeAOT shared lib (dotnet publish linux-x64)
//   gdextension/lib/linux/libvgmstream.a          — static, built from vgmstream main
//   gdextension/lib/windows/libvgmstream.a        — static, MinGW cross-compiled USE_VORBIS=ON
//   gdextension/lib/windows/libvorbisfile.a       — cross-compiled libvorbisfile
//   gdextension/lib/windows/libvorbis.a           — cross-compiled libvorbis
//   gdextension/lib/windows/libogg.a              — cross-compiled libogg

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS")
        .unwrap_or_default();

    match target_os.as_str() {
        "linux" => {
            let lib_dir = format!("{manifest_dir}/../lib/linux");
            println!("cargo:rustc-link-search=native={lib_dir}");

            // ── Rocksmith2014.NET NativeAOT shared library ─────────────────
            println!("cargo:rustc-link-lib=dylib=rocksmith_shim");
            // Make the .so look for librocksmith_shim.so in its own directory.
            println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN");

            // ── vgmstream WEM audio decoder (static) ───────────────────────
            println!("cargo:rustc-link-lib=static=vgmstream");
            println!("cargo:rustc-link-lib=dylib=stdc++");
            println!("cargo:rustc-link-lib=dylib=m");
        }
        "windows" => {
            let lib_dir = format!("{manifest_dir}/../lib/windows");
            println!("cargo:rustc-link-search=native={lib_dir}");
            // Windows: vgmstream WEM decoder (cross-compiled via MinGW, USE_VORBIS=ON).
            println!("cargo:rustc-link-lib=static=vgmstream");
            println!("cargo:rustc-link-lib=static=vorbisfile");
            println!("cargo:rustc-link-lib=static=vorbis");
            println!("cargo:rustc-link-lib=static=ogg");
            println!("cargo:rustc-link-lib=static=stdc++");
            // NOTE: RocksmithShim.dll must be built on Windows with:
            //   dotnet publish -c Release -r win-x64
            // and placed in gdextension/bin/ alongside godot_rocksmith.dll.
        }
        _ => {}
    }

    // Re-run if libraries change.
    println!("cargo:rerun-if-changed=../lib/linux/librocksmith_shim.so");
    println!("cargo:rerun-if-changed=../lib/linux/libvgmstream.a");
    println!("cargo:rerun-if-changed=../lib/windows/libvgmstream.a");
    println!("cargo:rerun-if-changed=../lib/windows/libvorbisfile.a");
    println!("cargo:rerun-if-changed=../lib/windows/libvorbis.a");
    println!("cargo:rerun-if-changed=../lib/windows/libogg.a");
    println!("cargo:rerun-if-changed=build.rs");
}
