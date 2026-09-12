import QtQuick

Rectangle {
  id: root
  property int txx: 0
  property int tyy: 0
  property int zz: 13
  property string src: ""
  width: 257
  height: 257
  color: "#151b23"
  Image {
    anchors.fill: parent
    source: root.src
    sourceSize.width: 257
    sourceSize.height: 257
    fillMode: Image.PreserveAspectFit
    cache: false
    onStatusChanged: { if (status === Image.Error) console.log("yerrr: tile missing " + source) }
  }
}