#pragma once
#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"
#include "ViewerMode.generated.h"
UCLASS()
class AViewerMode : public AGameModeBase {
    GENERATED_BODY()
  public:
    virtual void StartPlay() override;
};
