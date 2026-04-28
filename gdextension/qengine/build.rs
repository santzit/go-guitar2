fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set");

    println!("cargo::rustc-check-cfg=cfg(q_available)");

    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();

    if target_os == "windows" {
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
    } else if target_os == "linux" {
        println!("cargo:rustc-link-lib=dylib=stdc++");
        println!("cargo:rustc-link-lib=dylib=m");
    }

    let root_dir = format!("{manifest_dir}/..");

    let q_lib_dir = match target_os.as_str() {
        "linux" => format!("{root_dir}/lib/linux"),
        "windows" => format!("{root_dir}/lib/windows"),
        _ => String::new(),
    };
    let q_lib_path = if q_lib_dir.is_empty() {
        String::new()
    } else {
        format!("{q_lib_dir}/libq_bridge.a")
    };
    let has_prebuilt_q = !q_lib_path.is_empty() && std::path::Path::new(&q_lib_path).exists();

    let q_include_repo = format!("{root_dir}/include");
    let q_include_new = format!("{root_dir}/extern/q/q_lib/include");
    let q_include_old = format!("{root_dir}/extern/q/include");
    let infra_include = format!("{root_dir}/extern/infra/include");

    let q_include = if std::path::Path::new(&format!("{q_include_repo}/q")).exists() {
        q_include_repo.clone()
    } else if std::path::Path::new(&q_include_new).exists() {
        q_include_new.clone()
    } else {
        q_include_old.clone()
    };

    let has_q_headers =
        std::path::Path::new(&q_include).exists() && std::path::Path::new(&infra_include).exists();

    if has_prebuilt_q || has_q_headers {
        println!("cargo:rustc-cfg=q_available");

        if has_prebuilt_q {
            println!("cargo:rustc-link-search=native={q_lib_dir}");
            println!("cargo:rustc-link-lib=static=q_bridge");
        } else {
            cc::Build::new()
                .cpp(true)
                .std("c++20")
                .include(&q_include)
                .include(&infra_include)
                .file(format!("{root_dir}/q_bridge/q_bridge.cpp"))
                .compile("q_bridge");
        }
    } else {
        println!("cargo:warning=cycfi/q bridge library not found and headers are unavailable — QEngine disabled");
    }

    if target_os == "windows" {
        println!("cargo:rustc-link-lib=static=stdc++");
    }

    println!("cargo:rerun-if-changed={root_dir}/q_bridge/q_bridge.cpp");
    println!("cargo:rerun-if-changed={root_dir}/q_bridge/q_bridge.h");
    println!("cargo:rerun-if-changed={root_dir}/include/q");
    println!("cargo:rerun-if-changed={root_dir}/extern/q/q_lib/include");
    println!("cargo:rerun-if-changed={root_dir}/extern/q/include");
    println!("cargo:rerun-if-changed={root_dir}/extern/infra/include");
    println!("cargo:rerun-if-changed={root_dir}/lib/linux/libq_bridge.a");
    println!("cargo:rerun-if-changed={root_dir}/lib/windows/libq_bridge.a");
    println!("cargo:rerun-if-changed=build.rs");
}
