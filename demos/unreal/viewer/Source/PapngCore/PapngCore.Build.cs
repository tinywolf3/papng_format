using UnrealBuildTool;
using System.IO;
public class PapngCore : ModuleRules {
    public PapngCore(ReadOnlyTargetRules Target) : base(Target) {
        PCHUsage = PCHUsageMode.NoPCHs;
        bUseUnity = false;
        bEnableExceptions = true;
        PublicDependencyModuleNames.Add("Core");
        string Shared = Path.GetFullPath(Path.Combine(ModuleDirectory, "../../../../shared/papng"));
        if (Directory.Exists(Path.Combine(ModuleDirectory, "../../Native/papng")))
            Shared = Path.Combine(ModuleDirectory, "../../Native/papng");
        PublicIncludePaths.Add(Shared);
        ExternalDependencies.Add(Path.Combine(Shared, "papng.cpp"));
        ExternalDependencies.Add(Path.Combine(Shared, "json5.hpp"));
        ExternalDependencies.Add(Path.Combine(Shared, "third_party/stb_image.h"));
    }
}
