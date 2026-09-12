import QtQuick

Rectangle {
  id: root
  property string text: ""
  property string value: ""
  signal clicked()
  implicitHeight: 44
  implicitWidth: 170
  radius: 10
  color: Qt.rgba(1, 1, 1, 0.04)
  border.width: 1
  border.color: Qt.rgba(1, 1, 1, 0.08)
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: 8
    spacing: 1
    Text { text: root.text; color: Qt.rgba(1, 1, 1, 0.55); font.family: "Sans Serif"; font.pixelSize: 10; font.bold: true }
    Text { text: root.value; color: "white"; font.family: "Sans Serif"; font.pixelSize: 11; font.bold: true; elide: Text.ElideRight; width: parent.width }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: root.border.color = Qt.rgba(0, 0.9, 1, 0.55)
    onExited: root.border.color = Qt.rgba(1, 1, 1, 0.08)
    onClicked: { root.clicked() }
  }
}