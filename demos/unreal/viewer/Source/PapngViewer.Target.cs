using UnrealBuildTool;
public class PapngViewerTarget : TargetRules {
    public PapngViewerTarget(TargetInfo Target) : base(Target) {
        Type = TargetType.Game;
        DefaultBuildSettings = BuildSettingsVersion.V7;
        IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
        ExtraModuleNames.AddRange(new[] { "PapngViewer", "PapngCore" });
    }
}
