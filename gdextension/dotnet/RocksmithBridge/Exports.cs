// Exports.cs — C-ABI bridge for the Rust GDExtension.
//
// This is a REGULAR managed .NET class library (NOT NativeAOT).
// The Rust GDExtension loads it at runtime via the .NET component hosting API:
//   hostfxr → load_assembly_and_get_function_pointer → [UnmanagedCallersOnly] method
//
// Exported functions (called from Rust via CLR function pointers):
//   rs_open_psarc(path_utf8)        → opaque GCHandle (null on error)
//   rs_get_notes_json(handle, &len) → heap-allocated UTF-8 JSON (free with rs_free_ptr)
//   rs_get_wem_bytes(handle, &len)  → heap-allocated raw WEM bytes (free with rs_free_ptr)
//   rs_close(handle)                → free the opaque handle
//   rs_free_ptr(ptr)                → free a heap buffer returned above
//
// The [UnmanagedCallersOnly] attribute marks methods that can be called via
// unmanaged function pointers.  This works with both NativeAOT (pre-compiled)
// AND the CLR hosting API (JIT-compiled at runtime).  Here we use the CLR
// hosting approach — no ahead-of-time compilation needed.

using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.FSharp.Control;
using Microsoft.FSharp.Core;
using Rocksmith2014.PSARC;
using Rocksmith2014.SNG;
using RsPlatform    = Rocksmith2014.Common.Platform;
using RsSngModule   = Rocksmith2014.SNG.SNGModule;

namespace RocksmithBridge;

/// <summary>Data stored behind the GCHandle returned to Rust.</summary>
internal sealed class PsarcResult
{
    public string  NotesJson { get; init; } = "[]";
    public byte[]? WemBytes  { get; init; }
}

/// <summary>
/// C-ABI exports loaded by the Rust GDExtension via netcorehost.
/// </summary>
public static unsafe class Exports
{
    // ── rs_open_psarc ────────────────────────────────────────────────────────

    /// <summary>
    /// Open a .psarc file at <paramref name="pathUtf8"/>, parse the
    /// highest-difficulty lead arrangement and extract the first .wem file.
    /// Returns an opaque GCHandle cast to void*, or null on failure.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_open_psarc")]
    public static void* OpenPsarc(byte* pathUtf8)
    {
        try
        {
            string path = Marshal.PtrToStringUTF8((nint)pathUtf8)
                          ?? throw new ArgumentNullException(nameof(pathUtf8));

            using var psarc = PSARC.OpenFile(path);

            // ── Find the lead-guitar SNG (prefer "_lead.sng") ─────────────
            string? sngName = null;
            foreach (var name in psarc.Manifest)
            {
                if (name.EndsWith("_lead.sng", StringComparison.OrdinalIgnoreCase))
                { sngName = name; break; }
                if (sngName == null && name.EndsWith(".sng", StringComparison.OrdinalIgnoreCase))
                    sngName = name;
            }

            string notesJson = "[]";
            if (sngName != null)
            {
                Console.Error.WriteLine($"[RocksmithBridge] parsing arrangement '{sngName}'");
                using var sngStream = psarc.GetEntryStream(sngName).GetAwaiter().GetResult();
                var sng = FSharpAsync.RunSynchronously(
                    RsSngModule.fromStream(sngStream, RsPlatform.PC),
                    FSharpOption<int>.None,
                    FSharpOption<System.Threading.CancellationToken>.None);
                notesJson = BuildNotesJson(sng);
            }

            // ── Find first .wem file ──────────────────────────────────────
            byte[]? wemBytes = null;
            foreach (var name in psarc.Manifest)
            {
                if (!name.EndsWith(".wem", StringComparison.OrdinalIgnoreCase)) continue;
                Console.Error.WriteLine($"[RocksmithBridge] extracting WEM '{name}'");
                using var wemStream = psarc.GetEntryStream(name).GetAwaiter().GetResult();
                using var ms = new MemoryStream();
                wemStream.CopyTo(ms);
                wemBytes = ms.ToArray();
                Console.Error.WriteLine($"[RocksmithBridge] extracted {wemBytes.Length} WEM bytes");
                break;
            }

            var result = new PsarcResult { NotesJson = notesJson, WemBytes = wemBytes };
            var handle = GCHandle.Alloc(result, GCHandleType.Normal);
            return (void*)GCHandle.ToIntPtr(handle);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[RocksmithBridge] rs_open_psarc error: {ex}");
            return null;
        }
    }

    // ── rs_get_notes_json ─────────────────────────────────────────────────────

    /// <summary>
    /// Returns a heap-allocated null-terminated UTF-8 JSON string.
    /// *<paramref name="outLen"/> is set to the byte count (excluding null).
    /// Caller must free with rs_free_ptr.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_get_notes_json")]
    public static byte* GetNotesJson(void* handle, int* outLen)
    {
        try
        {
            return MarshalUtf8(GetResult(handle).NotesJson, outLen);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[RocksmithBridge] rs_get_notes_json error: {ex.Message}");
            if (outLen != null) *outLen = 0;
            return null;
        }
    }

    // ── rs_get_wem_bytes ──────────────────────────────────────────────────────

    /// <summary>
    /// Returns a heap-allocated byte array with raw WEM audio bytes.
    /// *<paramref name="outLen"/> is set to the byte count.
    /// Caller must free with rs_free_ptr.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_get_wem_bytes")]
    public static byte* GetWemBytes(void* handle, int* outLen)
    {
        try
        {
            var b = GetResult(handle).WemBytes;
            if (b is null || b.Length == 0) { if (outLen != null) *outLen = 0; return null; }
            if (outLen != null) *outLen = b.Length;
            var ptr = (byte*)NativeMemory.Alloc((nuint)b.Length);
            b.AsSpan().CopyTo(new Span<byte>(ptr, b.Length));
            return ptr;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[RocksmithBridge] rs_get_wem_bytes error: {ex.Message}");
            if (outLen != null) *outLen = 0;
            return null;
        }
    }

    // ── rs_close ──────────────────────────────────────────────────────────────

    [UnmanagedCallersOnly(EntryPoint = "rs_close")]
    public static void Close(void* handle)
    {
        if (handle == null) return;
        try { GCHandle.FromIntPtr((nint)handle).Free(); } catch { }
    }

    // ── rs_free_ptr ───────────────────────────────────────────────────────────

    [UnmanagedCallersOnly(EntryPoint = "rs_free_ptr")]
    public static void FreePtr(void* ptr)
    {
        if (ptr != null) NativeMemory.Free(ptr);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static PsarcResult GetResult(void* handle)
    {
        if (handle == null) throw new ArgumentNullException("handle");
        return (PsarcResult)GCHandle.FromIntPtr((nint)handle).Target!;
    }

    private static byte* MarshalUtf8(string s, int* outLen)
    {
        var bytes = Encoding.UTF8.GetBytes(s);
        var ptr   = (byte*)NativeMemory.Alloc((nuint)(bytes.Length + 1));
        bytes.AsSpan().CopyTo(new Span<byte>(ptr, bytes.Length));
        ptr[bytes.Length] = 0;
        if (outLen != null) *outLen = bytes.Length;
        return ptr;
    }

    // ── JSON builder ──────────────────────────────────────────────────────────

    private static string BuildNotesJson(SNG sng)
    {
        if (sng.Levels.Length == 0) return "[]";
        var level = sng.Levels[sng.Levels.Length - 1];
        var notes = level.Notes;
        if (notes.Length == 0) return "[]";

        var sb = new StringBuilder("[");
        for (int i = 0; i < notes.Length; i++)
        {
            var n = notes[i];
            if (i > 0) sb.Append(',');
            sb.Append("{\"time\":");
            sb.Append(n.Time.ToString("G", System.Globalization.CultureInfo.InvariantCulture));
            sb.Append(",\"fret\":");
            sb.Append((int)n.Fret);
            sb.Append(",\"string\":");
            sb.Append((int)n.StringIndex);
            sb.Append(",\"duration\":");
            sb.Append(n.Sustain.ToString("G", System.Globalization.CultureInfo.InvariantCulture));
            sb.Append('}');
        }
        sb.Append(']');
        return sb.ToString();
    }
}
