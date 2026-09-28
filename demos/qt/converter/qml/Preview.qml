import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property alias source: picture.source
    property string caption: ""
    property bool cropEnabled: false
    property bool pickEnabled: false
    signal pixelPicked(int x, int y)
    property int sourceWidth: 1
    property int sourceHeight: 1
    property rect cropRect: Qt.rect(0, 0, sourceWidth, sourceHeight)
    signal cropped(int x, int y, int w, int h)
    color: "#12171f"
    border.color: "#303b4c"
    radius: 12
    clip: true
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let c = getContext("2d"); c.clearRect(0, 0, width, height)
            for (let y = 0; y < height; y += 12)
                for (let x = 0; x < width; x += 12) {
                    c.fillStyle = ((x / 12 + y / 12) % 2) ? "#1c2531" : "#242e3b"
                    c.fillRect(x, y, 12, 12)
                }
        }
    }
    Image {
        id: picture
        anchors.fill: parent
        anchors.margins: 24
        fillMode: Image.PreserveAspectFit
        smooth: false
        cache: false
        asynchronous: false
    }
    Item {
        id: viewport
        objectName: "imageViewport"
        x: picture.x + (picture.width - picture.paintedWidth) / 2
        y: picture.y + (picture.height - picture.paintedHeight) / 2
        width: picture.paintedWidth
        height: picture.paintedHeight
        Rectangle {
            visible: root.cropEnabled && picture.status === Image.Ready
            x: root.cropRect.x / Math.max(1, root.sourceWidth) * viewport.width
            y: root.cropRect.y / Math.max(1, root.sourceHeight) * viewport.height
            width: root.cropRect.width / Math.max(1, root.sourceWidth) * viewport.width
            height: root.cropRect.height / Math.max(1, root.sourceHeight) * viewport.height
            color: "#1855ddbb"
            border.color: "#76edc0"
            border.width: 2
        }
        MouseArea {
            anchors.fill: parent
            enabled: (root.cropEnabled || root.pickEnabled) && picture.status === Image.Ready
            cursorShape: Qt.CrossCursor
            property point origin
            onPressed: mouse => { origin = Qt.point(mouse.x, mouse.y) }
            onReleased: mouse => {
                if (root.pickEnabled) {
                    if (mouse.x >= 0 && mouse.y >= 0 && mouse.x < width && mouse.y < height)
                        root.pixelPicked(Math.min(root.sourceWidth - 1, Math.floor(mouse.x / width * root.sourceWidth)),
                                         Math.min(root.sourceHeight - 1, Math.floor(mouse.y / height * root.sourceHeight)))
                    return
                }
                let x = Math.floor(Math.max(0, Math.min(origin.x, mouse.x)) / width * root.sourceWidth)
                let y = Math.floor(Math.max(0, Math.min(origin.y, mouse.y)) / height * root.sourceHeight)
                let right = Math.ceil(Math.min(width, Math.max(origin.x, mouse.x)) / width * root.sourceWidth)
                let bottom = Math.ceil(Math.min(height, Math.max(origin.y, mouse.y)) / height * root.sourceHeight)
                if (right > x && bottom > y) root.cropped(x, y, right - x, bottom - y)
            }
        }
    }
    Rectangle {
        visible: root.caption.length > 0
        x: 12; y: 12; height: 26; width: label.implicitWidth + 20
        color: "#dc111923"; radius: 6
        Label { id: label; anchors.centerIn: parent; text: root.caption; font.pixelSize: 12; color: "#d5dfea" }
    }
}
