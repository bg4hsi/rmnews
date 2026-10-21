#!/usr/bin/env python3
"""Run the app on the desktop with PySide6 (Qt 6.10, same as the tablet) and script it.

Usage: run.py WORKDIR STEPS_JSON
  WORKDIR holds data/ (cache, state), dict/ (offline dictionary), fonts/ and shots/.
  STEPS_JSON: [[kind, arg, wait_ms], ...] with kind one of
    js      evaluate arg against the host item (the app is `app`)
    shot    save a screenshot to shots/<arg>
    press / move / release   at [x, y]: a real touch point (like a finger on the tablet), or with
                             "pen" as third item a non-synthesized mouse event, which is how
                             xochitl delivers the Marker
"""
import json
import os
import sys

from PySide6.QtCore import QCoreApplication, QEvent, QPoint, QPointF, Qt, QTimer, QUrl
from PySide6.QtGui import QFontDatabase, QGuiApplication, QMouseEvent
from PySide6.QtQml import QQmlExpression
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.normpath(os.path.join(HERE, "..", "..", "app"))
W = os.path.abspath(sys.argv[1])
steps = json.loads(sys.argv[2])

os.environ.setdefault("QML_XHR_ALLOW_FILE_READ", "1")
os.environ.setdefault("QML_XHR_ALLOW_FILE_WRITE", "1")
app = QGuiApplication(sys.argv[:1])
fonts = os.path.join(W, "fonts")
for f in sorted(os.listdir(fonts)) if os.path.isdir(fonts) else []:
    QFontDatabase.addApplicationFont(os.path.join(fonts, f))
for d in ("data/cache", "shots"):
    os.makedirs(os.path.join(W, d), exist_ok=True)

host = os.path.join(W, "host.qml")
with open(host, "w") as fh:
    fh.write('import QtQuick 2.15\nItem { width: 810; height: 1080\n'
             ' Loader { id: l; anchors.fill: parent; source: "%s" }\n property alias app: l.item }\n'
             % QUrl.fromLocalFile(os.path.join(APP, "ui", "main.qml")).toString())

v = QQuickView()
v.engine().addImportPath(os.path.join(HERE, "imports"))
ctx = v.rootContext()
ctx.setContextProperty("rmnewsDataDir", QUrl.fromLocalFile(os.path.join(W, "data")).toString() + "/")
ctx.setContextProperty("rmnewsDictBase", QUrl.fromLocalFile(os.path.join(W, "dict")).toString() + "/")
v.engine().warnings.connect(lambda ws: [print("QMLWARN", w.toString()) for w in ws])
v.setSource(QUrl.fromLocalFile(host))
v.show()
root = v.rootObject()


def js(code):
    e = QQmlExpression(ctx, root, code)
    r = e.evaluate()
    if e.hasError():
        print("JSERR", code[:60], e.error().toString())
    return r


touch = None


def finger(kind, x, y):
    global touch
    if touch is None:
        touch = QTest.createTouchDevice()
    seq = QTest.touchEvent(v, touch)
    pt = QPoint(int(x), int(y))
    {"press": seq.press, "move": seq.move, "release": seq.release}[kind](0, pt, v)
    seq.commit()


def mouse(kind, x, y, pen):
    if not pen:
        return finger(kind, x, y)
    pt = QPointF(x, y)
    types = {"press": QEvent.MouseButtonPress, "move": QEvent.MouseMove, "release": QEvent.MouseButtonRelease}
    button = Qt.NoButton if kind == "move" else Qt.LeftButton
    buttons = Qt.NoButton if kind == "release" else Qt.LeftButton
    ev = QMouseEvent(types[kind], pt, pt, QPointF(v.mapToGlobal(QPoint(int(x), int(y)))),
                     button, buttons, Qt.NoModifier,
                     Qt.MouseEventNotSynthesized)
    QCoreApplication.sendEvent(v, ev)


def run(i=0):
    if i >= len(steps):
        app.quit()
        return
    kind, arg, wait = steps[i]
    if kind == "js":
        print("JS", arg[:70], "=>", str(js(arg))[:400])
    elif kind == "shot":
        v.grabWindow().save(os.path.join(W, "shots", arg))
        print("SHOT", arg)
    elif kind in ("press", "move", "release"):
        mouse(kind, arg[0], arg[1], len(arg) > 2 and arg[2] == "pen")
    QTimer.singleShot(wait, lambda: run(i + 1))


QTimer.singleShot(500, run)
app.exec()
