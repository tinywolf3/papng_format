using UnrealBuildTool;
public class PapngViewer : ModuleRules {
    public PapngViewer(ReadOnlyTargetRules Target) : base(Target) {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.AddRange(new[] { "Core", "CoreUObject", "Engine", "InputCore", "Slate",
                                                     "SlateCore", "ApplicationCore", "RenderCore", "RHI",
                                                     "ImageWrapper", "AppFramework", "PapngCore" });
    }
}
