import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1000000
    property int decimals: 0
    property string suffix: ""
    signal edited(real number)
    spacing: 5
    Layout.minimumWidth: 0
    Label { text: root.label; color: "#aab8ca"; font.pixelSize: 12 }
    TextField {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        implicitWidth: 100
        text: Number(root.value).toFixed(root.decimals)
        selectByMouse: true
        validator: DoubleValidator { bottom: root.minimum; top: root.maximum; decimals: root.decimals; locale: "C"; notation: DoubleValidator.StandardNotation }
        onEditingFinished: {
            let n = Number(text)
            if (acceptableInput && isFinite(n)) root.edited(n)
            text = Qt.binding(() => Number(root.value).toFixed(root.decimals))
        }
        ToolTip.visible: hovered && root.suffix.length > 0
        ToolTip.text: root.suffix
    }
}
