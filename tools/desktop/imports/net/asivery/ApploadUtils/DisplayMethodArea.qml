// Desktop stand-in for AppLoad's DisplayMethodArea (on the tablet it becomes Epaper.ScreenModeItem).
import QtQuick
Item {
    enum Method { UFast, Fast, Animate, Content, UI }
    property int displayMethod: 3
}
