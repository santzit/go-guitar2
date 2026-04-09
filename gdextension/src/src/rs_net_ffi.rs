/// rs_net_ffi.rs — Rust FFI bindings for the RocksmithShim NativeAOT library.
///
/// The C# shim (gdextension/dotnet/RocksmithShim/) is compiled with NativeAOT:
///   Linux:   dotnet publish -c Release -r linux-x64  -> librocksmith_shim.so
///   Windows: dotnet publish -c Release -r win-x64    -> RocksmithShim.dll
///
/// Place the output next to the GDExtension binary in gdextension/bin/.
///
/// All memory returned by the C functions (notes JSON, WEM bytes) is owned by
/// the caller after the call and must be freed with `rs_free_ptr`.
/// The opaque handle returned by `rs_open_psarc` must be freed with `rs_close`.

use std::ffi::{CString, CStr, c_void};

// ── Linux FFI block ───────────────────────────────────────────────────────────

#[cfg(target_os = "linux")]
#[link(name = "rocksmith_shim", kind = "dylib")]
extern "C" {
    fn rs_open_psarc(path: *const u8) -> *mut c_void;
    fn rs_get_notes_json(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
    fn rs_get_wem_bytes(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
    fn rs_close(handle: *mut c_void);
    fn rs_free_ptr(ptr: *mut u8);
}

// ── Windows FFI block — RocksmithShim.dll (NativeAOT, same C API) ────────────

#[cfg(target_os = "windows")]
#[link(name = "RocksmithShim", kind = "dylib")]
extern "C" {
    fn rs_open_psarc(path: *const u8) -> *mut c_void;
    fn rs_get_notes_json(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
    fn rs_get_wem_bytes(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
    fn rs_close(handle: *mut c_void);
    fn rs_free_ptr(ptr: *mut u8);
}

// ── RAII wrapper ──────────────────────────────────────────────────────────────

/// Opaque handle to a parsed PSARC.
#[cfg(any(target_os = "linux", target_os = "windows"))]
pub struct PsarcHandle(*mut c_void);

#[cfg(any(target_os = "linux", target_os = "windows"))]
impl PsarcHandle {
    /// Open a PSARC file at the given absolute path.  Returns `None` on failure.
    pub fn open(path: &str) -> Option<Self> {
        let cpath = CString::new(path).ok()?;
        let handle = unsafe { rs_open_psarc(cpath.as_ptr() as *const u8) };
        if handle.is_null() { None } else { Some(PsarcHandle(handle)) }
    }

    /// Return the notes as a compact JSON string.
    pub fn notes_json(&self) -> Option<String> {
        let mut len: i32 = 0;
        let ptr = unsafe { rs_get_notes_json(self.0, &mut len) };
        if ptr.is_null() { return None; }
        let s = unsafe { CStr::from_ptr(ptr as *const i8) }
            .to_string_lossy()
            .into_owned();
        unsafe { rs_free_ptr(ptr) };
        Some(s)
    }

    /// Return the raw WEM audio bytes.
    pub fn wem_bytes(&self) -> Option<Vec<u8>> {
        let mut len: i32 = 0;
        let ptr = unsafe { rs_get_wem_bytes(self.0, &mut len) };
        if ptr.is_null() || len <= 0 { return None; }
        let owned = unsafe { std::slice::from_raw_parts(ptr, len as usize) }.to_vec();
        unsafe { rs_free_ptr(ptr) };
        Some(owned)
    }
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
impl Drop for PsarcHandle {
    fn drop(&mut self) {
        if !self.0.is_null() {
            unsafe { rs_close(self.0) };
        }
    }
}

// ── Stub for unsupported platforms ───────────────────────────────────────────

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
pub struct PsarcHandle;

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
impl PsarcHandle {
    pub fn open(_path: &str) -> Option<Self> { None }
    pub fn notes_json(&self) -> Option<String> { None }
    pub fn wem_bytes(&self) -> Option<Vec<u8>> { None }
}
