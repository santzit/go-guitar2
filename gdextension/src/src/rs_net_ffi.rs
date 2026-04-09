/// rs_net_ffi.rs — Rust FFI bindings for PSARC/SNG parsing.
///
/// Linux: librocksmith_shim.so (C# NativeAOT) is linked at build time.
///
/// Windows (two-tier fallback — no user build steps required):
///   1. RocksmithShim.dll  — NativeAOT, loaded via LoadLibraryA at runtime.
///      Build once: cd gdextension/dotnet/RocksmithShim
///                  dotnet publish -c Release -r win-x64
///                  copy bin\Release\net10.0\win-x64\publish\RocksmithShim.dll ..\..\..\gdextension\bin\
///   2. CLR hosting  — if RocksmithShim.dll is absent, the code automatically
///      falls back to loading RocksmithBridge.dll (managed .NET, already in
///      gdextension/bin/) via the hostfxr / load_assembly_and_get_function_pointer
///      API.  The .NET runtime must be installed on the user's machine but no
///      additional build steps are needed.
///
/// All memory returned by the C functions must be freed with rs_free_ptr.
/// The opaque handle returned by rs_open_psarc must be freed with rs_close.

use std::ffi::{CString, CStr, c_void};

// ── Linux: link librocksmith_shim.so at build time ───────────────────────────

#[cfg(target_os = "linux")]
#[link(name = "rocksmith_shim", kind = "dylib")]
extern "C" {
    fn rs_open_psarc(path: *const u8) -> *mut c_void;
    fn rs_get_notes_json(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
    fn rs_get_wem_bytes(handle: *mut c_void, out_len: *mut i32) -> *mut u8;
    fn rs_close(handle: *mut c_void);
    fn rs_free_ptr(ptr: *mut u8);
}

// ── Windows: runtime loading — RocksmithShim.dll (NativeAOT) first,
//            then CLR hosting with RocksmithBridge.dll as fallback ─────────────

#[cfg(target_os = "windows")]
mod win_shim {
    use std::ffi::{c_void};
    use std::path::PathBuf;
    use std::sync::OnceLock;

    pub type FnOpenPsarc    = unsafe extern "C" fn(*const u8) -> *mut c_void;
    pub type FnGetNotesJson = unsafe extern "C" fn(*mut c_void, *mut i32) -> *mut u8;
    pub type FnGetWemBytes  = unsafe extern "C" fn(*mut c_void, *mut i32) -> *mut u8;
    pub type FnClose        = unsafe extern "C" fn(*mut c_void);
    pub type FnFreePtr      = unsafe extern "C" fn(*mut u8);

    pub struct ShimFns {
        pub open_psarc:     FnOpenPsarc,
        pub get_notes_json: FnGetNotesJson,
        pub get_wem_bytes:  FnGetWemBytes,
        pub close:          FnClose,
        pub free_ptr:       FnFreePtr,
    }
    unsafe impl Send for ShimFns {}
    unsafe impl Sync for ShimFns {}

    // ── Windows API ───────────────────────────────────────────────────────────
    extern "system" {
        fn LoadLibraryA(lp: *const u8) -> *mut c_void;
        fn LoadLibraryW(lp: *const u16) -> *mut c_void;
        fn GetProcAddress(h: *mut c_void, name: *const u8) -> *mut c_void;
        fn GetModuleHandleExW(flags: u32, lp: *const u16, ph: *mut *mut c_void) -> i32;
        fn GetModuleFileNameW(h: *mut c_void, buf: *mut u16, n: u32) -> u32;
    }

    fn get_proc(lib: *mut c_void, name: &[u8]) -> Option<*mut c_void> {
        let p = unsafe { GetProcAddress(lib, name.as_ptr()) };
        if p.is_null() { None } else { Some(p) }
    }

    fn to_wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    // ── Get directory of this DLL ─────────────────────────────────────────────
    fn dll_dir() -> Option<PathBuf> {
        // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT
        let flags = 4u32 | 2u32;
        let mut h: *mut c_void = std::ptr::null_mut();
        let ok = unsafe { GetModuleHandleExW(flags, dll_dir as *const fn() as *const u16, &mut h) };
        if ok == 0 { return None; }
        let mut buf = [0u16; 520];
        let len = unsafe { GetModuleFileNameW(h, buf.as_mut_ptr(), buf.len() as u32) } as usize;
        if len == 0 { return None; }
        let path = String::from_utf16_lossy(&buf[..len]);
        PathBuf::from(path).parent().map(|p| p.to_path_buf())
    }

    fn find_in_dll_dir(filename: &str) -> Option<PathBuf> {
        let dir = dll_dir()?;
        let candidate = dir.join(filename);
        if candidate.exists() { Some(candidate) } else { None }
    }

    // ── Tier 1: RocksmithShim.dll (NativeAOT) ────────────────────────────────
    fn try_native_shim() -> Option<ShimFns> {
        let lib = unsafe { LoadLibraryA(b"RocksmithShim.dll\0".as_ptr()) };
        if lib.is_null() { return None; }
        eprintln!("[rs_net_ffi] Loaded RocksmithShim.dll (NativeAOT)");
        Some(ShimFns {
            open_psarc:     unsafe { std::mem::transmute(get_proc(lib, b"rs_open_psarc\0")?) },
            get_notes_json: unsafe { std::mem::transmute(get_proc(lib, b"rs_get_notes_json\0")?) },
            get_wem_bytes:  unsafe { std::mem::transmute(get_proc(lib, b"rs_get_wem_bytes\0")?) },
            close:          unsafe { std::mem::transmute(get_proc(lib, b"rs_close\0")?) },
            free_ptr:       unsafe { std::mem::transmute(get_proc(lib, b"rs_free_ptr\0")?) },
        })
    }

    // ── Tier 2: CLR hosting via RocksmithBridge.dll ───────────────────────────
    // hostfxr delegate type constants
    const HDT_LOAD_ASSEMBLY_AND_GET_FP: i32 = 5;
    // Sentinel for [UnmanagedCallersOnly] methods in load_assembly_and_get_function_pointer
    const UNMANAGEDCALLERSONLY_METHOD: *const u16 = usize::MAX as *const u16;

    type FnHostfxrInitForRtConfig = unsafe extern "C" fn(*const u16, *const c_void, *mut *mut c_void) -> i32;
    type FnHostfxrGetRtDelegate   = unsafe extern "C" fn(*mut c_void, i32, *mut *mut c_void) -> i32;
    type FnHostfxrClose           = unsafe extern "C" fn(*mut c_void) -> i32;
    type FnLoadAssemblyAndGetFnPtr = unsafe extern "C" fn(*const u16, *const u16, *const u16, *const u16, *const c_void, *mut *mut c_void) -> i32;

    fn find_hostfxr() -> Option<PathBuf> {
        // Check DOTNET_ROOT env var
        if let Ok(root) = std::env::var("DOTNET_ROOT") {
            if let Some(p) = scan_fxr_dir(&PathBuf::from(root).join("host").join("fxr")) {
                return Some(p);
            }
        }
        // Standard install paths
        for base in &["C:\\Program Files\\dotnet", "C:\\Program Files (x86)\\dotnet"] {
            if let Some(p) = scan_fxr_dir(&PathBuf::from(base).join("host").join("fxr")) {
                return Some(p);
            }
        }
        None
    }

    fn scan_fxr_dir(fxr_dir: &PathBuf) -> Option<PathBuf> {
        let mut entries: Vec<_> = std::fs::read_dir(fxr_dir).ok()?
            .filter_map(|e| e.ok())
            .filter(|e| e.path().is_dir())
            .collect();
        entries.sort_by_key(|e| e.file_name());
        for entry in entries.iter().rev() {
            let c = entry.path().join("hostfxr.dll");
            if c.exists() { return Some(c); }
        }
        None
    }

    fn try_clr_hosting() -> Option<ShimFns> {
        // Find RocksmithBridge.runtimeconfig.json next to this DLL
        let rtcfg  = find_in_dll_dir("RocksmithBridge.runtimeconfig.json")?;
        let bridge = find_in_dll_dir("RocksmithBridge.dll")?;

        // Load hostfxr
        let hostfxr_path = find_hostfxr()?;
        let hostfxr_wide = to_wide(hostfxr_path.to_str()?);
        let hfxr = unsafe { LoadLibraryW(hostfxr_wide.as_ptr()) };
        if hfxr.is_null() { return None; }

        let init_fn: FnHostfxrInitForRtConfig = unsafe {
            std::mem::transmute(get_proc(hfxr, b"hostfxr_initialize_for_runtime_config\0")?)
        };
        let get_del_fn: FnHostfxrGetRtDelegate = unsafe {
            std::mem::transmute(get_proc(hfxr, b"hostfxr_get_runtime_delegate\0")?)
        };
        let close_fn: FnHostfxrClose = unsafe {
            std::mem::transmute(get_proc(hfxr, b"hostfxr_close\0")?)
        };

        let rtcfg_wide = to_wide(rtcfg.to_str()?);
        let mut host_ctx: *mut c_void = std::ptr::null_mut();
        let rc = unsafe { init_fn(rtcfg_wide.as_ptr(), std::ptr::null(), &mut host_ctx) };
        if rc < 0 {
            eprintln!("[rs_net_ffi] hostfxr_initialize_for_runtime_config failed: {rc:#x}");
            return None;
        }

        let mut load_fn_raw: *mut c_void = std::ptr::null_mut();
        let rc = unsafe { get_del_fn(host_ctx, HDT_LOAD_ASSEMBLY_AND_GET_FP, &mut load_fn_raw) };
        if rc < 0 || load_fn_raw.is_null() {
            eprintln!("[rs_net_ffi] hostfxr_get_runtime_delegate failed: {rc:#x}");
            unsafe { close_fn(host_ctx); }
            return None;
        }
        let load_fn: FnLoadAssemblyAndGetFnPtr = unsafe { std::mem::transmute(load_fn_raw) };

        let bridge_wide = to_wide(bridge.to_str()?);
        let type_name   = to_wide("RocksmithBridge.Exports, RocksmithBridge");

        let get_fp = |method: &str| -> Option<*mut c_void> {
            let method_wide = to_wide(method);
            let mut fp: *mut c_void = std::ptr::null_mut();
            let rc = unsafe {
                load_fn(bridge_wide.as_ptr(), type_name.as_ptr(), method_wide.as_ptr(),
                        UNMANAGEDCALLERSONLY_METHOD, std::ptr::null(), &mut fp)
            };
            if rc == 0 && !fp.is_null() { Some(fp) } else {
                eprintln!("[rs_net_ffi] load_assembly_and_get_function_pointer({method}) failed: {rc:#x}");
                None
            }
        };

        let fns = ShimFns {
            open_psarc:     unsafe { std::mem::transmute(get_fp("OpenPsarc")?) },
            get_notes_json: unsafe { std::mem::transmute(get_fp("GetNotesJson")?) },
            get_wem_bytes:  unsafe { std::mem::transmute(get_fp("GetWemBytes")?) },
            close:          unsafe { std::mem::transmute(get_fp("Close")?) },
            free_ptr:       unsafe { std::mem::transmute(get_fp("FreePtr")?) },
        };
        unsafe { close_fn(host_ctx); }
        eprintln!("[rs_net_ffi] CLR hosting ready (RocksmithBridge.dll)");
        Some(fns)
    }

    fn try_load() -> Option<ShimFns> {
        try_native_shim().or_else(try_clr_hosting)
    }

    static SHIM: OnceLock<Option<ShimFns>> = OnceLock::new();

    pub fn get() -> Option<&'static ShimFns> {
        SHIM.get_or_init(try_load).as_ref()
    }
}

// ── RAII wrapper — Linux (static link) and Windows (runtime) ─────────────────

#[cfg(any(target_os = "linux", target_os = "windows"))]
pub struct PsarcHandle(*mut c_void);

#[cfg(any(target_os = "linux", target_os = "windows"))]
impl PsarcHandle {
    /// Open a PSARC file at the given absolute path.  Returns `None` on failure.
    pub fn open(path: &str) -> Option<Self> {
        let cpath = CString::new(path).ok()?;
        #[cfg(target_os = "linux")]
        let handle = unsafe { rs_open_psarc(cpath.as_ptr() as *const u8) };
        #[cfg(target_os = "windows")]
        let handle = win_shim::get()
            .map(|s| unsafe { (s.open_psarc)(cpath.as_ptr() as *const u8) })
            .unwrap_or(std::ptr::null_mut());
        if handle.is_null() { None } else { Some(PsarcHandle(handle)) }
    }

    /// Return the notes as a compact JSON string.
    pub fn notes_json(&self) -> Option<String> {
        let mut len: i32 = 0;
        #[cfg(target_os = "linux")]
        let ptr = unsafe { rs_get_notes_json(self.0, &mut len) };
        #[cfg(target_os = "windows")]
        let ptr = win_shim::get()
            .map(|s| unsafe { (s.get_notes_json)(self.0, &mut len) })
            .unwrap_or(std::ptr::null_mut());
        if ptr.is_null() { return None; }
        let s = unsafe { CStr::from_ptr(ptr as *const i8) }
            .to_string_lossy()
            .into_owned();
        #[cfg(target_os = "linux")]
        unsafe { rs_free_ptr(ptr) };
        #[cfg(target_os = "windows")]
        if let Some(sh) = win_shim::get() { unsafe { (sh.free_ptr)(ptr) }; }
        Some(s)
    }

    /// Return the raw WEM audio bytes.
    pub fn wem_bytes(&self) -> Option<Vec<u8>> {
        let mut len: i32 = 0;
        #[cfg(target_os = "linux")]
        let ptr = unsafe { rs_get_wem_bytes(self.0, &mut len) };
        #[cfg(target_os = "windows")]
        let ptr = win_shim::get()
            .map(|s| unsafe { (s.get_wem_bytes)(self.0, &mut len) })
            .unwrap_or(std::ptr::null_mut());
        if ptr.is_null() || len <= 0 { return None; }
        let owned = unsafe { std::slice::from_raw_parts(ptr, len as usize) }.to_vec();
        #[cfg(target_os = "linux")]
        unsafe { rs_free_ptr(ptr) };
        #[cfg(target_os = "windows")]
        if let Some(sh) = win_shim::get() { unsafe { (sh.free_ptr)(ptr) }; }
        Some(owned)
    }
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
impl Drop for PsarcHandle {
    fn drop(&mut self) {
        if !self.0.is_null() {
            #[cfg(target_os = "linux")]
            unsafe { rs_close(self.0) };
            #[cfg(target_os = "windows")]
            if let Some(sh) = win_shim::get() { unsafe { (sh.close)(self.0) }; }
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
