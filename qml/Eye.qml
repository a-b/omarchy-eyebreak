import QtQuick

// The Eye Break eye, shared by the bar icon and the reminder cards.
// Open: almond outline, filled iris, pupil cut out so the surface shows
// through. Closed (paused): a lowered lid with three lashes.
Canvas {
  id: eye

  property color lineColor: "white"
  property color irisColor: lineColor
  property real lineWidth: 2
  property real openness: 1   // 0 shut .. 1 open, animated by the owner
  property bool closed: false

  onOpennessChanged: requestPaint()
  onClosedChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onIrisColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    var w = width, h = height, m = lineWidth, mid = h / 2
    ctx.reset()
    ctx.lineWidth = lineWidth
    ctx.lineCap = "round"
    ctx.strokeStyle = lineColor

    if (closed) {
      ctx.beginPath()
      ctx.moveTo(m, mid * 0.8)
      ctx.quadraticCurveTo(w / 2, h - m, w - m, mid * 0.8)
      ctx.stroke()
      // Lashes hang from the lid's lower curve.
      var lashes = [[0.27, 0.66], [0.5, 0.74], [0.73, 0.66]]
      for (var i = 0; i < lashes.length; i++) {
        var x = w * lashes[i][0], y = h * lashes[i][1]
        ctx.beginPath()
        ctx.moveTo(x, y)
        ctx.lineTo(x + (lashes[i][0] - 0.5) * w * 0.25, h - m / 2)
        ctx.stroke()
      }
      return
    }

    var lid = (mid - m) * 2 * Math.max(0.04, openness)
    ctx.beginPath()
    ctx.moveTo(m, mid)
    ctx.quadraticCurveTo(w / 2, mid - lid, w - m, mid)
    ctx.quadraticCurveTo(w / 2, mid + lid, m, mid)
    ctx.closePath()
    ctx.stroke()
    ctx.save()
    ctx.clip()
    ctx.beginPath()
    ctx.arc(w / 2, mid, h * 0.3, 0, 2 * Math.PI)
    ctx.fillStyle = irisColor
    ctx.fill()
    ctx.globalCompositeOperation = "destination-out"
    ctx.beginPath()
    ctx.arc(w / 2, mid, h * 0.13, 0, 2 * Math.PI)
    ctx.fill()
    ctx.restore()
  }
}
