import QtQuick 2.15

// A small on-screen keyboard for search terms and catalog addresses. AppLoad's own virtual
// keyboard only serves external (framebuffer) apps, so QML apps bring their own.
// Keys react on press: e-paper has no hover and a tap should feel immediate.
Rectangle {
    id: kb
    property real u: 1
    property string text: ""
    property bool masked: false          // passwords
    property string label: ""            // what is being typed
    property string okText: "OK"
    property string cancelText: "Cancel"
    property bool shift: false
    property bool symbols: false
    signal accepted(string text)
    signal canceled

    color: "white"
    border.width: 3 * u
    border.color: "black"
    implicitHeight: col.implicitHeight + 48 * u

    readonly property var letters: [
        "1234567890",
        "qwertyuiop",
        "asdfghjkl",
        "zxcvbnm"
    ]
    readonly property var syms: [
        "1234567890",
        "-/:;()&@\"'",
        ".,?!_=+#%",
        "~*[]<>|\\"
    ]
    readonly property real keyW: (width - 48 * u - 9 * 10 * u) / 10
    readonly property real keyH: 92 * u

    function press(k) {
        if (k === "⌫") { text = text.slice(0, -1); return; }
        if (k === "⇧") { shift = !shift; return; }
        if (k === "#+=") { symbols = !symbols; return; }
        if (k === "abc") { symbols = false; return; }
        if (k === "space") { text += " "; return; }
        text += shift ? k.toUpperCase() : k;
        shift = false;
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 * kb.u }
        spacing: 10 * kb.u

        Text {
            visible: kb.label !== ""
            text: kb.label
            font.pixelSize: 28 * kb.u
            font.family: "Noto Sans SC"
            font.weight: Font.Medium
        }

        // The line being typed, with a block caret.
        Rectangle {
            width: parent.width
            height: 96 * kb.u
            border.width: 3 * kb.u
            border.color: "black"
            radius: 10 * kb.u
            Text {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 22 * kb.u }
                text: (kb.masked ? kb.text.replace(/./g, "•") : kb.text) + "▏"
                elide: Text.ElideLeft
                font.pixelSize: 40 * kb.u
                font.family: "Noto Sans"
            }
        }

        Repeater {
            model: kb.symbols ? kb.syms : kb.letters
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10 * kb.u
                Repeater {
                    model: modelData.split("")
                    KeyCap {
                        u: kb.u
                        width: kb.keyW
                        height: kb.keyH
                        text: kb.shift ? modelData.toUpperCase() : modelData
                        onHit: kb.press(modelData)
                    }
                }
                // Row 4 ends with backspace, as on a phone.
                KeyCap {
                    visible: index === 3
                    u: kb.u
                    width: kb.keyW * 1.6
                    height: kb.keyH
                    text: "⌫"
                    onHit: kb.press("⌫")
                }
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 * kb.u
            KeyCap { u: kb.u; width: kb.keyW * 1.4; height: kb.keyH; text: "⇧"; down: kb.shift; onHit: kb.press("⇧") }
            KeyCap { u: kb.u; width: kb.keyW * 1.4; height: kb.keyH; text: kb.symbols ? "abc" : "#+="; onHit: kb.press(kb.symbols ? "abc" : "#+=") }
            KeyCap { u: kb.u; width: kb.keyW * 1.0; height: kb.keyH; text: "."; onHit: kb.press(".") }
            KeyCap { u: kb.u; width: kb.keyW * 2.6; height: kb.keyH; text: " "; onHit: kb.press("space") }
            KeyCap { u: kb.u; width: kb.keyW * 1.0; height: kb.keyH; text: "/"; onHit: kb.press("/") }
            KeyCap { u: kb.u; width: kb.keyW * 2.2; height: kb.keyH; text: kb.cancelText; onHit: kb.canceled() }
        }

        KeyCap {
            width: parent.width
            height: kb.keyH
            u: kb.u
            text: kb.okText
            down: true
            onHit: kb.accepted(kb.text)
        }
    }
}
