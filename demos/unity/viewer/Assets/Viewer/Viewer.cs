using System;
using System.IO;
using System.Linq;
using UnityEngine;
namespace Papng {
public sealed class Viewer : MonoBehaviour {
    NativeDocument doc, child;
    string path = "", error = "", folder = "", address = "", dialog = "", filter = "";
    string[] entries = Array.Empty<string>();
    int fileTarget, maskIndex, socketIndex, clipIndex = -1, bgMode;
    bool mark, hints, sockets, editChild;
    Vector2 scroll, pan;
    float zoom = 8, bgScale = 1, bgAlpha = 1, bgX, bgY;
    Color bgColor = new Color(.13f, .14f, .17f);
    Texture2D checker, background, hueStrip;
    bool showBackground = true;
    float[] offsets = Array.Empty<float>(), childOffsets = Array.Empty<float>();
    float[] saturations = Array.Empty<float>(), childSaturations = Array.Empty<float>();
    float[] brightness = Array.Empty<float>(), childBrightness = Array.Empty<float>();
    Rect viewport;
    double lastTick;
    string maskSearch = "";
    bool fitted;
    float uiScale = 1;
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    static void Boot() { new GameObject("PAPNG Viewer").AddComponent<Viewer>(); }
    void Awake() {
        Application.targetFrameRate = 60;
        Application.runInBackground = true;
        checker = new Texture2D(2, 2) { filterMode = FilterMode.Point, wrapMode = TextureWrapMode.Repeat };
        checker.SetPixels(new[] { new Color(.22f, .23f, .26f), new Color(.3f, .31f, .34f),
                                  new Color(.3f, .31f, .34f), new Color(.22f, .23f, .26f) });
        checker.Apply();
        hueStrip = new Texture2D(360, 1) { filterMode = FilterMode.Bilinear };
        for (int i = 0; i < 360; i++)
            hueStrip.SetPixel(i, 0, Color.HSVToRGB(i / 360f, 1, 1));
        hueStrip.Apply();
        folder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrEmpty(folder))
            folder = Application.persistentDataPath;
        lastTick = Time.realtimeSinceStartupAsDouble;
        foreach (var arg in Environment.GetCommandLineArgs())
            if (File.Exists(arg) && IsImage(arg)) {
                Open(arg, 0);
                break;
            }
    }
    static bool IsImage(string p) =>
        new[] { ".papng", ".apng", ".png" }.Contains(Path.GetExtension(p).ToLowerInvariant());
    void Open(string file, int target) {
        try {
            if (target == 2) {
                byte[] b = File.ReadAllBytes(file);
                if (b.Length > 64 * 1024 * 1024)
                    throw new Exception("Background exceeds 64 MiB");
                var tex = new Texture2D(2, 2) { filterMode = FilterMode.Point };
                if (!tex.LoadImage(b) || tex.width * (long)tex.height > 32000000) {
                    Destroy(tex);
                    throw new Exception("Use a PNG or JPEG background up to 32 MP");
                }
                if (background != null)
                    Destroy(background);
                background = tex;
                showBackground = true;
                return;
            }
            var next = new NativeDocument(file);
            if (target == 1) {
                child?.Dispose();
                child = next;
                childOffsets = Array.Empty<float>();
            } else {
                doc?.Dispose();
                doc = next;
                child?.Dispose();
                child = null;
                path = file;
                offsets = Array.Empty<float>();
                maskIndex = socketIndex = 0;
                clipIndex = -1;
                fitted = false;
            }
            error = "";
        } catch (Exception e) {
            error = e.Message;
        }
    }
    void Update() {
        double now = Time.realtimeSinceStartupAsDouble;
        double dt = Math.Min(.25, now - lastTick);
        lastTick = now;
        doc?.Update(dt);
        if (child != null) {
            if (doc == null || !doc.Playing)
                child.Playing = false;
            child.Update(dt);
        }
        if (doc != null && doc.State.Width > 0 && !fitted) {
            Fit();
            fitted = true;
        }
        if (doc != null && offsets.Length != doc.State.Masks)
            { offsets = new float[doc.State.Masks]; saturations = new float[doc.State.Masks]; brightness = new float[doc.State.Masks]; }
        if (child != null && childOffsets.Length != child.State.Masks)
            { childOffsets = new float[child.State.Masks]; childSaturations = new float[child.State.Masks]; childBrightness = new float[child.State.Masks]; }
    }
    void OnDestroy() {
        doc?.Dispose();
        child?.Dispose();
        if (background != null)
            Destroy(background);
        if (checker != null)
            Destroy(checker);
        if (hueStrip != null)
            Destroy(hueStrip);
    }
    void Browser(int target) {
        fileTarget = target;
        dialog = "files";
        scroll = Vector2.zero;
        ReadFolder(folder);
    }
    void ReadFolder(string dir) {
        try {
            folder = Path.GetFullPath(dir);
            address = folder;
            entries =
                Directory.GetDirectories(folder)
                    .OrderBy(x => x)
                    .Concat(
                        Directory.GetFiles(folder)
                            .Where(p => fileTarget == 2
                                            ? new[] { ".png", ".jpg", ".jpeg", ".apng", ".papng" }.Contains(
                                                  Path.GetExtension(p).ToLowerInvariant())
                                            : IsImage(p))
                            .OrderBy(x => x))
                    .ToArray();
            error = "";
        } catch (Exception e) {
            error = e.Message;
        }
    }
    void Fit() {
        if (doc == null || doc.State.Width <= 0)
            return;
        zoom = Mathf.Max(.1f, Mathf.Min((Screen.width / uiScale - 40) / doc.State.Width,
                                        (Screen.height / uiScale - 130) / doc.State.Height));
        if (zoom >= 1)
            zoom = Mathf.Max(1, Mathf.Floor(zoom));
        pan = Vector2.zero;
    }
    void Play() {
        if (doc == null)
            return;
        bool playing = !doc.Playing;
        if (playing && doc.State.Ended) {
            doc.Restart(clipIndex);
            child?.Restart();
        }
        doc.Playing = playing;
        if (child != null)
            child.Playing = playing;
    }
    void Restart() {
        doc?.Restart(clipIndex);
        child?.Restart();
    }
    void Pause() {
        if (doc != null)
            doc.Playing = false;
        if (child != null)
            child.Playing = false;
    }
    bool Button(string label, float width = 0) =>
        width > 0? GUILayout.Button(label, GUILayout.Width(width), GUILayout.Height(30))
        : GUILayout.Button(label, GUILayout.Height(30));
    void OnGUI() {
        GUI.enabled = dialog == "";
        uiScale = Mathf.Max(1, Mathf.Min(Screen.width / 1000f, Screen.height / 650f));
        GUI.matrix = Matrix4x4.Scale(new Vector3(uiScale, uiScale, 1));
        float w = Screen.width / uiScale, h = Screen.height / uiScale;
        GUI.skin.button.fontSize = 14;
        GUI.skin.label.fontSize = 14;
        GUI.skin.label.richText = false;
        GUI.skin.textField.fontSize = 14;
        viewport = new Rect(0, 84, w, h - 114);
        GUILayout.BeginArea(new Rect(8, 6, w - 16, 76));
        GUILayout.BeginHorizontal();
        if (Button("Open  Ctrl+O"))
            Browser(0);
        if (Button(doc != null && doc.Playing ? "Pause  Space" : "Play  Space"))
            Play();
        if (Button("Restart"))
            Restart();
        if (Button("Step")) {
            Pause();
            doc?.Step();
        }
        if (Button("Colors  Ctrl+M")) {
            Pause();
            dialog = "masks";
            scroll = Vector2.zero;
        }
        mark = GUILayout.Toggle(mark, "Masks [M]", "Button", GUILayout.Height(30));
        hints = GUILayout.Toggle(hints, "Hints [H]", "Button", GUILayout.Height(30));
        sockets = GUILayout.Toggle(sockets, "Sockets [S]", "Button", GUILayout.Height(30));
        if (Button("Background"))
            dialog = "background";
        if (Button("Info"))
            dialog = "info";
        GUILayout.EndHorizontal();
        GUILayout.BeginHorizontal();
        if (Button("Fit [F]", 75))
            Fit();
        if (Button("1:1", 60)) {
            zoom = 1;
            pan = Vector2.zero;
        }
        if (Button("−", 40))
            zoom = Mathf.Max(.1f, zoom / 2);
        if (Button("+", 40))
            zoom = Mathf.Min(128, zoom * 2);
        GUILayout.Label($"{zoom:0.##}×", GUILayout.Width(65));
        if (Button("Attach…", 85))
            Browser(1);
        if (Button("Detach", 70)) {
            child?.Dispose();
            child = null;
        }
        if (doc != null && doc.State.Sockets.Length > 0 &&
            Button("Socket: " + doc.State.Sockets[Math.Min(socketIndex, doc.State.Sockets.Length - 1)])) {
            socketIndex = (socketIndex + 1) % doc.State.Sockets.Length;
        }
        if (doc != null &&
            Button("Clip: " + (clipIndex < 0 ? "Full animation" : doc.State.Clips[clipIndex]))) {
            clipIndex++;
            if (clipIndex >= doc.State.Clips.Length)
                clipIndex = -1;
            Restart();
        }
        GUILayout.EndHorizontal();
        GUILayout.EndArea();
        DrawCanvas();
        GUILayout.BeginArea(new Rect(10, h - 29, w - 20, 26));
        GUILayout.BeginHorizontal();
        if (doc != null) {
            GUILayout.Label(
                $"{Path.GetFileName(path)}  {doc.State.Width}×{doc.State.Height}  Frame {doc.State.Visible+1}/{doc.State.Frames}",
                GUILayout.Width(400));
            if (doc.State.Frames > 1) {
                int selected = Mathf.RoundToInt(
                    GUILayout.HorizontalSlider(Math.Max(0, doc.State.Visible), 0, doc.State.Frames - 1));
                if (selected != doc.State.Visible && doc.State.Visible >= 0) {
                    Pause();
                    doc.Seek(selected);
                }
            }
        }
        string message = error;
        if (message == "" && doc != null) message = doc.State.Error;
        if (message == "" && child != null && child.State.Error != "") message = "Accessory: " + child.State.Error;
        if (message == "" && doc?.Loading == true) message = "Loading…";
        if (message == "" && doc != null && doc.State.Warnings != "") message = "Warnings — see Info";
        GUILayout.Label(message);
        GUILayout.EndHorizontal();
        GUILayout.EndArea();
        GUI.enabled = true;
        if (dialog != "") {
            var modal = new Rect(Mathf.Max(10, (w - 650) / 2), 70, Mathf.Min(650, w - 20), h - 110);
            var tint = GUI.color;
            GUI.color = new Color(0, 0, 0, .55f);
            GUI.DrawTexture(new Rect(0, 0, w, h), Texture2D.whiteTexture);
            GUI.color = new Color(.12f, .13f, .16f, 1);
            GUI.DrawTexture(modal, Texture2D.whiteTexture);
            GUI.color = tint;
            GUILayout.BeginArea(new Rect(modal.x + 14, modal.y + 14, modal.width - 28, modal.height - 28));
            GUILayout.BeginHorizontal();
            GUILayout.Label(dialog.ToUpperInvariant());
            if (Button("Close", 75))
                dialog = "";
            GUILayout.EndHorizontal();
            if (dialog == "files")
                Files();
            else if (dialog == "masks")
                Masks();
            else if (dialog == "background")
                Background();
            else if (dialog == "info") {
                scroll = GUILayout.BeginScrollView(scroll);
                GUILayout.TextArea((doc?.State.Error ?? "") + "\n" + (doc?.State.Warnings ?? "") + "\n" +
                                   Preview(doc?.State.Metadata ?? ""));
                GUILayout.EndScrollView();
            }
            GUILayout.EndArea();
        } else
            InputEvents();
    }
    static string Preview(string text) => text.Length > 65536? text.Substring(0, 65536) +
                                                            "\n[Preview limited to 65536 characters]"
        : text;
    void Files() {
        GUILayout.BeginHorizontal();
        address = GUILayout.TextField(address, GUILayout.Height(28));
        if (Button("Go", 55))
            ReadFolder(address);
        if (Button("Up", 55)) {
            var parent = Directory.GetParent(folder);
            if (parent != null)
                ReadFolder(parent.FullName);
        }
        GUILayout.EndHorizontal();
        filter = GUILayout.TextField(filter);
        scroll = GUILayout.BeginScrollView(scroll);
        foreach (var e in entries) {
            if (!Path.GetFileName(e).Contains(filter, StringComparison.OrdinalIgnoreCase))
                continue;
            bool dir = Directory.Exists(e);
            if (Button((dir ? "▸ " : "   ") + Path.GetFileName(e))) {
                if (dir)
                    ReadFolder(e);
                else {
                    Open(e, fileTarget);
                    dialog = "";
                }
                break;
            }
        }
        GUILayout.EndScrollView();
        GUILayout.Label(error);
    }
    static Color Mean(uint v) => new Color(((v >> 24) & 255) / 255f, ((v >> 16) & 255) / 255f,
                                           ((v >> 8) & 255) / 255f, 1);
    void Swatch(Color c) {
        GUILayout.Space(6);
        var rect = GUILayoutUtility.GetRect(42, 42, GUILayout.Width(42));
        var old = GUI.color;
        GUI.color = c;
        GUI.DrawTexture(rect, Texture2D.whiteTexture);
        GUI.color = old;
    }
    void Masks() {
        if (child != null)
            editChild = GUILayout.Toggle(editChild, "Edit accessory masks");
        var d = editChild && child != null ? child : doc;
        var values = d == child ? childOffsets : offsets;
        var ds = d == child ? childSaturations : saturations;
        var dv = d == child ? childBrightness : brightness;
        if (d == null || d.State.Masks == 0) {
            GUILayout.Label("No masks in this image.");
            return;
        }
        maskIndex = Mathf.Clamp(maskIndex, 0, d.State.Masks - 1);
        maskSearch = GUILayout.TextField(maskSearch);
        scroll = GUILayout.BeginScrollView(scroll, GUILayout.Height(160));
        int shown = 0;
        for (int i = 0; i < d.State.Masks && shown < 128; i++) {
            if (!d.State.MaskNames[i].Contains(maskSearch, StringComparison.OrdinalIgnoreCase))
                continue;
            shown++;
            if (Button(d.State.MaskNames[i])) {
                maskIndex = i;
                Pause();
                d.Select(i);
                child?.Restart();
            }
        }
        GUILayout.EndScrollView();
        GUILayout.Label(d.State.MaskNames[maskIndex]);
        var original = Mean(d.State.Means[maskIndex]);
        Color.RGBToHSV(original, out float hue, out float sat, out float val);
        float offset = values[maskIndex];
        float newHue = Mathf.Repeat(hue + offset / 360, 1);
        GUILayout.BeginHorizontal();
        Swatch(original);
        Swatch(Color.HSVToRGB(newHue, Mathf.Clamp01(sat+ds[maskIndex]), Mathf.Clamp01(val+dv[maskIndex])));
        GUILayout.Label($"Original H {hue*360:0.0}°    Offset {offset:0.0}°");
        GUILayout.EndHorizontal();
        GUI.enabled = d.State.Means[maskIndex] != 0;
        Rect hueRect = GUILayoutUtility.GetRect(200, 28, GUILayout.ExpandWidth(true));
        GUI.DrawTexture(hueRect, hueStrip);
        float picked = newHue * 360;
        var evt = Event.current;
        if ((evt.type == EventType.MouseDown || evt.type == EventType.MouseDrag) &&
            hueRect.Contains(evt.mousePosition)) {
            picked = Mathf.Clamp01((evt.mousePosition.x - hueRect.x) / hueRect.width) * 360;
            evt.Use();
        }
        picked = GUILayout.HorizontalSlider(picked, 0, 360);
        float nextS = Slider("ΔS saturation", ds[maskIndex], -1, 1);
        float nextV = Slider("ΔV value", dv[maskIndex], -1, 1);
        if (Math.Abs(picked - newHue * 360) > .05 || nextS != ds[maskIndex] || nextV != dv[maskIndex]) {
            ds[maskIndex] = nextS; dv[maskIndex] = nextV;
            values[maskIndex] = picked - hue * 360;
            Pause();
            d.MaskHsv(maskIndex, values[maskIndex], ds[maskIndex], dv[maskIndex]);
            if (d == doc)
                child?.Restart();
            else
                doc?.Restart(clipIndex);
        }
        GUI.enabled = true;
        if (Button("Reset offset")) {
            values[maskIndex] = 0;
            Pause();
            ds[maskIndex] = dv[maskIndex] = 0;
            d.MaskHsv(maskIndex, 0, 0, 0);
            Restart();
        }
        if (Button("Highlight all masks")) {
            d.Select(-1);
            mark = true;
        }
        GUILayout.Label("HSV offsets preserve each pixel's alpha. S/V are additive, clamped to 0–1.\nClipping can reduce texture. Playback is " +
                        "paused and reconstruction restarts after edits.");
    }
    float Slider(string name, float v, float min, float max) {
        GUILayout.Label($"{name}: {v:0.##}");
        return GUILayout.HorizontalSlider(v, min, max);
    }
    void Background() {
        bgMode = GUILayout.SelectionGrid(bgMode, new[] { "Checker", "Solid" }, 2);
        bgColor.r = Slider("Red", bgColor.r, 0, 1);
        bgColor.g = Slider("Green", bgColor.g, 0, 1);
        bgColor.b = Slider("Blue", bgColor.b, 0, 1);
        if (Button("Load PNG / JPEG background…"))
            Browser(2);
        if (background == null)
            return;
        showBackground = GUILayout.Toggle(showBackground, "Show reference image");
        bgX = Number("X (source pixels)", bgX);
        bgY = Number("Y (source pixels)", bgY);
        bgScale = Number("Scale", bgScale, .001f, 10000);
        bgAlpha = Slider("Opacity", bgAlpha, 0, 1);
        if (Button("Fit background to canvas") && doc != null) {
            bgScale = Mathf.Min((float)doc.State.Width / background.width,
                                (float)doc.State.Height / background.height);
            bgX = (doc.State.Width - background.width * bgScale) / 2;
            bgY = (doc.State.Height - background.height * bgScale) / 2;
        }
        if (Button("Remove background")) {
            Destroy(background);
            background = null;
        }
    }
    float Number(string label, float value, float min = -1000000, float max = 1000000) {
        GUILayout.BeginHorizontal();
        GUILayout.Label(label);
        string raw = GUILayout.TextField(value.ToString(System.Globalization.CultureInfo.InvariantCulture));
        if (float.TryParse(raw, System.Globalization.NumberStyles.Float,
                           System.Globalization.CultureInfo.InvariantCulture, out var n) &&
            !float.IsNaN(n) && !float.IsInfinity(n))
            value = Mathf.Clamp(n, min, max);
        GUILayout.EndHorizontal();
        return value;
    }
    void Image(Rect r, Texture texture, float alpha = 1, bool flip = true) {
        if (texture == null)
            return;
        var old = GUI.color;
        GUI.color = new Color(1, 1, 1, alpha);
        GUI.DrawTextureWithTexCoords(r, texture, flip ? new Rect(0, 1, 1, -1) : new Rect(0, 0, 1, 1), true);
        GUI.color = old;
    }
    void Line(Vector2 a, Vector2 b, Color color, float thickness = 1) {
        var matrix = GUI.matrix;
        var old = GUI.color;
        GUI.color = color;
        GUIUtility.RotateAroundPivot(Vector2.SignedAngle(Vector2.right, b - a), a);
        GUI.DrawTexture(new Rect(a.x, a.y, (b - a).magnitude, thickness), Texture2D.whiteTexture);
        GUI.matrix = matrix;
        GUI.color = old;
    }
    void Cross(Vector2 p, string name, float rotation = 0) {
        Line(p - Vector2.right * 6, p + Vector2.right * 6, Color.cyan);
        Line(p - Vector2.up * 6, p + Vector2.up * 6, Color.cyan);
        float a = rotation * Mathf.Deg2Rad;
        Line(p, p + new Vector2(Mathf.Cos(a), Mathf.Sin(a)) * 22, Color.yellow, 2);
        GUI.Label(new Rect(p.x + 8, p.y - 20, 230, 24), name);
    }
    static bool PoseVisible(double[] p) => p != null && Math.Abs(p[0]) <= 1e10 && Math.Abs(p[1]) <= 1e10;
    void DrawCanvas() {
        GUI.BeginGroup(viewport);
        Rect local = new Rect(0, 0, viewport.width, viewport.height);
        var old = GUI.color;
        if (bgMode == 0)
            GUI.DrawTextureWithTexCoords(local, checker, new Rect(0, 0, local.width / 24, local.height / 24));
        else {
            GUI.color = bgColor;
            GUI.DrawTexture(local, Texture2D.whiteTexture);
            GUI.color = old;
        }
        if (doc != null && doc.State.Width > 0) {
            var origin = new Vector2((local.width - doc.State.Width * zoom) / 2,
                                     (local.height - doc.State.Height * zoom) / 2) +
                         pan;
            Rect r = new Rect(origin, new Vector2(doc.State.Width, doc.State.Height) * zoom);
            if (background != null && showBackground)
                Image(new Rect(origin + new Vector2(bgX, bgY) * zoom,
                               new Vector2(background.width, background.height) * bgScale *zoom),
                      background, bgAlpha, false);
            Image(r, doc.Image);
            if (mark)
                Image(r, doc.Highlight, .65f);
            if (child?.Image != null && socketIndex < doc.State.Poses.Length &&
                PoseVisible(doc.State.Poses[socketIndex])) {
                var pose = doc.State.Poses[socketIndex];
                var pivot = child.State.Hints[3] ?? new double[4];
                var anchor = origin + new Vector2((float)pose[0], (float)pose[1]) * zoom;
                var saved = GUI.matrix;
                GUIUtility.RotateAroundPivot((float)(pose[2] % 360), anchor);
                Image(new Rect(anchor - new Vector2((float)pivot[0], (float)pivot[1]) * zoom,
                               new Vector2(child.State.Width, child.State.Height) * zoom),
                      child.Image);
                GUI.matrix = saved;
            }
            if (hints) {
                Line(r.min, new Vector2(r.xMax, r.yMin), Color.green);
                Line(r.min, new Vector2(r.xMin, r.yMax), Color.green);
                Line(r.max, new Vector2(r.xMax, r.yMin), Color.green);
                Line(r.max, new Vector2(r.xMin, r.yMax), Color.green);
                var p = doc.State.Hints[3];
                if (p != null)
                    Cross(origin + new Vector2((float)p[0], (float)p[1]) * zoom, "Pivot");
                var b = doc.State.Hints[1];
                if (b != null) {
                    var a = origin + new Vector2((float)b[0], (float)b[1]) * zoom;
                    var z = a + new Vector2((float)b[2], (float)b[3]) * zoom;
                    Line(a, new Vector2(z.x, a.y), Color.yellow);
                    Line(a, new Vector2(a.x, z.y), Color.yellow);
                    Line(z, new Vector2(z.x, a.y), Color.yellow);
                    Line(z, new Vector2(a.x, z.y), Color.yellow);
                }
                var display = doc.State.Hints[0];
                var scale = doc.State.Hints[2];
                GUI.Label(
                    new Rect(8, 8, 600, 28),
                    $"Output: {(display==null?"unspecified":display[0]+" × "+display[1])}   Pixel multiple: {(scale==null?"unspecified":scale[0].ToString())}");
            }
            if (sockets)
                for (int i = 0; i < doc.State.Poses.Length; i++) {
                    var p = doc.State.Poses[i];
                    if (PoseVisible(p))
                        Cross(origin + new Vector2((float)p[0], (float)p[1]) * zoom, doc.State.Sockets[i],
                              (float)(p[2] % 360));
                }
        } else
            GUI.Label(new Rect(30, 40, 500, 50), "Open a PAPNG, APNG or PNG image to begin.");
        GUI.EndGroup();
    }
    void InputEvents() {
        var e = Event.current;
        if (e.type == EventType.ScrollWheel && viewport.Contains(e.mousePosition)) {
            zoom = Mathf.Clamp(zoom * Mathf.Pow(1.15f, -e.delta.y), .1f, 128);
            e.Use();
        }
        if (e.type == EventType.MouseDrag && viewport.Contains(e.mousePosition)) {
            pan += e.delta;
            e.Use();
        }
        if (e.type != EventType.KeyDown)
            return;
        bool ctrl = e.control || e.command;
        if (ctrl && e.keyCode == KeyCode.O)
            Browser(0);
        else if (ctrl && e.keyCode == KeyCode.M) {
            Pause();
            dialog = "masks";
        } else if (ctrl && e.keyCode == KeyCode.B)
            dialog = "background";
        else if (ctrl && e.keyCode == KeyCode.L)
            Browser(1);
        else if (e.keyCode == KeyCode.Space)
            Play();
        else if (e.keyCode == KeyCode.Home)
            Restart();
        else if (e.keyCode == KeyCode.RightArrow) {
            Pause();
            doc?.Step();
        } else if (e.keyCode == KeyCode.M)
            mark = !mark;
        else if (e.keyCode == KeyCode.H)
            hints = !hints;
        else if (e.keyCode == KeyCode.S)
            sockets = !sockets;
        else if (e.keyCode == KeyCode.F)
            Fit();
        else if (e.keyCode == KeyCode.Alpha1) {
            zoom = 1;
            pan = Vector2.zero;
        }
    }
}
}
