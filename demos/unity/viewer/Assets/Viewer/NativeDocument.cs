using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.IO;
using UnityEngine;
namespace Papng {
public sealed class NativeDocument : IDisposable {
    const string Library = "papng";
    [DllImport(Library)]
    internal static extern IntPtr pp_open(byte[] b, int length);
    [DllImport(Library)]
    internal static extern void pp_close(IntPtr h);
    [DllImport(Library)]
    internal static extern IntPtr pp_error(IntPtr h);
    [DllImport(Library)]
    internal static extern IntPtr pp_warnings(IntPtr h);
    [DllImport(Library)]
    internal static extern IntPtr pp_metadata(IntPtr h);
    [DllImport(Library)]
    internal static extern int pp_get(IntPtr h, int field);
    [DllImport(Library)]
    internal static extern IntPtr pp_pixels(IntPtr h);
    [DllImport(Library)]
    internal static extern IntPtr pp_marks(IntPtr h);
    [DllImport(Library)]
    internal static extern void pp_tick(IntPtr h, double seconds);
    [DllImport(Library)]
    internal static extern void pp_step(IntPtr h);
    [DllImport(Library)]
    internal static extern void pp_restart(IntPtr h, int clip);
    [DllImport(Library)]
    internal static extern void pp_seek(IntPtr h, int frame);
    [DllImport(Library)]
    internal static extern void pp_mask(IntPtr h, int index, double degrees);
    [DllImport(Library)]
    internal static extern void pp_mask_hsv(IntPtr h, int index, double degrees, double saturation, double value);
    [DllImport(Library)]
    internal static extern void pp_select_mask(IntPtr h, int index);
    [DllImport(Library)]
    internal static extern IntPtr pp_name(IntPtr h, int kind, int index);
    [DllImport(Library)]
    internal static extern int pp_socket(IntPtr h, int index, [Out] double[] xyz);
    [DllImport(Library)]
    internal static extern int pp_hint(IntPtr h, int kind, [Out] double[] values);
    [DllImport(Library)]
    internal static extern uint pp_mean(IntPtr h, int index);
    static string Text(IntPtr p) => Marshal.PtrToStringUTF8(p) ?? "";
    public sealed class View {
        public int Width, Height, Frames, Masks, Visible = -1, Revision = -1;
        public bool Ended;
        public string Error = "", Warnings = "", Metadata = "";
        public string[] MaskNames = Array.Empty<string>(), Sockets = Array.Empty<string>(),
                        Clips = Array.Empty<string>();
        public uint[] Means = Array.Empty<uint>();
        public double[][] Hints = new double [4][], Poses = Array.Empty<double[]>();
        public byte[] Pixels, Marks;
    }
    double accumulated;
    IntPtr handle;
    Task<View> pending;
    readonly ConcurrentQueue<Action<IntPtr>> queue = new ConcurrentQueue<Action<IntPtr>>();
    bool disposed;
    public View State = new View();
    public bool Ready => handle != IntPtr.Zero && pending == null && State.Error == "";
    public bool Loading => State.Width == 0 && State.Error == "";
    public bool Playing = true;
    public int Clip = -1;
    public Texture2D Image, Highlight;
    public NativeDocument(string path) {
        pending = Task.Run(() => {
            try {
                var info = new FileInfo(path);
                if (info.Length > 128 * 1024 * 1024)
                    throw new Exception("File exceeds 128 MiB");
                byte[] bytes = File.ReadAllBytes(path);
                handle = pp_open(bytes, bytes.Length);
                return Capture(true);
            } catch (Exception e) {
                return new View { Error = e.Message };
            }
        });
    }
    View Capture(bool initial = false) {
        var v = new View { Width = pp_get(handle, 0),           Height = pp_get(handle, 1),
                           Frames = pp_get(handle, 2),          Masks = pp_get(handle, 3),
                           Visible = pp_get(handle, 4),         Ended = pp_get(handle, 5) != 0,
                           Revision = pp_get(handle, 6),        Error = Text(pp_error(handle)),
                           Warnings = Text(pp_warnings(handle)) };
        if (initial && v.Error == "") {
            v.Metadata = Text(pp_metadata(handle));
            v.MaskNames = new string[v.Masks];
            v.Means = new uint[v.Masks];
            for (int i = 0; i < v.Masks; i++) {
                v.MaskNames[i] = Text(pp_name(handle, 0, i));
                v.Means[i] = pp_mean(handle, i);
            }
            v.Sockets = new string[pp_get(handle, 7)];
            for (int i = 0; i < v.Sockets.Length; i++)
                v.Sockets[i] = Text(pp_name(handle, 1, i));
            v.Clips = new string[pp_get(handle, 8)];
            for (int i = 0; i < v.Clips.Length; i++)
                v.Clips[i] = Text(pp_name(handle, 2, i));
            for (int i = 0; i < 4; i++) {
                double[] h = new double[4];
                if (pp_hint(handle, i, h) != 0)
                    v.Hints[i] = h;
            }
        }
        v.Poses = new double [pp_get(handle, 7)][];
        for (int i = 0; i < v.Poses.Length; i++) {
            double[] p = new double[3];
            if (pp_socket(handle, i, p) != 0)
                v.Poses[i] = p;
        }
        if (initial || v.Revision != State.Revision) {
            int n = checked(v.Width * v.Height * 4);
            var p = pp_pixels(handle);
            if (p != IntPtr.Zero) {
                v.Pixels = new byte[n];
                v.Marks = new byte[n];
                Marshal.Copy(p, v.Pixels, 0, n);
                Marshal.Copy(pp_marks(handle), v.Marks, 0, n);
            }
        }
        return v;
    }
    public void Update(double elapsed) {
        if (disposed)
            return;
        if (Playing)
            accumulated += elapsed;
        else accumulated = 0;
        if (pending != null) {
            if (!pending.IsCompleted)
                return;
            View v;
            try {
                v = pending.GetAwaiter().GetResult();
            } catch (Exception e) {
                v = new View { Error = e.Message };
            }
            pending = null;
            if (State.Width == 0) accumulated = 0;
            if (State.Width != 0) {
                v.Metadata = State.Metadata;
                v.MaskNames = State.MaskNames;
                v.Means = State.Means;
                v.Sockets = State.Sockets;
                v.Clips = State.Clips;
                v.Hints = State.Hints;
            }
            if (v.Revision != State.Revision) {
                Upload(ref Image, v.Width, v.Height, v.Pixels);
                Upload(ref Highlight, v.Width, v.Height, v.Marks);
            }
            State = v;
            if (v.Ended || v.Error != "")
                Playing = false;
        }
        if (handle != IntPtr.Zero && State.Error == "" && (Playing || !queue.IsEmpty)) {
            bool play = Playing;
            double delta = accumulated;
            accumulated = 0;
            pending = Task.Run(() => {
                while (queue.TryDequeue(out var action))
                    action(handle);
                if (play)
                    pp_tick(handle, delta);
                return Capture();
            });
        }
    }
    static void Upload(ref Texture2D texture, int w, int h, byte[] pixels) {
        if (pixels == null) {
            if (texture != null)
                UnityEngine.Object.Destroy(texture);
            texture = null;
            return;
        }
        if (texture == null || texture.width != w || texture.height != h) {
            if (texture != null)
                UnityEngine.Object.Destroy(texture);
            texture = new Texture2D(w, h, TextureFormat.RGBA32, false) { filterMode = FilterMode.Point,
                                                                         wrapMode = TextureWrapMode.Clamp };
        }
        texture.LoadRawTextureData(pixels);
        texture.Apply(false, false);
    }
    public void Restart(int clip = -1) {
        Clip = clip;
        queue.Enqueue(h => pp_restart(h, clip));
    }
    public void Seek(int f) {
        Playing = false;
        queue.Enqueue(h => pp_seek(h, f));
    }
    public void Step() {
        Playing = false;
        queue.Enqueue(h => pp_step(h));
    }
    public void Mask(int index, float degrees) {
        Playing = false;
        queue.Enqueue(h => pp_mask(h, index, degrees));
    }
    public void MaskHsv(int index, float degrees, float saturation, float value) {
        Playing = false;
        queue.Enqueue(h => pp_mask_hsv(h, index, degrees, saturation, value));
    }
    public void Select(int index) {
        Playing = false;
        queue.Enqueue(h => pp_select_mask(h, index));
    }
    public void Dispose() {
        if (disposed)
            return;
        disposed = true;
        if (Image != null)
            UnityEngine.Object.Destroy(Image);
        if (Highlight != null)
            UnityEngine.Object.Destroy(Highlight);
        if (pending != null)
            pending.ContinueWith(
                _ => {
                    if (handle != IntPtr.Zero)
                        pp_close(handle);
                });
        else if (handle != IntPtr.Zero)
            pp_close(handle);
    }
}
}
