// build.rs — links libvgmstream.a for WEM audio decoding on Linux and Windows.
//
// Pre-built static libraries live at:
//   gdextension/lib/linux/libvgmstream.a  — built from vgmstream main (GCC/Linux)
//   gdextension/lib/windows/libvgmstream.a — cross-compiled with MinGW (x86_64-w64-mingw32-gcc)

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS")
        .unwrap_or_default();

    match target_os.as_str() {
        "linux" => {
            let lib_dir = format!("{manifest_dir}/../lib/linux");
            println!("cargo:rustc-link-search=native={lib_dir}");
            println!("cargo:rustc-link-lib=static=vgmstream");
            // vgmstream is primarily C with some C++ codec implementations; link stdc++.
            println!("cargo:rustc-link-lib=dylib=stdc++");
            println!("cargo:rustc-link-lib=dylib=m");
        }
        "windows" => {
            let lib_dir = format!("{manifest_dir}/../lib/windows");
            println!("cargo:rustc-link-search=native={lib_dir}");
            println!("cargo:rustc-link-lib=static=vgmstream");
            // MinGW runtime for C++ codecs inside vgmstream.
            println!("cargo:rustc-link-lib=static=stdc++");
        }
        _ => {}
    }

    // Re-run if the native library changes.
    println!("cargo:rerun-if-changed=../lib/linux/libvgmstream.a");
    println!("cargo:rerun-if-changed=../lib/windows/libvgmstream.a");
    println!("cargo:rerun-if-changed=build.rs");
}
