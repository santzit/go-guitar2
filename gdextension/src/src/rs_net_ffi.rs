/// rs_net_ffi.rs — Rust FFI bindings for the RocksmithShim NativeAOT library.
///
/// The C# shim (gdextension/dotnet/RocksmithShim/) is compiled with NativeAOT
/// into `librocksmith_shim.so` (Linux) / `RocksmithShim.dll` (Windows).
/// The Linux build is produced by `dotnet publish -c Release -r linux-x64`.
/// The Windows build must be produced on a Windows machine:
///   dotnet publish -c Release -r win-x64
/// and the resulting `RocksmithShim.dll` placed in `gdextension/bin/`.
///
/// All memory returned by the C functions (notes JSON, WEM bytes) is owned by
/// the caller after the call and must be freed with `rs_free_ptr`.
/// The opaque handle returned by `rs_open_psarc` must be freed with `rs_close`.

use std::ffi::{CString, CStr};

// ── Platform-specific FFI block ───────────────────────────────────────────────

#[cfg(any(target_os = "linux", target_os = "windows"))]
mod ffi {
    use std::ffi::c_void;

    // Linux: links librocksmith_shim.so (NativeAOT, built via build_shim.sh).
    // Windows: links RocksmithShim.dll (NativeAOT, built on Windows with
    //          `dotnet publish -c Release -r win-x64`; import lib generated
    //          from RocksmithShim.def via dlltool during cross-compilation).
    //
    // Note: naming differs by platform convention:
    //   Linux  → librocksmith_shim.so  (lib prefix + lowercase, UNIX convention)
    //   Windows → RocksmithShim.dll    (PascalCase, no lib prefix, Windows convention)
    #[cfg_attr(target_os = "linux",   link(name = "rocksmith_shim", kind = "dylib"))]
    #[cfg_attr(target_os = "windows", link(name = "RocksmithShim",  kind = "dylib"))]
    extern "C" {
        pub fn rs_open_psarc(path: *const u8) -> *mut c_void;
        pub fn rs_get_notes_json(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
        pub fn rs_get_wem_bytes(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
        pub fn rs_close(handle: *mut c_void);
        pub fn rs_free_ptr(ptr: *mut u8);
    }
}

// ── RAII wrapper ──────────────────────────────────────────────────────────────

/// Opaque handle to a parsed PSARC.
pub struct PsarcHandle(*mut std::ffi::c_void);

impl PsarcHandle {
    /// Open a PSARC file at the given absolute path.
    /// Returns `None` on failure.
    /// On Windows, requires `RocksmithShim.dll` next to `godot_rocksmith.dll`.
    pub fn open(path: &str) -> Option<Self> {
        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            let cpath = CString::new(path).ok()?;
            let handle = unsafe { ffi::rs_open_psarc(cpath.as_ptr() as *const u8) };
            if handle.is_null() { None } else { Some(PsarcHandle(handle)) }
        }
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        {
            let _ = path;
            None
        }
    }

    /// Return the notes as a compact JSON string.
    pub fn notes_json(&self) -> Option<String> {
        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            let mut len: i32 = 0;
            let ptr = unsafe { ffi::rs_get_notes_json(self.0, &mut len) };
            if ptr.is_null() { return None; }
            let s = unsafe { CStr::from_ptr(ptr as *const i8) }
                .to_string_lossy()
                .into_owned();
            unsafe { ffi::rs_free_ptr(ptr) };
            Some(s)
        }
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        { None }
    }

    /// Return the raw WEM audio bytes.
    pub fn wem_bytes(&self) -> Option<Vec<u8>> {
        #[cfg(any(target_os = "linux", target_os = "windows"))]
        {
            let mut len: i32 = 0;
            let ptr = unsafe { ffi::rs_get_wem_bytes(self.0, &mut len) };
            if ptr.is_null() || len <= 0 { return None; }
            let slice = unsafe { std::slice::from_raw_parts(ptr, len as usize) };
            let owned = slice.to_vec();
            unsafe { ffi::rs_free_ptr(ptr) };
            Some(owned)
        }
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        { None }
    }
}

impl Drop for PsarcHandle {
    fn drop(&mut self) {
        #[cfg(any(target_os = "linux", target_os = "windows"))]
        if !self.0.is_null() {
            unsafe { ffi::rs_close(self.0) };
        }
    }
}
