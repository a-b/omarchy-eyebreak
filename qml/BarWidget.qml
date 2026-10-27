import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "../js/Model.js" as Model

// Eye icon (shut while paused, blinking while a reminder shows); the tooltip
// shows the next look-far break; left click opens the pause and settings menu.
BarWidget {
  id: root
  moduleName: "a-b.eyebreak"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool paused: !!service && service.paused
  readonly property var cfg: Model.config(settings)
  property bool popupOpen: false

  function close() { popupOpen = false }

  // The service lives apart from the widget, so hand it the settings.
  function pushSettings() { if (service) service.applySettings(settings) }
  onServiceChanged: pushSettings()
  onSettingsChanged: pushSettings()

  // Writes keys of this widget's shell.json entry, keeping the others.
  function setSettings(values) {
    var entry = { id: moduleName }
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    for (var v in values) entry[v] = values[v]
    settings = entry
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, entry)
  }
  function setSetting(key, value) {
    var values = {}
    values[key] = value
    setSettings(values)
  }

  // Interval slider value: 0 is the leftmost position and means off.
  function setInterval(enabledKey, minutesKey, minutes) {
    var values = {}
    values[enabledKey] = minutes > 0
    if (minutes > 0) values[minutesKey] = minutes
    setSettings(values)
  }
  function intervalLabel(name, minutes) {
    return name + "  " + (minutes > 0 ? minutes + " min" : "off")
  }

  // A label over a slider; shell.json is written once, on release.
  component SliderRow: Item {
    id: row
    property string label: ""
    property string hint: ""   // recommended value, shown dimmed at the right
    property var bar: null
    property alias minimum: slider.minimum
    property alias maximum: slider.maximum
    property alias step: slider.step
    property alias value: slider.value
    // PanelSlider leaves snapping to the caller.
    readonly property int liveValue: Math.round(slider.liveValue / slider.step) * slider.step
    signal released(int value)

    height: rowLabel.implicitHeight + slider.implicitHeight + Style.space(6)

    Text {
      id: rowLabel
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.controlPaddingX
      textFormat: Text.PlainText
      text: row.label
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.controlPaddingX
      anchors.baseline: rowLabel.baseline
      textFormat: Text.PlainText
      text: row.hint
      color: Commons.Color.foreground
      opacity: 0.5
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    PanelSlider {
      id: slider
      bar: row.bar
      anchors.top: rowLabel.bottom
      anchors.topMargin: Style.space(6)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.spacing.controlPaddingX
      anchors.rightMargin: Style.spacing.controlPaddingX
      integer: true
      onReleased: function(v) { row.released(Math.round(v / slider.step) * slider.step) }
    }
  }

  function statusText() {
    if (!service) return "Eye Break: service not running"
    if (paused) return "Eye Break paused until " + Model.clock(service.state.pausedUntil)
    if (!cfg.farEnabled && !cfg.blinkEnabled) return "Eye Break off"
    if (!cfg.farEnabled) return "Blink nudges only"
    return "Look-far break in " + Model.fmt(service.farRemainingMs)
  }

  // Menu actions need the service; without it they only close the menu.
  function act(fn) { if (service) fn(); popupOpen = false }

  implicitWidth: vertical ? barSize : Style.bar.iconSlot
  implicitHeight: vertical ? Style.bar.iconSlot : barSize

  // Same eye as the reminder card. Shut while paused; blinks while a reminder shows.
  Eye {
    id: icon
    anchors.centerIn: parent
    width: Math.round(Style.bar.iconSize * 1.35)
    height: Math.round(Style.bar.iconSize * 0.85)
    lineWidth: Math.max(1.5, Style.bar.iconSize / 10)
    lineColor: root.bar ? root.bar.barForeground : Commons.Color.foreground
    closed: root.paused
    opacity: root.paused ? 0.6 : 1

    SequentialAnimation on openness {
      running: !!root.service && root.service.showing !== "" && !Style.reduceMotion
      loops: Animation.Infinite
      onRunningChanged: if (!running) icon.openness = 1
      PauseAnimation { duration: 500 }
      NumberAnimation { to: 0.04; duration: 110; easing.type: Easing.InQuad }
      NumberAnimation { to: 1; duration: 180; easing.type: Easing.OutQuad }
      PauseAnimation { duration: 700 }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
    onEntered: if (root.bar) root.bar.showTooltip(root, root.statusText())
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(menu.implicitHeight)

    Column {
      id: menu
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.popupOpen ? root.statusText() : ""
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
        bottomPadding: Style.space(6)
      }

      Repeater {
        model: root.paused
          ? [{ label: "Resume", choice: "" }]
          : [{ label: "Pause 15 min", choice: "15" }, { label: "Pause 1 h", choice: "60" },
             { label: "Pause until tomorrow", choice: "tomorrow" }]
        Button {
          required property var modelData
          width: menu.width
          leftAlign: true
          text: modelData.label
          onClicked: root.act(function() {
            if (modelData.choice) root.service.pause(modelData.choice)
            else root.service.resume()
          })
        }
      }

      Button {
        width: menu.width
        leftAlign: true
        text: "Take a look-far break now"
        onClicked: root.act(function() { root.service.show("far") })
      }

      PanelSeparator { width: menu.width }

      // Bounds match the manifest schema.
      SliderRow {
        width: menu.width
        bar: root.bar
        label: root.intervalLabel("Blink", liveValue)
        hint: "rec. " + Model.DEFAULTS.blinkEveryMinutes + " min"
        minimum: 0
        maximum: 60
        step: 1
        value: root.cfg.blinkEnabled ? root.cfg.blinkEveryMs / 60000 : 0
        onReleased: function(v) { root.setInterval("blinkEnabled", "blinkEveryMinutes", v) }
      }

      SliderRow {
        width: menu.width
        bar: root.bar
        label: root.intervalLabel("Look far", liveValue)
        hint: "rec. " + Model.DEFAULTS.farEveryMinutes + " min"
        minimum: 0
        maximum: 120
        step: 1
        value: root.cfg.farEnabled ? root.cfg.farEveryMs / 60000 : 0
        onReleased: function(v) { root.setInterval("farEnabled", "farEveryMinutes", v) }
      }

      SliderRow {
        width: menu.width
        bar: root.bar
        label: "Opacity  " + liveValue + " %"
        hint: "rec. " + Model.DEFAULTS.opacityPercent + " %"
        minimum: 20
        maximum: 100
        step: 5
        value: Math.round(root.cfg.opacity * 100)
        onReleased: function(v) { root.setSetting("opacityPercent", v) }
      }

      Item {
        width: menu.width
        height: dismissToggle.implicitHeight + Style.space(8)

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Click to dismiss"
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        ToggleSwitch {
          id: dismissToggle
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          checked: root.cfg.dismissOnClick
          onToggled: root.setSetting("dismissOnClick", !root.cfg.dismissOnClick)
        }
      }
    }
  }
}
