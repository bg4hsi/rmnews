import QtQuick 2.15

// A polyline drawn as rounded, rotated rectangles. xochitl renders Qt Quick with the
// software backend, where QtQuick.Shapes paths don't reach the screen; plain Rectangles do.
Item {
    id: stroke
    property var pts: []                // [Qt.point | {x, y}, ...]
    property color color: "black"
    property real lineWidth: 4

    Repeater {
        model: Math.max(0, stroke.pts.length - 1)
        Rectangle {
            readonly property var a: stroke.pts[index]
            readonly property var b: stroke.pts[index + 1]
            readonly property real dx: b.x - a.x
            readonly property real dy: b.y - a.y
            x: a.x - stroke.lineWidth / 2
            y: a.y - stroke.lineWidth / 2
            width: Math.sqrt(dx * dx + dy * dy) + stroke.lineWidth
            height: stroke.lineWidth
            radius: stroke.lineWidth / 2
            color: stroke.color
            antialiasing: true
            // Rotate about the start point (the centre of the left cap).
            transform: Rotation {
                origin.x: stroke.lineWidth / 2
                origin.y: stroke.lineWidth / 2
                angle: Math.atan2(dy, dx) * 180 / Math.PI
            }
        }
    }
}
