import QtQuick 2.15

// One key of Keyboard.qml. Fires on press, so typing doesn't wait for a lift.
Rectangle {
    id: k
    property real u: 1
    property alias text: t.text
    property bool down: false            // drawn inverted (shift on, the OK key)
    signal hit

    radius: 10 * u
    border.width: 3 * u
    border.color: "black"
    color: down ? "black" : "white"

    Text {
        id: t
        anchors.centerIn: parent
        color: k.down ? "white" : "black"
        font.pixelSize: (text.length > 2 ? 30 : 40) * k.u
        font.family: "Noto Sans SC"
        font.weight: Font.Medium
    }

    MouseArea {
        anchors.fill: parent
        onPressed: k.hit()
    }
}
