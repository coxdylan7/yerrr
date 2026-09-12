import QtQuick

Rectangle {
  id: root
  property string title: ""
  property string count: ""
  property string subtitle: ""
  signal clicked()
  implicitHeight: 56
  radius: 12
  color: Qt.rgba(0.05, 0.06, 0.09, 0.9)
  border.width: 1
  border.color: Qt.rgba(1, 1, 1, 0.09)
  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.margins: 10
    spacing: 10
    Rectangle {
      width: 40; height: 40; radius: 20
      color: Qt.rgba(0, 0.898, 1, 0.14); border.width: 1; border.color: Qt.rgba(0, 0.898, 1, 0.26)
      Text { anchors.centerIn: parent; text: root.title.slice(0, 1); color: "#00e5ff"; font.family: "Sans Serif"; font.pixelSize: 15; font.bold: true }
    }
    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      width: parent.width - 58
      Text { text: root.title; color: Qt.rgba(1, 1, 1, 0.6); font.family: "Sans Serif"; font.pixelSize: 10; font.bold: true }
      Text { text: root.count; color: "white"; font.family: "Sans Serif"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; width: parent.width }
      Text { text: root.subtitle; color: Qt.rgba(1, 1, 1, 0.5); font.family: "Sans Serif"; font.pixelSize: 9; elide: Text.ElideRight; width: parent.width }
    }
  }
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    onEntered: root.border.color = Qt.rgba(0, 0.9, 1, 0.55)
    onExited: root.border.color = Qt.rgba(1, 1, 1, 0.09)
    onClicked: { root.clicked() }
  }
}