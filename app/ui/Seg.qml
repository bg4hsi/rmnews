import QtQuick 2.15

// Segmented switch: one rounded frame, the selected segment filled.
Rectangle {
    id: seg
    property var options: []            // [[value, label], ...]
    property string value: ""
    property real u: 1
    property real segWidth: 130 * u
    property color accent: "black"
    signal picked(string v)

    width: options.length * segWidth + 12 * u
    height: 84 * u
    radius: 14 * u
    border.width: 3 * u
    border.color: "black"

    Row {
        anchors.fill: parent
        anchors.margins: 6 * seg.u
        Repeater {
            model: seg.options
            Rectangle {
                width: seg.segWidth
                height: parent.height
                radius: 9 * seg.u
                color: seg.value === modelData[0] ? seg.accent : "white"
                Text {
                    anchors.centerIn: parent
                    text: modelData[1]
                    color: seg.value === modelData[0] ? "white" : "black"
                    font.pixelSize: 30 * seg.u
                    font.family: "Noto Sans SC"
                    font.weight: Font.DemiBold
                }
                MouseArea { anchors.fill: parent; onClicked: seg.picked(modelData[0]) }
            }
        }
    }
}
