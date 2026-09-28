import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ApplicationWindow {
    id: window
    required property QtObject controller
    width: 1180; height: 810
    minimumWidth: 900; minimumHeight: 680
    visible: true
    title: "PAPNG Converter"
    color: "#111720"
    palette.window: "#111720"
    palette.windowText: "#e5edf7"
    palette.base: "#19222f"
    palette.text: "#e5edf7"
    palette.button: "#253449"
    palette.buttonText: "#e5edf7"
    palette.highlight: "#398b78"
    palette.highlightedText: "#ffffff"
    font.family: "Noto Sans CJK KR"
    font.pixelSize: 14
    property int page: 0
    property bool playing: false
    property int completedLoops: 0
    property bool lockAspect: true
    property int sizeDivisor: 1
    property bool divisorActive: false
    property string sizingSource: ""
    function divideSize(value) {
        sizeDivisor = Math.round(value)
        divisorActive = true
        set("width", Math.max(1, Math.round(controller.settings.cropWidth / sizeDivisor)))
        set("height", Math.max(1, Math.round(controller.settings.cropHeight / sizeDivisor)))
    }
    readonly property var titles: ["파일 선택", "사용 구간", "크기와 자르기", "프레임과 시간", "색상과 투명도", "확인과 저장"]
    readonly property var notes: ["작은 움직임을 픽셀 애니메이션으로", "남기고 싶은 움직임만 선택하세요", "최종 픽셀 크기에서 모양을 다듬으세요", "원래 속도를 유지하거나 프레임 수를 줄이세요", "원하는 경우에만 색상을 정리하세요", "결과를 재생하고 편집기로 가져가세요"]
    function set(key, value) { playing = false; controller.change(key, value) }
    function sizeWidth(value) {
        divisorActive = false
        if (!lockAspect) { set("width", value); return }
        let ratio = controller.settings.cropHeight / controller.settings.cropWidth
        let w = Math.min(value, 512 / ratio)
        set("width", Math.max(1, Math.round(w)))
        set("height", Math.max(1, Math.min(512, Math.round(w * ratio))))
    }
    function sizeHeight(value) {
        divisorActive = false
        if (!lockAspect) { set("height", value); return }
        let ratio = controller.settings.cropWidth / controller.settings.cropHeight
        let h = Math.min(value, 512 / ratio)
        set("height", Math.max(1, Math.round(h)))
        set("width", Math.max(1, Math.min(512, Math.round(h * ratio))))
    }
    function applyCrop(x, y, w, h) {
        controller.crop(x, y, w, h)
        if (lockAspect) {
            if (divisorActive) divideSize(sizeDivisor)
            else sizeWidth(controller.settings.width)
        }
    }
    FileDialog {
        id: openDialog
        title: "변환할 영상 또는 GIF 선택"
        nameFilters: ["영상과 애니메이션 (*.mp4 *.MP4 *.webm *.WEBM *.gif *.GIF)"]
        onAccepted: { playing = false; page = 0; controller.open(selectedFile) }
    }
    FileDialog {
        id: saveDialog
        title: "PAPNG 저장"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "papng"
        nameFilters: ["PAPNG 이미지 (*.papng)"]
        onAccepted: controller.exportFile(selectedFile)
    }
    Dialog {
        id: pickDialog
        objectName: "sourceColorDialog"
        title: "배경색 선택 · 원본에서 픽셀 클릭"
        anchors.centerIn: parent
        width: Math.min(window.width - 60, 900); height: Math.min(window.height - 60, 650)
        modal: true
        standardButtons: Dialog.Close
        contentItem: ColumnLayout {
            Preview {
                objectName: "colorPickPreview"
                Layout.fillWidth: true; Layout.fillHeight: true
                source: controller.sourceUrl
                sourceWidth: controller.media.width || 1; sourceHeight: controller.media.height || 1
                pickEnabled: !controller.busy
                caption: "원본 · " + controller.sourceTime.toFixed(3) + "초"
                onPixelPicked: (x, y) => {
                    window.set("keyColor", controller.sourceColor(x, y).toString())
                    pickDialog.close()
                }
            }
            RowLayout {
                enabled: !controller.busy
                Button { text: "◀ 이전 프레임"; onClicked: controller.step(-1) }
                Button { text: "다음 프레임 ▶"; onClicked: controller.step(1) }
                Button { text: "색상 대화상자…"; onClicked: { pickDialog.close(); keyDialog.selectedColor = controller.settings.keyColor; keyDialog.open() } }
            }
        }
    }
    ColorDialog { id: keyDialog; title: "투명하게 바꿀 배경색"; onAccepted: window.set("keyColor", selectedColor.toString()) }
    Connections {
        target: controller
        function onGenerated() { page = 5; completedLoops = 0; playing = true }
        function onChanged() {
            if (!controller.ready || controller.error.length > 0) playing = false
            if ((controller.media.path || "") !== sizingSource) {
                sizingSource = controller.media.path || ""
                divisorActive = false; sizeDivisor = 1
            }
        }
    }
    Timer {
        id: playTimer
        interval: controller.frameDelay
        repeat: false
        running: playing && controller.ready && !controller.busy && !controller.comparisonBusy
        onTriggered: {
            if (controller.frameIndex + 1 >= controller.frameCount) {
                completedLoops++
                if (controller.settings.plays > 0 && completedLoops >= controller.settings.plays) { playing = false; return }
                controller.selectFrame(0)
            } else controller.selectFrame(controller.frameIndex + 1)
            if (playing && !controller.comparisonBusy) restart()
        }
    }
    Shortcut { sequence: "Ctrl+O"; enabled: !controller.busy; onActivated: openDialog.open() }
    Shortcut { sequence: "Space"; enabled: page === 5 && controller.ready && !controller.busy; onActivated: { completedLoops = 0; playing = !playing } }
    Shortcut { sequence: "Escape"; enabled: controller.busy; onActivated: controller.cancel() }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillHeight: true; Layout.preferredWidth: 206
            color: "#182230"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 22; spacing: 12
                Label { text: "PAPNG"; font.pixelSize: 29; font.bold: true; color: "#83e2c3" }
                Label { text: "CONVERTER"; font.letterSpacing: 2; font.pixelSize: 12; color: "#aab8ca" }
                Item { Layout.preferredHeight: 24 }
                Repeater {
                    model: window.titles
                    delegate: Button {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        text: (index + 1) + "   " + modelData
                        flat: true
                        highlighted: page === index
                        enabled: !controller.busy && (index === 0 || controller.media.width > 0) && (index < 5 || controller.ready)
                        onClicked: { playing = false; page = index }
                    }
                }
                Item { Layout.fillHeight: true }
                Label { text: "MP4 · WebM · GIF\n↓\nPAPNG 1.1"; color: "#9daec3"; lineHeight: 1.4 }
                Label { text: "Linux · Windows"; font.pixelSize: 11; color: "#72859e" }
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.margins: 26; spacing: 14
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Label { text: window.titles[page]; font.pixelSize: 25; font.bold: true }
                    Label { text: window.notes[page]; color: "#9daec3" }
                }
                Item { Layout.fillWidth: true }
                Button { text: "다른 파일…"; enabled: !controller.busy; visible: controller.media.width > 0; onClicked: openDialog.open() }
            }
            Label {
                Layout.fillWidth: true
                visible: controller.media.width > 0
                text: (controller.media.name || "") + "  ·  " + (controller.media.width || 0) + " × " + (controller.media.height || 0) + "  ·  " + Number(controller.media.duration || 0).toFixed(3) + "초"
                color: "#83e2c3"; elide: Text.ElideMiddle
            }
            StackLayout {
                id: pages
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: page
                enabled: !controller.busy
                // 1. Source
                Item {
                    ColumnLayout {
                        anchors.fill: parent; spacing: 18
                        Preview {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            source: controller.sourceUrl
                            caption: controller.media.width > 0 ? "원본" : ""
                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: !controller.media.width
                                spacing: 20
                                Label { Layout.alignment: Qt.AlignHCenter; text: "영상 속 작은 움직임을\n픽셀아트의 재료로"; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 26; font.bold: true }
                                Button { objectName: "openFile"; Layout.alignment: Qt.AlignHCenter; text: "영상 또는 GIF 선택…"; onClicked: openDialog.open() }
                                Label { Layout.alignment: Qt.AlignHCenter; text: "파일을 이 창에 끌어다 놓아도 됩니다."; color: "#9daec3" }
                            }
                        }
                        Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "원본의 프레임 시간과 투명도를 사용합니다. 영상에 이미 사라진 투명도와 색상은 자동으로 복구되지 않습니다."; color: "#9daec3" }
                    }
                }
                // 2. Trim
                ColumnLayout {
                    spacing: 12
                    Preview { Layout.fillWidth: true; Layout.fillHeight: true; source: controller.sourceUrl; caption: "원본 · " + controller.sourceTime.toFixed(3) + "초" }
                    Slider { Layout.fillWidth: true; from: 0; to: controller.media.duration || 1; value: controller.sourceTime; onPressedChanged: if (!pressed) controller.seek(value) }
                    RowLayout {
                        Button { text: "◀ 이전 프레임"; onClicked: controller.step(-1) }
                        Button { text: "다음 프레임 ▶"; onClicked: controller.step(1) }
                        Item { Layout.fillWidth: true }
                        Button { text: "여기서 시작"; onClicked: window.set("start", controller.sourceTime) }
                        Button { text: "여기까지"; onClicked: window.set("end", controller.sourceTime) }
                    }
                    RowLayout {
                        NumberField { Layout.fillWidth: true; label: "시작 (초)"; value: controller.settings.start || 0; maximum: controller.media.duration || 1; decimals: 3; onEdited: number => window.set("start", number) }
                        NumberField { Layout.fillWidth: true; label: "끝 (초)"; value: controller.settings.end || 0; maximum: controller.media.duration || 1; decimals: 3; onEdited: number => window.set("end", number) }
                        Label { Layout.preferredWidth: 160; text: "선택 " + Number((controller.settings.end || 0) - (controller.settings.start || 0)).toFixed(3) + "초\n최대 60초"; color: "#aab8ca" }
                    }
                }
                // 3. Spatial
                RowLayout {
                    spacing: 18
                    Preview {
                        Layout.fillWidth: true; Layout.fillHeight: true; source: controller.sourceUrl
                        caption: "드래그하여 자르기"; cropEnabled: true
                        sourceWidth: controller.media.width || 1; sourceHeight: controller.media.height || 1
                        cropRect: Qt.rect(controller.settings.x || 0, controller.settings.y || 0, controller.settings.cropWidth || 1, controller.settings.cropHeight || 1)
                        onCropped: (x, y, w, h) => window.applyCrop(x, y, w, h)
                    }
                    ColumnLayout {
                        Layout.preferredWidth: 242; Layout.minimumWidth: 242; Layout.maximumWidth: 242
                        Label { text: "원본에서 자를 영역"; font.bold: true }
                        RowLayout {
                            NumberField { Layout.fillWidth: true; label: "X"; value: controller.settings.x || 0; maximum: (controller.media.width || 1) - 1; onEdited: number => window.set("x", number) }
                            NumberField { Layout.fillWidth: true; label: "Y"; value: controller.settings.y || 0; maximum: (controller.media.height || 1) - 1; onEdited: number => window.set("y", number) }
                        }
                        RowLayout {
                            NumberField { Layout.fillWidth: true; label: "너비"; minimum: 1; maximum: controller.media.width || 1; value: controller.settings.cropWidth || 1; onEdited: number => window.applyCrop(controller.settings.x, controller.settings.y, number, controller.settings.cropHeight) }
                            NumberField { Layout.fillWidth: true; label: "높이"; minimum: 1; maximum: controller.media.height || 1; value: controller.settings.cropHeight || 1; onEdited: number => window.applyCrop(controller.settings.x, controller.settings.y, controller.settings.cropWidth, number) }
                        }
                        Button { text: "전체 영역"; onClicked: window.applyCrop(0, 0, controller.media.width, controller.media.height) }
                        Item { Layout.preferredHeight: 16 }
                        Label { text: "출력 픽셀 크기"; font.bold: true }
                        RowLayout {
                            NumberField { Layout.fillWidth: true; label: "너비"; minimum: 1; maximum: 512; value: controller.settings.width || 128; onEdited: number => window.sizeWidth(number) }
                            NumberField { Layout.fillWidth: true; label: "높이"; minimum: 1; maximum: 512; value: controller.settings.height || 128; onEdited: number => window.sizeHeight(number) }
                        }
                        CheckBox { objectName: "lockAspect"; text: "비율 유지"; checked: lockAspect; onClicked: { lockAspect = checked; if (checked && divisorActive) window.divideSize(sizeDivisor) } }
                        Label { visible: lockAspect; text: divisorActive ? sizeDivisor + "x · 자르기 영역 ÷ " + sizeDivisor : "배수로 나누기 · 직접 입력 중" }
                        Slider {
                            objectName: "sizeDivisor"
                            Layout.fillWidth: true; visible: lockAspect; enabled: lockAspect
                            from: 1; to: 16; stepSize: 1; snapMode: Slider.SnapAlways
                            value: window.sizeDivisor
                            onMoved: window.divideSize(value)
                        }
                        Label {
                            visible: controller.settings.width > 512 || controller.settings.height > 512
                            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: "#ffb5a7"
                            text: "출력이 512픽셀을 넘습니다. 배수를 높이거나 자르기 영역을 줄이세요."
                        }
                        ComboBox { Layout.fillWidth: true; model: ["또렷하게 · 최근접", "부드럽게 · Lanczos"]; currentIndex: controller.settings.nearest === false ? 1 : 0; onActivated: window.set("nearest", currentIndex === 0) }
                        Label { Layout.fillWidth: true; text: "가로·세로 최대 512픽셀\n최종 결과는 다음 단계에서 비교합니다."; wrapMode: Text.WordWrap; color: "#9daec3"; font.pixelSize: 12 }
                        Item { Layout.fillHeight: true }
                    }
                }
                // 4. Timing
                ColumnLayout {
                    spacing: 16
                    Label { text: "프레임 간격"; font.pixelSize: 18; font.bold: true }
                    RadioButton { text: "원본 프레임 시간 유지 (권장)"; checked: !controller.settings.fps; onClicked: window.set("fps", 0) }
                    RowLayout {
                        RadioButton { text: "일정한 FPS로 다시 샘플링"; checked: controller.settings.fps > 0; onClicked: window.set("fps", 12) }
                        NumberField { Layout.preferredWidth: 110; label: "FPS"; enabled: controller.settings.fps > 0; minimum: 1; maximum: 60; decimals: 3; value: controller.settings.fps || 12; onEdited: number => window.set("fps", number) }
                    }
                    Label { Layout.fillWidth: true; text: "원본 유지는 각 프레임의 표시 시간을 따릅니다. FPS를 낮추면 움직임 일부가 생략되지만 전체 재생 길이는 유지됩니다."; wrapMode: Text.WordWrap; color: "#9daec3" }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#303b4c" }
                    CheckBox { text: "연속된 동일 프레임 합치기"; checked: controller.settings.merge === true; onClicked: window.set("merge", checked) }
                    RowLayout {
                        NumberField { Layout.preferredWidth: 160; label: "유사 프레임 허용 오차"; value: controller.settings.mergeTolerance || 0; maximum: 16; enabled: controller.settings.merge === true; onEdited: number => window.set("mergeTolerance", number) }
                        Label { Layout.fillWidth: true; text: "0이면 픽셀이 정확히 같을 때만 합칩니다.\n값을 높이면 작은 움직임이나 색 변화가 사라질 수 있습니다."; wrapMode: Text.WordWrap; color: "#9daec3" }
                    }
                    NumberField { Layout.preferredWidth: 190; label: "재생 횟수 (0 = 계속 반복)"; maximum: 4294967295; value: controller.settings.plays || 0; onEdited: number => window.set("plays", number) }
                    Item { Layout.fillHeight: true }
                    Label { Layout.fillWidth: true; text: "결과 한도: 600프레임 · 비압축 RGBA 64 MiB\n한도를 넘으면 저장 전에 알려 드립니다. 구간·크기·FPS를 줄여 다시 시도할 수 있습니다."; wrapMode: Text.WordWrap; color: "#9daec3" }
                }
                // 5. Color
                ColumnLayout {
                    spacing: 16
                    Label { text: "구간 전체에 같은 색상 팔레트 적용"; font.pixelSize: 18; font.bold: true }
                    ComboBox {
                        Layout.preferredWidth: 280
                        model: ["원본 색상 유지", "16색", "32색", "64색", "128색", "256색"]
                        property var values: [0, 16, 32, 64, 128, 256]
                        currentIndex: Math.max(0, values.indexOf(controller.settings.colors || 0))
                        onActivated: window.set("colors", values[currentIndex])
                    }
                    CheckBox { text: "디더링 · 작은 패턴으로 색을 섞기"; enabled: controller.settings.colors > 0; checked: controller.settings.dither === true; onClicked: window.set("dither", checked) }
                    Label { Layout.fillWidth: true; text: "프레임마다 색상이 달라지는 깜박임을 줄이기 위해 하나의 팔레트를 공유합니다. 투명도는 색상 수 제한과 별도로 유지됩니다."; wrapMode: Text.WordWrap; color: "#9daec3" }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#303b4c" }
                    CheckBox { text: "배경색을 투명하게 바꾸기"; checked: controller.settings.key === true; onClicked: window.set("key", checked) }
                    RowLayout {
                        enabled: controller.settings.key === true
                        Rectangle { width: 34; height: 34; radius: 5; color: controller.settings.keyColor || "#00ff00"; border.color: "#b2c4d9" }
                        Button { objectName: "pickBackground"; text: "배경색 선택…"; onClicked: pickDialog.open() }
                        NumberField { Layout.preferredWidth: 140; label: "색상 허용 오차"; maximum: 255; value: controller.settings.keyTolerance || 0; onEdited: number => window.set("keyTolerance", number) }
                    }
                    Label { Layout.fillWidth: true; text: "단색 배경의 영상에 적합합니다. 같은 색의 피사체도 투명해질 수 있으므로 결과를 꼭 확인하세요."; wrapMode: Text.WordWrap; color: "#9daec3" }
                    Item { Layout.fillHeight: true }
                    Label { text: "설정이 준비되면 ‘미리보기 만들기’를 누르세요."; color: "#83e2c3" }
                }
                // 6. Preview and export
                ColumnLayout {
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 14
                        Preview { Layout.fillWidth: true; Layout.fillHeight: true; source: controller.originalUrl; caption: controller.comparisonBusy ? "원본 프레임 읽는 중…" : "원본 · " + controller.media.width + " × " + controller.media.height }
                        Preview { Layout.fillWidth: true; Layout.fillHeight: true; source: controller.resultUrl; caption: "변환 결과" }
                    }
                    RowLayout {
                        Button { objectName: "playResult"; text: playing ? "Ⅱ 일시 정지" : "▶ 재생"; onClicked: { completedLoops = 0; playing = !playing } }
                        Button { text: "◀"; onClicked: { playing = false; controller.selectFrame(controller.frameIndex - 1) } }
                        Slider { Layout.fillWidth: true; from: 0; to: Math.max(0, controller.frameCount - 1); stepSize: 1; value: controller.frameIndex; onMoved: { playing = false; controller.selectFrame(value) } }
                        Button { text: "▶"; onClicked: { playing = false; controller.selectFrame(controller.frameIndex + 1) } }
                        Label { text: (controller.frameIndex + 1) + " / " + controller.frameCount + "  ·  " + controller.frameDelay + " ms"; font.pixelSize: 12 }
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: (controller.result.width || 0) + " × " + (controller.result.height || 0) + "  ·  " + (controller.result.frames || 0) + "프레임  ·  " + Number(controller.result.duration || 0).toFixed(3) + "초  ·  파일 " + (Number(controller.result.bytes || 0) / 1024).toFixed(1) + " KiB  ·  RGBA " + (Number(controller.result.memory || 0) / 1048576).toFixed(2) + " MiB"
                        color: "#83e2c3"
                    }
                    Label { Layout.fillWidth: true; visible: controller.savedPath.length > 0; text: controller.savedPath; elide: Text.ElideMiddle; color: "#9daec3" }
                    Button { visible: controller.savedPath.length > 0; text: "저장 폴더 열기"; onClicked: controller.reveal() }
                }
            }
            Label {
                Layout.fillWidth: true
                visible: controller.error.length > 0
                text: controller.error
                color: "#ffb5a7"; wrapMode: Text.WrapAnywhere
                maximumLineCount: 4; elide: Text.ElideRight
            }
            ProgressBar { Layout.fillWidth: true; visible: controller.busy; value: controller.progress; indeterminate: controller.progress === 0 }
            RowLayout {
                Layout.fillWidth: true
                Label { Layout.fillWidth: true; text: controller.status; elide: Text.ElideMiddle; color: "#9daec3"; font.pixelSize: 12 }
                Button { text: "취소"; visible: controller.busy; onClicked: controller.cancel() }
                Button { text: "이전"; visible: page > 0; enabled: !controller.busy; onClicked: { playing = false; page-- } }
                Button {
                    objectName: "nextStep"
                    text: page < 4 ? "다음 →" : page === 4 ? "미리보기 만들기" : "PAPNG 저장…"
                    highlighted: true
                    enabled: !controller.busy && controller.media.width > 0 && (page < 5 || controller.ready)
                    onClicked: {
                        playing = false
                        if (page < 4) page++
                        else if (page === 4) controller.generate()
                        else { saveDialog.selectedFile = controller.suggestedOutput(); saveDialog.open() }
                    }
                }
            }
        }
    }
    DropArea {
        anchors.fill: parent
        enabled: !controller.busy
        onDropped: drop => { if (drop.hasUrls && drop.urls.length === 1) { page = 0; playing = false; controller.open(drop.urls[0]) } }
    }
}
