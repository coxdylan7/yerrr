import QtQuick
import qs.Commons

Rectangle {
  id: root
  property int txx: 0
  property int tyy: 0
  property int zz: 13
  property string src: ""
  width: 256
  height: 256
  color: Util.alpha(Color.background, 0.95)
  property int retryLeft: 8
  property int attempts: 0
  onSrcChanged: { root.attempts = 0; tileImg.source = ""; tileImg.source = root.src; retryTimer.restart() }
  Timer {
    id: retryTimer
    interval: 900
    repeat: true
    onTriggered: {
      if (tileImg.status === Image.Loading) return
      root.attempts++
      if (root.attempts > root.retryLeft) { retryTimer.stop(); return }
      tileImg.source = ""
      tileImg.source = root.src
    }
  }
  Image {
    id: tileImg
    anchors.fill: parent
    source: root.src
    sourceSize.width: 256
    sourceSize.height: 256
    fillMode: Image.PreserveAspectFit
    cache: false
    asynchronous: true
    onStatusChanged: {
      if (status === Image.Error) { console.log("yerrr: tile missing " + source); retryTimer.start() }
      else if (status === Image.Ready) { retryTimer.stop(); root.attempts = 0 }
    }
  }
}