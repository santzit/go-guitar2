// Exports.cs — C-ABI exports for the RocksmithShim NativeAOT library.
//
// This shim wraps iminashi/Rocksmith2014.NET (PSARC + SNG) and exposes a
// minimal C API consumed by the Rust GDExtension via extern "C" FFI.
//
// Exported functions:
//   rs_open_psarc(path)       → opaque handle (null on error)
//   rs_get_notes_json(handle) → heap-allocated UTF-8 JSON string
//   rs_get_wem_bytes(handle)  → heap-allocated raw WEM bytes
//   rs_close(handle)          → free the opaque handle
//   rs_free_ptr(ptr)          → free a heap allocation returned above
//
// All pointers returned by rs_get_notes_json / rs_get_wem_bytes must be
// released by calling rs_free_ptr.  The data is owned by the caller after
// the call returns.

using System.Runtime.InteropServices;
using System.Text;
using Microsoft.FSharp.Control;
using Microsoft.FSharp.Core;
using Rocksmith2014.PSARC;
using Rocksmith2014.SNG;
using RsPlatform = Rocksmith2014.Common.Platform;
using RsSngModule = Rocksmith2014.SNG.SNGModule;

/// <summary>Opaque result stored behind the GCHandle returned to Rust.</summary>
internal sealed class PsarcResult
{
    public string  NotesJson  { get; init; } = "[]";
    public byte[]? WemBytes   { get; init; }
}

/// <summary>C-ABI exports for the Rust GDExtension.</summary>
public static unsafe class Exports
{
    // ── rs_open_psarc ────────────────────────────────────────────────────────

    /// <summary>
    /// Open a .psarc file, parse the highest-difficulty lead arrangement and
    /// extract the first .wem file.
    /// Returns an opaque GCHandle integer cast to void*, or null on failure.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_open_psarc")]
    public static void* OpenPsarc(byte* pathUtf8)
    {
        try
        {
            string path = Marshal.PtrToStringUTF8((nint)pathUtf8)
                          ?? throw new ArgumentNullException("path");

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
                using var wemStream = psarc.GetEntryStream(name).GetAwaiter().GetResult();
                using var ms = new MemoryStream((int)wemStream.Length);
                wemStream.CopyTo(ms);
                wemBytes = ms.ToArray();
                break;
            }

            var result = new PsarcResult { NotesJson = notesJson, WemBytes = wemBytes };
            var handle = GCHandle.Alloc(result, GCHandleType.Normal);
            return (void*)GCHandle.ToIntPtr(handle);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[RocksmithShim] rs_open_psarc error: {ex}");
            return null;
        }
    }

    // ── rs_get_notes_json ────────────────────────────────────────────────────

    /// <summary>
    /// Returns a heap-allocated null-terminated UTF-8 JSON string with the
    /// notes array, e.g.: [{"time":1.5,"fret":7,"string":3,"duration":0.1}]
    /// Caller must free with rs_free_ptr.  Returns null on failure.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_get_notes_json")]
    public static byte* GetNotesJson(void* handle, int* outLen)
    {
        try
        {
            var result = GetResult(handle);
            return MarshalUtf8(result.NotesJson, outLen);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[RocksmithShim] rs_get_notes_json error: {ex.Message}");
            if (outLen != null) *outLen = 0;
            return null;
        }
    }

    // ── rs_get_wem_bytes ─────────────────────────────────────────────────────

    /// <summary>
    /// Returns a heap-allocated byte array with raw WEM audio bytes.
    /// *outLen is set to the byte count.  Returns null if none found.
    /// Caller must free with rs_free_ptr.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_get_wem_bytes")]
    public static byte* GetWemBytes(void* handle, int* outLen)
    {
        try
        {
            var result = GetResult(handle);
            if (result.WemBytes is null || result.WemBytes.Length == 0)
            {
                if (outLen != null) *outLen = 0;
                return null;
            }
            if (outLen != null) *outLen = result.WemBytes.Length;
            var ptr = (byte*)NativeMemory.Alloc((nuint)result.WemBytes.Length);
            result.WemBytes.AsSpan().CopyTo(new Span<byte>(ptr, result.WemBytes.Length));
            return ptr;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[RocksmithShim] rs_get_wem_bytes error: {ex.Message}");
            if (outLen != null) *outLen = 0;
            return null;
        }
    }

    // ── rs_close ─────────────────────────────────────────────────────────────

    /// <summary>Free the opaque handle returned by rs_open_psarc.</summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_close")]
    public static void Close(void* handle)
    {
        if (handle == null) return;
        try
        {
            var gcHandle = GCHandle.FromIntPtr((nint)handle);
            gcHandle.Free();
        }
        catch { /* ignore double-free */ }
    }

    // ── rs_free_ptr ──────────────────────────────────────────────────────────

    /// <summary>
    /// Free a byte buffer previously returned by rs_get_notes_json or
    /// rs_get_wem_bytes.
    /// </summary>
    [UnmanagedCallersOnly(EntryPoint = "rs_free_ptr")]
    public static void FreePtr(void* ptr)
    {
        if (ptr != null) NativeMemory.Free(ptr);
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static PsarcResult GetResult(void* handle)
    {
        if (handle == null) throw new ArgumentNullException("handle");
        var gcHandle = GCHandle.FromIntPtr((nint)handle);
        return (PsarcResult)gcHandle.Target!;
    }

    private static byte* MarshalUtf8(string s, int* outLen)
    {
        var bytes = Encoding.UTF8.GetBytes(s);
        var total = bytes.Length + 1; // null terminator
        var ptr   = (byte*)NativeMemory.Alloc((nuint)total);
        bytes.AsSpan().CopyTo(new Span<byte>(ptr, bytes.Length));
        ptr[bytes.Length] = 0;
        if (outLen != null) *outLen = bytes.Length;
        return ptr;
    }

    // ── JSON builder ─────────────────────────────────────────────────────────

    /// <summary>
    /// Builds a compact JSON array from the highest-difficulty level's notes.
    /// Format: [{"time":1.5,"fret":7,"string":3,"duration":0.12},...]
    /// </summary>
    private static string BuildNotesJson(SNG sng)
    {
        if (sng.Levels.Length == 0) return "[]";

        // Use the last (highest difficulty) level
        var level = sng.Levels[sng.Levels.Length - 1];
        var notes = level.Notes;
        if (notes.Length == 0) return "[]";

        var sb = new StringBuilder("[");
        for (int i = 0; i < notes.Length; i++)
        {
            var n = notes[i];
            if (i > 0) sb.Append(',');
            // Use InvariantCulture-safe formatting (G format = no locale separators)
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
