/// rs_net_ffi.rs — .NET CLR hosting bridge for Rocksmith2014.NET.
///
/// Architecture (no NativeAOT, no shim DLL):
///
///   Rust (godot_rocksmith)
///     → netcorehost (find + load hostfxr)
///       → .NET CLR (runtime loaded in-process)
///         → RocksmithBridge.dll (regular managed .NET 9.0)
///           → Rocksmith2014.PSARC.dll / Rocksmith2014.SNG.dll (F#)
///
/// The Rust code uses `netcorehost::nethost::load_hostfxr()` to locate the
/// .NET runtime, then calls `load_assembly_and_get_function_pointer` to obtain
/// raw function pointers to the [UnmanagedCallersOnly] methods in Exports.cs.
///
/// The managed DLLs (RocksmithBridge.dll, Rocksmith2014.*.dll, FSharp.Core.dll)
/// and RocksmithBridge.runtimeconfig.json must be in the same directory as the
/// Rust GDExtension binary (gdextension/bin/).

use std::ffi::{c_void, CStr, CString};
use std::path::PathBuf;
use std::sync::OnceLock;

use netcorehost::nethost;
use netcorehost::pdcstring::PdCString;

// ── Function pointer types matching Exports.cs signatures ─────────────────────

type FnOpenPsarc     = unsafe extern "C" fn(path_utf8: *const u8) -> *mut c_void;
type FnGetNotesJson  = unsafe extern "C" fn(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
type FnGetWemBytes   = unsafe extern "C" fn(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
type FnClose         = unsafe extern "C" fn(handle: *mut c_void);
type FnFreePtr       = unsafe extern "C" fn(ptr: *mut u8);

struct BridgeFns {
    open_psarc:     FnOpenPsarc,
    get_notes_json: FnGetNotesJson,
    get_wem_bytes:  FnGetWemBytes,
    close:          FnClose,
    free_ptr:       FnFreePtr,
}

// SAFETY: function pointers are thread-safe once loaded.
unsafe impl Send for BridgeFns {}
unsafe impl Sync for BridgeFns {}

static BRIDGE: OnceLock<Result<BridgeFns, String>> = OnceLock::new();

fn init_bridge() -> Result<BridgeFns, String> {
    let bin_dir = locate_bin_dir()?;
    let config_path = bin_dir.join("RocksmithBridge.runtimeconfig.json");

    eprintln!("[rs_net_ffi] loading hostfxr...");
    let hostfxr = nethost::load_hostfxr()
        .map_err(|e| format!("load_hostfxr failed: {e}"))?;

    eprintln!("[rs_net_ffi] initializing runtime: {}", config_path.display());
    let ctx = hostfxr
        .initialize_for_runtime_config(
            PdCString::from_os_str(config_path.as_os_str())
                .map_err(|e| format!("config path: {e}"))?,
        )
        .map_err(|e| format!("initialize_for_runtime_config: {e}"))?;

    let loader = ctx.get_delegate_loader()
        .map_err(|e| format!("get_delegate_loader: {e}"))?;

    let type_name = PdCString::from_str("RocksmithBridge.Exports, RocksmithBridge")
        .map_err(|e| format!("type name: {e}"))?;

    // Helper: load one [UnmanagedCallersOnly] method by name.
    let load = |method: &str| -> Result<*const (), String> {
        let mname = PdCString::from_str(method)
            .map_err(|e| format!("method name '{method}': {e}"))?;
        unsafe {
            loader.get_function_pointer_for_unmanaged_callers_only_method::<fn()>(
                type_name.clone(),
                mname,
            )
        }
        .map(|f| f as *const ())
        .map_err(|e| format!("get_function_pointer '{method}': {e}"))
    };

    eprintln!("[rs_net_ffi] loading RocksmithBridge.Exports function pointers...");
    let fns = BridgeFns {
        open_psarc:     unsafe { std::mem::transmute(load("OpenPsarc")?) },
        get_notes_json: unsafe { std::mem::transmute(load("GetNotesJson")?) },
        get_wem_bytes:  unsafe { std::mem::transmute(load("GetWemBytes")?) },
        close:          unsafe { std::mem::transmute(load("Close")?) },
        free_ptr:       unsafe { std::mem::transmute(load("FreePtr")?) },
    };
    eprintln!("[rs_net_ffi] RocksmithBridge loaded OK");
    Ok(fns)
}

/// Find the directory that contains the GDExtension binary at runtime.
fn locate_bin_dir() -> Result<PathBuf, String> {
    #[cfg(target_os = "linux")]
    {
        // Read /proc/self/maps to find this .so
        if let Ok(maps) = std::fs::read_to_string("/proc/self/maps") {
            for line in maps.lines() {
                if line.contains("libgodot_rocksmith") {
                    if let Some(path) = line.split_whitespace().last() {
                        if let Some(parent) = std::path::Path::new(path).parent() {
                            eprintln!("[rs_net_ffi] bin_dir: {}", parent.display());
                            return Ok(parent.to_path_buf());
                        }
                    }
                }
            }
        }
    }

    // Fallback: look for gdextension/bin relative to CWD
    let cwd = std::env::current_dir()
        .map_err(|e| format!("current_dir: {e}"))?;
    let candidate = cwd.join("gdextension").join("bin");
    if candidate.exists() {
        eprintln!("[rs_net_ffi] bin_dir (cwd/gdextension/bin): {}", candidate.display());
        return Ok(candidate);
    }
    eprintln!("[rs_net_ffi] bin_dir fallback (cwd): {}", cwd.display());
    Ok(cwd)
}

fn bridge() -> Option<&'static BridgeFns> {
    BRIDGE.get_or_init(init_bridge).as_ref().map_or_else(
        |e| { eprintln!("[rs_net_ffi] bridge init error: {e}"); None },
        Some,
    )
}

// ── RAII handle ────────────────────────────────────────────────────────────────

pub struct PsarcHandle { ptr: *mut c_void }
unsafe impl Send for PsarcHandle {}

impl PsarcHandle {
    pub fn open(path: &str) -> Option<Self> {
        let fns = bridge()?;
        let cpath = CString::new(path).ok()?;
        let ptr = unsafe { (fns.open_psarc)(cpath.as_ptr() as *const u8) };
        if ptr.is_null() { None } else { Some(PsarcHandle { ptr }) }
    }

    pub fn notes_json(&self) -> Option<String> {
        let fns = bridge()?;
        let mut len: i32 = 0;
        let ptr = unsafe { (fns.get_notes_json)(self.ptr, &mut len) };
        if ptr.is_null() { return None; }
        let s = unsafe { CStr::from_ptr(ptr as *const i8) }.to_string_lossy().into_owned();
        unsafe { (fns.free_ptr)(ptr) };
        Some(s)
    }

    pub fn wem_bytes(&self) -> Option<Vec<u8>> {
        let fns = bridge()?;
        let mut len: i32 = 0;
        let ptr = unsafe { (fns.get_wem_bytes)(self.ptr, &mut len) };
        if ptr.is_null() || len <= 0 { return None; }
        let owned = unsafe { std::slice::from_raw_parts(ptr, len as usize) }.to_vec();
        unsafe { (fns.free_ptr)(ptr) };
        Some(owned)
    }
}

impl Drop for PsarcHandle {
    fn drop(&mut self) {
        if let (Some(fns), false) = (bridge(), self.ptr.is_null()) {
            unsafe { (fns.close)(self.ptr) };
        }
    }
}
