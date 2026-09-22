using System;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
public static class BuildViewer {
    public static void Build() {
        var platform = Environment.GetEnvironmentVariable("PAPNG_PLATFORM") ?? "linux";
        var output = Environment.GetEnvironmentVariable("PAPNG_OUTPUT");
        if (string.IsNullOrEmpty(output))
            throw new Exception("PAPNG_OUTPUT is required");
        var target = platform == "windows" ? BuildTarget.StandaloneWindows64 : BuildTarget.StandaloneLinux64;
        PlayerSettings.companyName = "Tiny Games";
        PlayerSettings.productName = "PAPNG Unity Viewer";
        PlayerSettings.bundleVersion = "0.1.0";
        PlayerSettings.defaultScreenWidth = 1200;
        PlayerSettings.defaultScreenHeight = 800;
        PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
        PlayerSettings.resizableWindow = true;
        PlayerSettings.runInBackground = true;
        PlayerSettings.colorSpace = ColorSpace.Gamma;
        PlayerSettings.SetScriptingBackend(UnityEditor.Build.NamedBuildTarget.Standalone,
                                           ScriptingImplementation.Mono2x);

        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
        var camera = new GameObject("Camera").AddComponent<Camera>();
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = Color.black;
        EditorSceneManager.SaveScene(scene, "Assets/Viewer.unity");
        var report = BuildPipeline.BuildPlayer(
            new BuildPlayerOptions { scenes = new[] { "Assets/Viewer.unity" }, locationPathName = output,
                                     target = target, options = BuildOptions.StrictMode });
        if (report.summary.result != BuildResult.Succeeded)
            throw new Exception("Build failed: " + report.summary.result);
    }
}
