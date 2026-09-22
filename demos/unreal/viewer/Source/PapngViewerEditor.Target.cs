using UnrealBuildTool;
public class PapngViewerEditorTarget : TargetRules {
    public PapngViewerEditorTarget(TargetInfo Target) : base(Target) {
        Type = TargetType.Editor;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.AddRange(new[] { "PapngViewer", "PapngCore" });
    }
}
