import QtQuick 2.15

// Borderless icon drawn from two strokes, so it stays crisp on e-paper at any scale.
// kind: "close" (an ✕) or "back" (a ‹ chevron followed by an optional label).
Item {
    id: ic
    property string kind: "close"
    property string label: ""
    property real u: 1
    property color color: "black"
    property real stroke: 5 * u
    signal clicked

    implicitWidth: kind === "close" ? 96 * u : glyph.width + (label ? labelText.implicitWidth + 18 * u : 0) + 24 * u
    implicitHeight: 96 * u

    Item {
        id: glyph
        anchors { left: parent.left; leftMargin: ic.kind === "close" ? (ic.width - width) / 2 : 12 * ic.u; verticalCenter: parent.verticalCenter }
        width: ic.kind === "close" ? 44 * ic.u : 24 * ic.u
        height: 44 * ic.u

        // ✕
        Rectangle {
            visible: ic.kind === "close"
            anchors.centerIn: parent
            width: 56 * ic.u; height: ic.stroke; radius: height / 2
            color: ic.color; rotation: 45; antialiasing: true
        }
        Rectangle {
            visible: ic.kind === "close"
            anchors.centerIn: parent
            width: 56 * ic.u; height: ic.stroke; radius: height / 2
            color: ic.color; rotation: -45; antialiasing: true
        }

        // ‹  (two strokes meeting at the left middle)
        Rectangle {
            visible: ic.kind === "back"
            x: 0; y: parent.height / 2 - height / 2
            width: 30 * ic.u; height: ic.stroke; radius: height / 2
            transformOrigin: Item.Left
            color: ic.color; rotation: -45; antialiasing: true
        }
        Rectangle {
            visible: ic.kind === "back"
            x: 0; y: parent.height / 2 - height / 2
            width: 30 * ic.u; height: ic.stroke; radius: height / 2
            transformOrigin: Item.Left
            color: ic.color; rotation: 45; antialiasing: true
        }
    }

    Text {
        id: labelText
        visible: ic.label !== ""
        anchors { left: glyph.right; leftMargin: 18 * ic.u; verticalCenter: parent.verticalCenter }
        text: ic.label
        color: ic.color
        font.pixelSize: 36 * ic.u
        font.family: "Noto Sans SC"
        font.weight: Font.DemiBold
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -12 * ic.u
        onClicked: ic.clicked()
    }
}
