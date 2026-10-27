import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "../js/Model.js" as Model

// One screen's reminder: a small card placed randomly near the centre, above
// fullscreen windows. A blinking eye; the look-far break adds a countdown.
PanelWindow {
  id: win

  property var service: null
  readonly property bool on: !!service && service.showing !== ""
  // Kept through the fade-out, after the service has cleared `showing`.
  property string kind: ""
  readonly property bool far: kind === "far"
  property real remaining: 0
  // Offsets as fractions of the free space either side of centre (Model.nearCenter).
  property real fx: 0
  property real fy: 0

  Connections {
    target: win.service
    function onShowingChanged() {
      if (!win.service.showing) return
      win.kind = win.service.showing
      win.fx = Model.nearCenter(Math.random(), Math.random())
      win.fy = Model.nearCenter(Math.random(), Math.random())
      if (win.far) {
        countdown.from = win.service.cfg.farShowMs / 1000
        countdown.duration = win.service.cfg.farShowMs
        countdown.restart()
      }
    }
  }

  NumberAnimation {
    id: countdown
    target: win
    property: "remaining"
    to: 0
  }

  visible: on || card.opacity > 0
  // Full-screen and transparent, so the card can sit anywhere on the output.
  anchors { top: true; left: true; bottom: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "a-b.eyebreak"
  // Click-through (empty input region) unless clicking dismisses the card.
  mask: Region { item: win.service && win.service.cfg.dismissOnClick ? card : null }

  Rectangle {
    id: card
    x: (win.width - width) / 2 * (1 + win.fx)
    y: (win.height - height) / 2 * (1 + win.fy)
    width: win.far ? Style.space(320) : Style.space(150)
    height: content.implicitHeight + Style.space(40)
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    border.color: Commons.Color.popups.border
    border.width: win.service && !win.service.cfg.showBorder ? 0 : Math.max(1, Style.space(2))
    opacity: win.on && win.service ? win.service.cfg.opacity : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(250) } }

    MouseArea {
      anchors.fill: parent
      enabled: !!win.service && win.service.cfg.dismissOnClick
      cursorShape: Qt.PointingHandCursor
      onClicked: win.service.dismiss()
    }

    Column {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(12)

      Eye {
        id: eye
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(96)
        height: Style.space(56)
        lineColor: Commons.Color.foreground
        irisColor: Commons.Color.accent

        SequentialAnimation on openness {
          running: win.visible && !Style.reduceMotion
          loops: Animation.Infinite
          onRunningChanged: if (!running) eye.openness = 1
          PauseAnimation { duration: 500 }
          NumberAnimation { to: 0.04; duration: 110; easing.type: Easing.InQuad }
          NumberAnimation { to: 1; duration: 180; easing.type: Easing.OutQuad }
          PauseAnimation { duration: 700 }
        }
      }

      Text {
        visible: win.far
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: "Look ~6 m (20 ft) away"
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        visible: win.far
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Math.ceil(win.remaining) + " s"
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Rectangle {
        visible: win.far
        anchors.horizontalCenter: parent.horizontalCenter
        width: Style.space(240)
        height: Style.space(4)
        radius: height / 2
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.15)

        Rectangle {
          height: parent.height
          radius: parent.radius
          color: Commons.Color.accent
          width: countdown.from > 0 ? parent.width * win.remaining / countdown.from : 0
        }
      }
    }
  }
}
