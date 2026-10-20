import QtQuick 2.15

Rectangle {
    id: b
    property alias text: label.text
    property real u: 1
    property bool checked: false
    property bool dim: false
    property color accent: "black"      // fill when checked
    property real fontPx: 34 * u
    signal clicked

    implicitWidth: label.implicitWidth + 56 * u
    implicitHeight: 88 * u
    radius: 12 * u
    border.width: 3 * u
    border.color: checked ? accent : "black"
    color: checked ? accent : "white"
    // Greys dither badly on Gallery 3, so an unavailable button simply disappears.
    opacity: dim ? 0 : 1

    Text {
        id: label
        anchors.centerIn: parent
        color: b.checked ? "white" : "black"
        font.pixelSize: b.fontPx
        font.family: "Noto Sans SC"
        font.weight: Font.Medium
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -8 * b.u
        onClicked: if (!b.dim) b.clicked()
    }
}
