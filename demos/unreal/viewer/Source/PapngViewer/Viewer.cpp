#include "Brushes/SlateColorBrush.h"
#include "Document.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Framework/Application/SlateApplication.h"
#include "GameFramework/PlayerController.h"
#include "HAL/FileManager.h"
#include "IImageWrapper.h"
#include "IImageWrapperModule.h"
#include "ImageUtils.h"
#include "Input/DragAndDrop.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Modules/ModuleManager.h"
#include "Rendering/DrawElements.h"
#include "Styling/CoreStyle.h"
#include "ViewerMode.h"
#include "Widgets/Colors/SColorPicker.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SEditableTextBox.h"
#include "Widgets/Input/SSlider.h"
#include "Widgets/Input/SSpinBox.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SWrapBox.h"
#include "Widgets/SCompoundWidget.h"
#include "Widgets/SLeafWidget.h"
#include "Widgets/Text/SMultiLineEditableText.h"
#include "Widgets/Text/STextBlock.h"
IMPLEMENT_PRIMARY_GAME_MODULE(FDefaultGameModuleImpl, PapngViewer, "PapngViewer");
class SViewer;
class SImageArea : public SLeafWidget {
  public:
    SLATE_BEGIN_ARGS(SImageArea) {}
    SLATE_ARGUMENT(SViewer *, Owner) SLATE_END_ARGS() SViewer *Owner = nullptr;
    void Construct(const FArguments &Args) {
        Owner = Args._Owner;
        SetClipping(EWidgetClipping::ClipToBounds);
    }
    virtual FVector2D ComputeDesiredSize(float) const override { return FVector2D(600, 400); }
    virtual int32 OnPaint(const FPaintArgs &, const FGeometry &, const FSlateRect &,
                          FSlateWindowElementList &, int32, const FWidgetStyle &, bool) const override;
    virtual FReply OnMouseWheel(const FGeometry &, const FPointerEvent &) override;
    virtual FReply OnMouseButtonDown(const FGeometry &, const FPointerEvent &) override;
    virtual FReply OnMouseButtonUp(const FGeometry &, const FPointerEvent &) override {
        return FReply::Handled().ReleaseMouseCapture();
    }
    virtual FReply OnMouseMove(const FGeometry &, const FPointerEvent &) override;
};
class SViewer : public SCompoundWidget {
  public:
    SLATE_BEGIN_ARGS(SViewer) {}
    SLATE_END_ARGS()
    TUniquePtr<FDocument> Doc, Child;
    TSharedPtr<SImageArea> Canvas;
    TSharedPtr<SVerticalBox> Panel;
    TSharedPtr<SBox> PanelBox;
    TSharedPtr<SEditableTextBox> Address;
    TStrongObjectPtr<UTexture2D> BackgroundImage, CheckerTexture;
    FString Path, Folder, Error;
    FVector2D Pan = FVector2D::ZeroVector;
    float Zoom = 8, BgX = 0, BgY = 0, BgScale = 1, BgAlpha = 1;
    FLinearColor BgColor = FLinearColor(.13f, .14f, .17f);
    bool Mark = false, Hints = false, Sockets = false, Checker = true, ShowBackground = true, Fitted = false,
         EditChild = false;
    int SocketIndex = 0, MaskIndex = 0, RequestedMaskIndex = 0, ClipIndex = -1, FileTarget = 0;
    FSlateColorBrush White{FLinearColor::White};
    TSharedRef<SWidget> Button(const FString &Text, TFunction<void()> Fn) {
        return SNew(SButton)
            .ContentPadding(FMargin(9, 7))
            .Text(FText::FromString(Text))
            .OnClicked_Lambda([Fn = MoveTemp(Fn)]() {
                Fn();
                return FReply::Handled();
            });
    }
    void Construct(const FArguments &) {
        Folder = FPlatformProcess::UserHomeDir();
        CheckerTexture.Reset(UTexture2D::CreateTransient(32, 32, PF_R8G8B8A8));
        CheckerTexture->Filter = TF_Nearest;
        CheckerTexture->AddressX = TA_Wrap;
        CheckerTexture->AddressY = TA_Wrap;
        auto& Pixels = CheckerTexture->GetPlatformData()->Mips[0].BulkData;
        auto Data = static_cast<uint8*>(Pixels.Lock(LOCK_READ_WRITE));
        for (int I=0; I<32*32; I++) { uint8 C=((I%32)/16==(I/32)/16)?56:77; Data[I*4]=Data[I*4+1]=Data[I*4+2]=C; Data[I*4+3]=255; }
        Pixels.Unlock();
        CheckerTexture->UpdateResource();
        auto Toolbar = SNew(SWrapBox).UseAllottedSize(true).InnerSlotPadding(FVector2D(3, 3));
        auto Add = [&](const TCHAR *Text, TFunction<void()> Fn) {
            Toolbar->AddSlot()[Button(Text, MoveTemp(Fn))];
        };
        Add(TEXT("Open  Ctrl+O"), [this] { Files(0); });
        Add(TEXT("Play / Pause  Space"), [this] { Play(); });
        Add(TEXT("Restart"), [this] { Restart(); });
        Add(TEXT("Step"), [this] {
            Pause();
            if (Doc)
                Doc->Step();
        });
        Add(TEXT("Colors  Ctrl+M"), [this] {
            Pause();
            Colors();
        });
        Add(TEXT("Masks [M]"), [this] { Mark = !Mark; });
        Add(TEXT("Hints [H]"), [this] { Hints = !Hints; });
        Add(TEXT("Sockets [S]"), [this] { Sockets = !Sockets; });
        Add(TEXT("Background"), [this] { BackgroundPanel(); });
        Add(TEXT("Info"), [this] { Info(); });
        Add(TEXT("Fit [F]"), [this] { Fit(); });
        Add(TEXT("1:1"), [this] {
            Zoom = 1;
            Pan = FVector2D::ZeroVector;
        });
        Add(TEXT("−"), [this] { Zoom = FMath::Max(.1f, Zoom / 2); });
        Add(TEXT("+"), [this] { Zoom = FMath::Min(128.f, Zoom * 2); });
        Add(TEXT("Attach…"), [this] { Files(1); });
        Add(TEXT("Detach"), [this] { Child.Reset(); });
        Add(TEXT("Next socket"), [this] {
            if (Doc && Doc->State.Sockets.Num())
                SocketIndex = (SocketIndex + 1) % Doc->State.Sockets.Num();
        });
        Add(TEXT("Next clip"), [this] {
            if (Doc) {
                ClipIndex++;
                if (ClipIndex >= Doc->State.Clips.Num())
                    ClipIndex = -1;
                Restart();
            }
        });
        ChildSlot[SNew(SBorder).Padding(8).BorderImage(&White).BorderBackgroundColor(FLinearColor(
            .035f, .04f,
            .055f))[SNew(SVerticalBox) + SVerticalBox::Slot().AutoHeight()[Toolbar] +
                    SVerticalBox::Slot().FillHeight(1).Padding(
                        0,
                        6)[SNew(SHorizontalBox) +
                           SHorizontalBox::Slot().FillWidth(1)[SAssignNew(Canvas, SImageArea).Owner(this)] +
                           SHorizontalBox::Slot().AutoWidth().Padding(8, 0)
                               [SAssignNew(PanelBox, SBox)
                                    .WidthOverride(370)
                                    .Visibility(EVisibility::Collapsed)[SAssignNew(Panel, SVerticalBox)]]] +
                    SVerticalBox::Slot().AutoHeight()[SNew(SSlider)
                                                          .Value_Lambda([this] {
                                                              return Doc && Doc->State.Frames > 1
                                                                         ? float(FMath::Max(
                                                                               0, Doc->State.Visible)) /
                                                                               (Doc->State.Frames - 1)
                                                                         : 0.f;
                                                          })
                                                          .OnValueChanged_Lambda([this](float V) {
                                                              if (Doc) {
                                                                  Pause();
                                                                  Doc->Seek(FMath::RoundToInt(
                                                                      V * (Doc->State.Frames - 1)));
                                                              }
                                                          })] +
                    SVerticalBox::Slot().AutoHeight()[SNew(STextBlock).Text_Lambda([this] {
                        return FText::FromString(Status());
                    })]]];
        FString File;
        if (FParse::Value(FCommandLine::Get(), TEXT("PapngFile="), File))
            Open(File, 0);
        else {
            TArray<FString> Tokens, Switches;
            FCommandLine::Parse(FCommandLine::Get(), Tokens, Switches);
            for (auto &Token : Tokens)
                if (IsImage(Token) && IFileManager::Get().FileExists(*Token)) {
                    Open(Token, 0);
                    break;
                }
        }
    }
    virtual bool SupportsKeyboardFocus() const override { return true; }
    static bool IsImage(const FString &P) {
        auto Ext = FPaths::GetExtension(P).ToLower();
        return Ext == TEXT("png") || Ext == TEXT("apng") || Ext == TEXT("papng");
    }
    FString Status() const {
        if (!Error.IsEmpty())
            return Error;
        if (!Doc)
            return TEXT("Open a PAPNG, APNG or PNG image to begin.");
        auto &S = Doc->State;
        if (!S.Error.IsEmpty())
            return S.Error;
        if (!S.Width)
            return TEXT("Loading…");
        if (Child && !Child->State.Error.IsEmpty()) return TEXT("Accessory: ")+Child->State.Error;
        return FString::Printf(TEXT("%s   %d × %d   Frame %d / %d   %.2f×   %s   Clip: %s%s"),
                               *FPaths::GetCleanFilename(Path), S.Width, S.Height, S.Visible + 1, S.Frames,
                               Zoom, Doc->Playing ? TEXT("Playing") : TEXT("Paused"),
                               ClipIndex < 0 ? TEXT("Full animation") : *S.Clips[ClipIndex],
                               S.Warnings.IsEmpty() ? TEXT("") : TEXT("   Warnings: see Info"));
    }
    virtual void Tick(const FGeometry &Geometry, double Time, float Delta) override {
        SCompoundWidget::Tick(Geometry, Time, Delta);
        if (Doc) {
            Doc->Update(FMath::Min(.25f, Delta));
            if (Doc->State.Width && !Fitted) {
                Fit();

            }
        }
        if (Child) {
            if (!Doc || !Doc->Playing)
                Child->Playing = false;
            Child->Update(FMath::Min(.25f, Delta));
        }
    }
    void Open(const FString &File, int Target) {
        Error.Empty();
        if (Target == 2) {
            TArray<uint8> Bytes;
            int64 Size = IFileManager::Get().FileSize(*File);
            if (Size < 0 || Size > 64 * 1024 * 1024 || !FFileHelper::LoadFileToArray(Bytes, *File)) {
                Error = TEXT("Background cannot be read (64 MiB limit)");
                return;
            }
            auto &Module = FModuleManager::LoadModuleChecked<IImageWrapperModule>(TEXT("ImageWrapper"));
            auto Format = Module.DetectImageFormat(Bytes.GetData(), Bytes.Num());
            auto Wrapper = Module.CreateImageWrapper(Format);
            if (!Wrapper.IsValid() || !Wrapper->SetCompressed(Bytes.GetData(), Bytes.Num()) ||
                int64(Wrapper->GetWidth()) * Wrapper->GetHeight() > 32000000) {
                Error = TEXT("Unsupported background or larger than 32 MP");
                return;
            }
            BackgroundImage.Reset(FImageUtils::ImportBufferAsTexture2D(Bytes));
            if (BackgroundImage.IsValid()) {
                BackgroundImage->Filter = TF_Nearest;
                ShowBackground = true;
            } else
                Error = TEXT("Background decode failed");
            return;
        }
        if (Target == 1) {
            Child = MakeUnique<FDocument>(File);
        } else {
            Doc = MakeUnique<FDocument>(File);
            Child.Reset();
            Path = File;
            Fitted = false;
            MaskIndex = SocketIndex = 0;
            ClipIndex = -1;
        }
        PanelBox->SetVisibility(EVisibility::Collapsed);
    }
    void Pause() {
        if (Doc)
            Doc->Playing = false;
        if (Child)
            Child->Playing = false;
    }
    void Play() {
        if (!Doc)
            return;
        bool Playing = !Doc->Playing;
        if (Playing && Doc->State.Ended)
            Restart();
        Doc->Playing = Playing;
        if (Child)
            Child->Playing = Playing;
    }
    void Restart() {
        if (Doc)
            Doc->Restart(ClipIndex);
        if (Child)
            Child->Restart();
    }
    void Fit() {
        if (!Doc || !Doc->State.Width || !Canvas)
            return;
        auto Size = Canvas->GetCachedGeometry().GetLocalSize();
        if (Size.X <= 30 || Size.Y <= 30) return;
        Fitted = true;
        Zoom = FMath::Max(.1f, FMath::Min(float((Size.X - 30) / Doc->State.Width),
                                          float((Size.Y - 30) / Doc->State.Height)));
        if (Zoom >= 1)
            Zoom = FMath::Max(1.f, FMath::Floor(Zoom));
        Pan = FVector2D::ZeroVector;
    }
    void BeginPanel(const TCHAR *Title) {
        PanelBox->SetVisibility(EVisibility::Visible);
        Panel->ClearChildren();
        Panel->AddSlot().AutoHeight().Padding(
            0, 0, 0, 8)[SNew(SHorizontalBox) +
                        SHorizontalBox::Slot().FillWidth(1)[SNew(STextBlock).Text(FText::FromString(Title))] +
                        SHorizontalBox::Slot().AutoWidth()[Button(TEXT("Close"), [this] {
                            PanelBox->SetVisibility(EVisibility::Collapsed);
                            FSlateApplication::Get().SetKeyboardFocus(AsShared());
                        })]];
    }
    void Label(const FString &Text) {
        Panel->AddSlot().AutoHeight().Padding(
            0, 5)[SNew(STextBlock).Text(FText::FromString(Text)).AutoWrapText(true)];
    }
    void Number(const FString &Text, float Value, float Min, float Max, TFunction<void(float)> Fn) {
        Label(Text);
        Panel->AddSlot().AutoHeight()[SNew(SSpinBox<float>)
                                          .MinValue(Min)
                                          .MaxValue(Max)
                                          .Value(Value)
                                          .OnValueChanged_Lambda([Fn = MoveTemp(Fn)](float V) { Fn(V); })];
    }
    void Files(int Target) {
        FileTarget = Target;
        ListFolder(Folder);
    }
    void ListFolder(const FString &Directory) {
        FString Full = FPaths::ConvertRelativePathToFull(Directory);
        if (!IFileManager::Get().DirectoryExists(*Full)) {
            Error = TEXT("Directory not found");
            return;
        }
        Folder = Full;
        BeginPanel(TEXT("Open image"));
        Panel->AddSlot()
            .AutoHeight()[SAssignNew(Address, SEditableTextBox)
                              .Text(FText::FromString(Folder))
                              .OnTextCommitted_Lambda([this](const FText &T, ETextCommit::Type Type) {
                                  if (Type == ETextCommit::OnEnter)
                                      ListFolder(T.ToString());
                              })];
        Panel->AddSlot()
            .AutoHeight()[Button(TEXT("Parent directory"), [this] { ListFolder(FPaths::GetPath(Folder)); })];
        TArray<FString> Dirs, Files;
        IFileManager::Get().FindFiles(Dirs, *(Folder / TEXT("*")), false, true);
        IFileManager::Get().FindFiles(Files, *(Folder / TEXT("*")), true, false);
        Dirs.Sort();
        Files.Sort();
        auto List = SNew(SScrollBox);
        Panel->AddSlot().FillHeight(1)[List];
        for (auto &Name : Dirs) {
            FString P = Folder / Name;
            List->AddSlot()[Button(TEXT("▸ ") + Name, [this, P] { ListFolder(P); })];
        }
        for (auto &Name : Files) {
            if (FileTarget != 2 && !IsImage(Name))
                continue;
            FString P = Folder / Name;
            List->AddSlot()[Button(Name, [this, P] { Open(P, FileTarget); })];
        }
        if (Files.IsEmpty())
            Label(TEXT("No matching files. You can enter another directory above."));
    }
    void Info() {
        BeginPanel(TEXT("File information"));
        auto List = SNew(SScrollBox);
        List->AddSlot()[SNew(SMultiLineEditableText)
                            .IsReadOnly(true)
                            .Text(FText::FromString(
                                Doc ? Doc->State.Error + TEXT("\n") + Doc->State.Warnings + TEXT("\n") +
                                          Doc->State.Metadata.Left(65536) +
                                          (Doc->State.Metadata.Len() > 65536
                                               ? TEXT("\n[Preview limited to 65536 characters]")
                                               : TEXT(""))
                                    : TEXT("No image")))];
        Panel->AddSlot().FillHeight(1)[List];
    }
    static FLinearColor Mean(uint32 Value) {
        return FLinearColor(float((Value >> 24) & 255) / 255, float((Value >> 16) & 255) / 255,
                            float((Value >> 8) & 255) / 255, 1);
    }
    static FLinearColor DisplayColor(FLinearColor Encoded) {
        return FLinearColor::FromSRGBColor(Encoded.ToFColor(false));
    }
    static FLinearColor EncodedColor(FLinearColor Linear) {
        auto C = Linear.ToFColor(true);
        return FLinearColor(C.R / 255.f, C.G / 255.f, C.B / 255.f, 1);
    }
    FDocument *Editing() { return EditChild && Child ? Child.Get() : Doc.Get(); }
    void Colors() {
        BeginPanel(TEXT("Mask HSV"));
        if (Child)
            Panel->AddSlot().AutoHeight()[Button(EditChild ? TEXT("Editing accessory — switch to parent")
                                                           : TEXT("Editing parent — switch to accessory"),
                                                 [this] {
                                                     EditChild = !EditChild;
                                                     MaskIndex = 0;
                                                     Colors();
                                                 })];
        auto D = Editing();
        if (!D || !D->State.Masks) {
            Label(TEXT("No masks in this image."));
            return;
        }
        MaskIndex = FMath::Clamp(MaskIndex, 0, D->State.Masks - 1);
        RequestedMaskIndex = MaskIndex;
        Number(TEXT("Mask index"), MaskIndex, 0, D->State.Masks - 1,
               [this](float V) { RequestedMaskIndex = FMath::RoundToInt(V); });
        Panel->AddSlot().AutoHeight()[Button(TEXT("Select mask"), [this] {
            auto D = Editing();
            if (D && D->State.Masks) {
                Pause();
                MaskIndex = RequestedMaskIndex;
                D->Select(MaskIndex);
                Colors();
            }
        })];
        Label(D->State.MaskNames[MaskIndex]);
        auto Original = Mean(D->State.Means[MaskIndex]);
        auto HSV = Original.LinearRGBToHSV();
        float Offset = D->Offsets[MaskIndex];
        auto Edited = HSV;
        Edited.R = FMath::Fmod(HSV.R + Offset + 360, 360);
        Edited.G = FMath::Clamp(HSV.G + D->SaturationOffsets[MaskIndex], 0.f, 1.f);
        Edited.B = FMath::Clamp(HSV.B + D->ValueOffsets[MaskIndex], 0.f, 1.f);
        Edited = Edited.HSVToLinearRGB();
        Panel->AddSlot()
            .AutoHeight()[SNew(SHorizontalBox) +
                          SHorizontalBox::Slot().FillWidth(
                              1)[SNew(SBorder).Padding(16).BorderImage(&White).BorderBackgroundColor(
                              DisplayColor(Original))[SNew(STextBlock).Text(FText::FromString(TEXT("Original")))]] +
                          SHorizontalBox::Slot().FillWidth(
                              1)[SNew(SBorder).Padding(16).BorderImage(&White).BorderBackgroundColor(
                              DisplayColor(Edited))[SNew(STextBlock).Text(FText::FromString(TEXT("Modified")))]]];
        Label(FString::Printf(TEXT("Original H: %.1f°  Offset: %.1f°"), HSV.R, Offset));
        Panel->AddSlot().AutoHeight()[Button(TEXT("Choose color…"), [this, Edited, HSV] {
            Pause();
            TWeakPtr<SViewer> Weak = SharedThis(this);
            FColorPickerArgs Args(DisplayColor(Edited),
                                  FOnLinearColorValueChanged::CreateLambda([Weak, HSV, Target=Editing(), Index=MaskIndex](FLinearColor Value) {
                                      if (auto Self = Weak.Pin()) {
                                          auto D = Self->Editing();
                                          if (D == Target && D && Self->MaskIndex == Index && D->State.Masks) {
                                              auto Picked = EncodedColor(Value).LinearRGBToHSV();
                                              D->MaskHsv(Index, Picked.R - HSV.R, Picked.G - HSV.G, Picked.B - HSV.B);
                                              Self->Restart();
                                              Self->Colors();
                                          }
                                      }
                                  }));
            Args.ParentWidget = AsShared();
            Args.bUseAlpha = false;
            Args.sRGBOverride = true;
            Args.bOnlyRefreshOnMouseUp = true;
            OpenColorPicker(Args);
        })];
        Number(TEXT("Target hue (degrees)"), FMath::Fmod(HSV.R + Offset + 360, 360), 0, 360,
               [this, Hue = HSV.R](float V) {
                   auto D = Editing();
                   if (D && D->State.Masks) {
                       Pause();
                       D->Mask(MaskIndex, V - Hue);
                       Restart();
                   }
               });
        Number(TEXT("ΔS saturation"), D->SaturationOffsets[MaskIndex], -1, 1, [this](float V) {
            auto Target = Editing(); if (!Target || !Target->State.Masks) return;
            Pause(); Target->MaskHsv(MaskIndex, Target->Offsets[MaskIndex], V, Target->ValueOffsets[MaskIndex]); Restart();
        });
        Number(TEXT("ΔV value"), D->ValueOffsets[MaskIndex], -1, 1, [this](float V) {
            auto Target = Editing(); if (!Target || !Target->State.Masks) return;
            Pause(); Target->MaskHsv(MaskIndex, Target->Offsets[MaskIndex], Target->SaturationOffsets[MaskIndex], V); Restart();
        });
        Panel->AddSlot().AutoHeight()[Button(TEXT("Update swatches"), [this] { Colors(); })];
        Panel->AddSlot().AutoHeight()[Button(TEXT("Reset offset"), [this] {
            auto D = Editing();
            if (D) {
                D->MaskHsv(MaskIndex, 0, 0, 0);
                Pause();
                Restart();
                Colors();
            }
        })];
        Panel->AddSlot().AutoHeight()[Button(TEXT("Highlight all masks"), [this] {
            auto D = Editing();
            if (D)
                D->Select(-1);
            Mark = true;
            Pause();
        })];
        Label(TEXT(
            "HSV edits pause playback and reconstruct from frame zero. S/V are additive and clamped to 0–1; clipping can reduce texture. Alpha is preserved."));
    }
    void BackgroundPanel() {
        BeginPanel(TEXT("Background"));
        Panel->AddSlot()
            .AutoHeight()[Button(Checker ? TEXT("Checker — use solid") : TEXT("Solid — use checker"), [this] {
                Checker = !Checker;
                BackgroundPanel();
            })];
        Number(TEXT("Red"), BgColor.R, 0, 1, [this](float V) { BgColor.R = V; });
        Number(TEXT("Green"), BgColor.G, 0, 1, [this](float V) { BgColor.G = V; });
        Number(TEXT("Blue"), BgColor.B, 0, 1, [this](float V) { BgColor.B = V; });
        Panel->AddSlot().AutoHeight()[Button(TEXT("Load background image…"), [this] { Files(2); })];
        if (!BackgroundImage.IsValid())
            return;
        Panel->AddSlot()
            .AutoHeight()[Button(ShowBackground ? TEXT("Hide image") : TEXT("Show image"), [this] {
                ShowBackground = !ShowBackground;
                BackgroundPanel();
            })];
        Number(TEXT("X (source pixels)"), BgX, -1000000, 1000000, [this](float V) { BgX = V; });
        Number(TEXT("Y (source pixels)"), BgY, -1000000, 1000000, [this](float V) { BgY = V; });
        Number(TEXT("Scale"), BgScale, .001f, 10000, [this](float V) { BgScale = V; });
        Number(TEXT("Opacity"), BgAlpha, 0, 1, [this](float V) { BgAlpha = V; });
        Panel->AddSlot().AutoHeight()[Button(TEXT("Fit background"), [this] {
            if (Doc) {
                BgScale = FMath::Min(float(Doc->State.Width) / BackgroundImage->GetSizeX(),
                                     float(Doc->State.Height) / BackgroundImage->GetSizeY());
                BgX = (Doc->State.Width - BackgroundImage->GetSizeX() * BgScale) / 2;
                BgY = (Doc->State.Height - BackgroundImage->GetSizeY() * BgScale) / 2;
                BackgroundPanel();
            }
        })];
        Panel->AddSlot().AutoHeight()[Button(TEXT("Remove background"), [this] {
            BackgroundImage.Reset();
            BackgroundPanel();
        })];
    }
    int Paint(const FGeometry &G, FSlateWindowElementList &Out, int Layer) const {
        auto Size = G.GetLocalSize();
        auto Box = [&](FVector2D P, FVector2D S, FLinearColor C) {
            FSlateDrawElement::MakeBox(Out, Layer++, G.ToPaintGeometry(S, FSlateLayoutTransform(P)), &White,
                                       ESlateDrawEffect::None, C);
        };
        auto Line = [&](FVector2D A, FVector2D B, FLinearColor C) {
            TArray<FVector2D> Points{A, B};
            FSlateDrawElement::MakeLines(Out, Layer++, G.ToPaintGeometry(), Points, ESlateDrawEffect::None, C,
                                         true, 1.5);
        };
        auto Text = [&](FVector2D P, const FString &S) {
            FSlateDrawElement::MakeText(
                Out, Layer++, G.ToPaintGeometry(FVector2D(1, 1), FSlateLayoutTransform(P)), S,
                FCoreStyle::GetDefaultFontStyle("Regular", 12), ESlateDrawEffect::None, FLinearColor::White);
        };
        auto Cross = [&](FVector2D P, const FString &Name, double R) {
            Line(P - FVector2D(6, 0), P + FVector2D(6, 0), FLinearColor(0, 1, 1));
            Line(P - FVector2D(0, 6), P + FVector2D(0, 6), FLinearColor(0, 1, 1));
            double A = FMath::DegreesToRadians(FMath::Fmod(R,360.0));
            Line(P, P + FVector2D(cos(A), sin(A)) * 22, FLinearColor::Yellow);
            Text(P + FVector2D(8, -20), Name);
        };
        auto Image = [&](UTexture2D *Texture, FVector2D P, FVector2D S, float Alpha = 1.f, double Angle = 0,
                         FVector2D Pivot = FVector2D::ZeroVector) {
            if (!Texture)
                return;
            FSlateBrush Brush;
            Brush.SetResourceObject(Texture);
            Brush.ImageSize = S;
            Brush.DrawAs = ESlateBrushDrawType::Image;
            FSlateDrawElement::MakeRotatedBox(Out, Layer++, G.ToPaintGeometry(S, FSlateLayoutTransform(P)),
                                              &Brush, ESlateDrawEffect::None, FMath::DegreesToRadians(FMath::Fmod(Angle,360.0)),
                                              FVector2f(Pivot), FSlateDrawElement::RelativeToElement,
                                              FLinearColor(1, 1, 1, Alpha));
        };
        if (Checker) {
            FSlateBrush Brush;
            Brush.SetResourceObject(CheckerTexture.Get());
            Brush.DrawAs = ESlateBrushDrawType::Image;
            Brush.Tiling = ESlateBrushTileType::Both;
            Brush.ImageSize = FVector2D(32,32);
            FSlateDrawElement::MakeBox(Out, Layer++, G.ToPaintGeometry(), &Brush);
        } else Box(FVector2D::ZeroVector, Size, BgColor);
        if (!Doc || !Doc->State.Width) {
            Text(FVector2D(24, 24), TEXT("Open a PAPNG, APNG or PNG image."));
            return Layer;
        }
        auto &S = Doc->State;
        FVector2D Origin = (Size - FVector2D(S.Width, S.Height) * Zoom) / 2 + Pan,
                  Extent = FVector2D(S.Width, S.Height) * Zoom;
        if (BackgroundImage.IsValid() && ShowBackground)
            Image(BackgroundImage.Get(), Origin + FVector2D(BgX, BgY) * Zoom,
                  FVector2D(BackgroundImage->GetSizeX(), BackgroundImage->GetSizeY()) * BgScale * Zoom,
                  BgAlpha);
        Image(Doc->Image.Get(), Origin, Extent);
        if (Mark)
            Image(Doc->Highlight.Get(), Origin, Extent, .65f);
        if (Child && Child->Image.IsValid() && S.Poses.IsValidIndex(SocketIndex) &&
            S.Poses[SocketIndex].Num() == 3 && FMath::Abs(S.Poses[SocketIndex][0])<=1e10 && FMath::Abs(S.Poses[SocketIndex][1])<=1e10) {
            auto P = S.Poses[SocketIndex];
            FVector2D Pivot = FVector2D::ZeroVector;
            if (Child->State.Hints.IsValidIndex(3) && Child->State.Hints[3].Num())
                Pivot = FVector2D(Child->State.Hints[3][0], Child->State.Hints[3][1]) * Zoom;
            Image(Child->Image.Get(), Origin + FVector2D(P[0], P[1]) * Zoom - Pivot,
                  FVector2D(Child->State.Width, Child->State.Height) * Zoom, 1, P[2], Pivot);
        }
        if (Hints) {
            Line(Origin, Origin + FVector2D(Extent.X, 0), FLinearColor::Green);
            Line(Origin, Origin + FVector2D(0, Extent.Y), FLinearColor::Green);
            Line(Origin + Extent, Origin + FVector2D(Extent.X, 0), FLinearColor::Green);
            Line(Origin + Extent, Origin + FVector2D(0, Extent.Y), FLinearColor::Green);
            if (S.Hints.Num() == 4) {
                if (S.Hints[3].Num())
                    Cross(Origin + FVector2D(S.Hints[3][0], S.Hints[3][1]) * Zoom, TEXT("Pivot"), 0);
                if (S.Hints[1].Num()) {
                    auto B = S.Hints[1];
                    FVector2D A = Origin + FVector2D(B[0], B[1]) * Zoom, Z = A + FVector2D(B[2], B[3]) * Zoom;
                    Line(A, FVector2D(Z.X, A.Y), FLinearColor::Yellow);
                    Line(A, FVector2D(A.X, Z.Y), FLinearColor::Yellow);
                    Line(Z, FVector2D(Z.X, A.Y), FLinearColor::Yellow);
                    Line(Z, FVector2D(A.X, Z.Y), FLinearColor::Yellow);
                }
                Text(FVector2D(10, 10),
                     FString::Printf(TEXT("Output: %s   Pixel multiple: %s"),
                                     S.Hints[0].Num()
                                         ? *FString::Printf(TEXT("%.0f × %.0f"), S.Hints[0][0], S.Hints[0][1])
                                         : TEXT("unspecified"),
                                     S.Hints[2].Num() ? *FString::Printf(TEXT("%.0f"), S.Hints[2][0])
                                                      : TEXT("unspecified")));
            }
        }
        if (Sockets)
            for (int I = 0; I < S.Poses.Num(); I++)
                if (S.Poses[I].Num() == 3 && FMath::Abs(S.Poses[I][0])<=1e10 && FMath::Abs(S.Poses[I][1])<=1e10)
                    Cross(Origin + FVector2D(S.Poses[I][0], S.Poses[I][1]) * Zoom, S.Sockets[I],
                          S.Poses[I][2]);
        return Layer;
    }
    virtual FReply OnKeyDown(const FGeometry &, const FKeyEvent &E) override {
        auto K = E.GetKey();
        bool Ctrl = E.IsControlDown() || E.IsCommandDown();
        if (Ctrl && K == EKeys::O)
            Files(0);
        else if (Ctrl && K == EKeys::M) {
            Pause();
            Colors();
        } else if (Ctrl && K == EKeys::B)
            BackgroundPanel();
        else if (Ctrl && K == EKeys::L)
            Files(1);
        else if (K == EKeys::SpaceBar)
            Play();
        else if (K == EKeys::Home)
            Restart();
        else if (K == EKeys::Right) {
            Pause();
            if (Doc)
                Doc->Step();
        } else if (K == EKeys::M)
            Mark = !Mark;
        else if (K == EKeys::H)
            Hints = !Hints;
        else if (K == EKeys::S)
            Sockets = !Sockets;
        else if (K == EKeys::F)
            Fit();
        else if (K == EKeys::One) {
            Zoom = 1;
            Pan = FVector2D::ZeroVector;
        } else
            return FReply::Unhandled();
        return FReply::Handled();
    }
    virtual FReply OnDrop(const FGeometry &, const FDragDropEvent &Event) override {
        auto Op = Event.GetOperationAs<FExternalDragOperation>();
        if (Op.IsValid() && Op->HasFiles()) {
            for (auto &File : Op->GetFiles())
                if (IsImage(File)) {
                    Open(File, 0);
                    return FReply::Handled();
                }
        }
        return FReply::Unhandled();
    }
};
int32 SImageArea::OnPaint(const FPaintArgs &, const FGeometry &G, const FSlateRect &,
                          FSlateWindowElementList &Out, int32 Layer, const FWidgetStyle &, bool) const {
    return Owner->Paint(G, Out, Layer);
}
FReply SImageArea::OnMouseWheel(const FGeometry &, const FPointerEvent &E) {
    Owner->Zoom = FMath::Clamp(Owner->Zoom * FMath::Pow(1.15f, E.GetWheelDelta()), .1f, 128.f);
    return FReply::Handled();
}
FReply SImageArea::OnMouseButtonDown(const FGeometry &, const FPointerEvent &) {
    return FReply::Handled().CaptureMouse(AsShared()).SetUserFocus(Owner->AsShared());
}
FReply SImageArea::OnMouseMove(const FGeometry &G, const FPointerEvent &E) {
    if (HasMouseCapture()) {
        Owner->Pan += E.GetCursorDelta() / G.Scale;
        return FReply::Handled();
    }
    return FReply::Unhandled();
}
void AViewerMode::StartPlay() {
    Super::StartPlay();
    if (GEngine && GEngine->GameViewport) {
        GEngine->GameViewport->bDisableWorldRendering = true;
        auto View = SNew(SViewer);
        GEngine->GameViewport->AddViewportWidgetContent(View);
        if (auto PC = GetWorld()->GetFirstPlayerController()) {
            PC->bShowMouseCursor = true;
            FInputModeUIOnly Mode;
            Mode.SetWidgetToFocus(View);
            Mode.SetLockMouseToViewportBehavior(EMouseLockMode::DoNotLock);
            PC->SetInputMode(Mode);
        }
    }
}
