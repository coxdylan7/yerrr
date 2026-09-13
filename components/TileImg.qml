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
  Image {
    anchors.fill: parent
    source: root.src
    sourceSize.width: 256
    sourceSize.height: 256
    fillMode: Image.PreserveAspectFit
    cache: false
    onStatusChanged: { if (status === Image.Error) console.log("yerrr: tile missing " + source) }
  }
}