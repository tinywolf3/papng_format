#pragma once
#include "Async/Async.h"
#include "CoreMinimal.h"
#include "Misc/FileHelper.h"
#include "HAL/FileManager.h"
#include "Engine/Texture2D.h"
#include "UObject/StrongObjectPtr.h"
#include "papng.h"
struct FPapngView {
    int Width = 0, Height = 0, Frames = 0, Masks = 0, Visible = -1, Revision = -1;
    bool Ended = false;
    FString Error, Warnings, Metadata;
    TArray<FString> MaskNames, Sockets, Clips;
    TArray<uint32> Means;
    TArray<TArray<double>> Hints, Poses;
    TArray<uint8> Pixels, Marks;
};
struct FNativeHandle {
    void *Value = nullptr;
    ~FNativeHandle() { pp_close(Value); }
};
class FDocument {
    TSharedPtr<FNativeHandle, ESPMode::ThreadSafe> Handle = MakeShared<FNativeHandle, ESPMode::ThreadSafe>();
    TFuture<FPapngView> Pending;
    TArray<TFunction<void(void *)>> Commands;
    double Accumulated = 0;
    static FPapngView Capture(void *H, int Revision, bool Initial) {
        FPapngView V;
        V.Width = pp_get(H, 0);
        V.Height = pp_get(H, 1);
        V.Frames = pp_get(H, 2);
        V.Masks = pp_get(H, 3);
        V.Visible = pp_get(H, 4);
        V.Ended = pp_get(H, 5) != 0;
        V.Revision = pp_get(H, 6);
        V.Error = UTF8_TO_TCHAR(pp_error(H));
        V.Warnings = UTF8_TO_TCHAR(pp_warnings(H));
        if (Initial && V.Error.IsEmpty()) {
            V.Metadata = UTF8_TO_TCHAR(pp_metadata(H));
            for (int I = 0; I < V.Masks; I++) {
                V.MaskNames.Add(UTF8_TO_TCHAR(pp_name(H, 0, I)));
                V.Means.Add(pp_mean(H, I));
            }
            for (int I = 0; I < pp_get(H, 7); I++)
                V.Sockets.Add(UTF8_TO_TCHAR(pp_name(H, 1, I)));
            for (int I = 0; I < pp_get(H, 8); I++)
                V.Clips.Add(UTF8_TO_TCHAR(pp_name(H, 2, I)));
            V.Hints.SetNum(4);
            for (int I = 0; I < 4; I++) {
                double Values[4];
                if (pp_hint(H, I, Values))
                    V.Hints[I].Append(Values, 4);
            }
        }
        for (int I = 0; I < pp_get(H, 7); I++) {
            double P[3];
            TArray<double> Pose;
            if (pp_socket(H, I, P))
                Pose.Append(P, 3);
            V.Poses.Add(MoveTemp(Pose));
        }
        if (V.Error.IsEmpty() && (Initial || V.Revision != Revision)) {
            auto Pixels = pp_pixels(H);
            if (Pixels) {
                int N = V.Width * V.Height * 4;
                V.Pixels.Append(Pixels, N);
                V.Marks.Append(pp_marks(H), N);
            }
        }
        return V;
    }
    static void Upload(TStrongObjectPtr<UTexture2D> &Texture, int W, int H, const TArray<uint8> &Bytes) {
        if (Bytes.IsEmpty()) {
            Texture.Reset();
            return;
        }
        if (!Texture.IsValid() || Texture->GetSizeX() != W || Texture->GetSizeY() != H) {
            Texture.Reset(UTexture2D::CreateTransient(W, H, PF_R8G8B8A8));
            Texture->Filter = TF_Nearest;
            Texture->SRGB = true;
            Texture->NeverStream = true;
        }
        auto &Mip = Texture->GetPlatformData()->Mips[0];
        void *Target = Mip.BulkData.Lock(LOCK_READ_WRITE);
        FMemory::Memcpy(Target, Bytes.GetData(), Bytes.Num());
        Mip.BulkData.Unlock();
        Texture->UpdateResource();
    }

  public:
    FPapngView State;
    TStrongObjectPtr<UTexture2D> Image, Highlight;
    bool Playing = true;
    int Clip = -1;
    TArray<float> Offsets, SaturationOffsets, ValueOffsets;
    explicit FDocument(const FString &Path) {
        auto Shared = Handle;
        Pending = Async(EAsyncExecution::ThreadPool, [Shared, Path]() {
            TArray<uint8> Bytes;
            FPapngView V;
            auto Size = IFileManager::Get().FileSize(*Path);
            if (Size < 0 || Size > 128 * 1024 * 1024 || !FFileHelper::LoadFileToArray(Bytes, *Path)) {
                V.Error = TEXT("Cannot read image (128 MiB limit)");
                return V;
            }
            Shared->Value = pp_open(Bytes.GetData(), Bytes.Num());
            return Capture(Shared->Value, -1, true);
        });
    }
    void Update(double Dt) {
        if (Playing)
            Accumulated += Dt;
        else Accumulated = 0;
        if (Pending.IsValid()) {
            if (!Pending.IsReady())
                return;
            auto V = Pending.Get();
            Pending = TFuture<FPapngView>();
            if (!State.Width) Accumulated = 0;
            if (State.Width) {
                V.Metadata = MoveTemp(State.Metadata);
                V.MaskNames = MoveTemp(State.MaskNames);
                V.Means = MoveTemp(State.Means);
                V.Sockets = MoveTemp(State.Sockets);
                V.Clips = MoveTemp(State.Clips);
                V.Hints = MoveTemp(State.Hints);
            }
            if (V.Revision != State.Revision) {
                Upload(Image, V.Width, V.Height, V.Pixels);
                Upload(Highlight, V.Width, V.Height, V.Marks);
            }
            V.Pixels.Empty();
            V.Marks.Empty();
            State = MoveTemp(V);
            if (State.Ended || !State.Error.IsEmpty())
                Playing = false;
            Offsets.SetNumZeroed(State.Masks);
            SaturationOffsets.SetNumZeroed(State.Masks);
            ValueOffsets.SetNumZeroed(State.Masks);
        }
        if (!Pending.IsValid() && Handle->Value && State.Error.IsEmpty() && (Playing || Commands.Num())) {
            auto Shared = Handle;
            auto Work = MoveTemp(Commands);
            int Revision = State.Revision;
            bool Play = Playing;
            double Delta = Accumulated;
            Accumulated = 0;
            Pending = Async(EAsyncExecution::ThreadPool,
                            [Shared, Work = MoveTemp(Work), Revision, Play, Delta]() mutable {
                                for (auto &Fn : Work)
                                    Fn(Shared->Value);
                                if (Play)
                                    pp_tick(Shared->Value, Delta);
                                return Capture(Shared->Value, Revision, false);
                            });
        }
    }
    void Restart(int Which = -1) {
        Clip = Which;
        Commands.Add([Which](void *H) { pp_restart(H, Which); });
    }
    void Seek(int Frame) {
        Playing = false;
        Commands.Add([Frame](void *H) { pp_seek(H, Frame); });
    }
    void Step() {
        Playing = false;
        Commands.Add([](void *H) { pp_step(H); });
    }
    void Mask(int Index, float Degrees) {
        Playing = false;
        Offsets[Index] = Degrees;
        Commands.Add([Index, Degrees](void *H) { pp_mask(H, Index, Degrees); });
    }
    void MaskHsv(int Index, float Degrees, float Saturation, float Value) {
        if (!Offsets.IsValidIndex(Index)) return;
        Playing = false;
        Offsets[Index] = Degrees;
        SaturationOffsets[Index] = FMath::Clamp(Saturation, -1.f, 1.f);
        ValueOffsets[Index] = FMath::Clamp(Value, -1.f, 1.f);
        Commands.Add([Index, Degrees, Saturation, Value](void *H) { pp_mask_hsv(H, Index, Degrees, Saturation, Value); });
    }
    void Select(int Index) {
        Playing = false;
        Commands.Add([Index](void *H) { pp_select_mask(H, Index); });
    }
};
