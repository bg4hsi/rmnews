"""Draw the 100x100 launcher icon (needs PySide6): a folded newspaper."""
import sys
from PySide6.QtGui import QGuiApplication, QImage, QPainter, QPen, QColor, QFont
from PySide6.QtCore import Qt, QRectF

app = QGuiApplication(sys.argv[:1])
img = QImage(100, 100, QImage.Format_ARGB32)
img.fill(Qt.transparent)
p = QPainter(img)
p.setRenderHint(QPainter.Antialiasing)
p.setPen(QPen(QColor("black"), 5))
p.setBrush(QColor("white"))
p.drawRoundedRect(QRectF(12, 14, 76, 72), 8, 8)
p.setBrush(QColor("black"))
p.setPen(Qt.NoPen)
p.drawRect(QRectF(22, 26, 24, 22))
for y in (28, 38, 46):
    p.drawRect(QRectF(52, y, 26, 4))
for y in (56, 64, 72):
    p.drawRect(QRectF(22, y, 56, 4))
p.end()
img.save(sys.argv[1])
