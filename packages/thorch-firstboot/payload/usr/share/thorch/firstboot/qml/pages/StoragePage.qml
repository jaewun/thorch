import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

SetupPage {
    id: page

    required property var flow
    required property int optionMaxWidth

    title: qsTr("Choose Where Thorch Runs")
    description: qsTr("Run Thorch from this SD card using all available space, or move Thorch onto the device's internal storage.")

    ColumnLayout {
        spacing: 14
        Layout.maximumWidth: page.optionMaxWidth

        ChoiceRow {
            text: qsTr("Run from this SD card")
            checked: page.flow.installChoice === "expand-sd"
            onClicked: page.flow.installChoice = "expand-sd"
        }

        ChoiceRow {
            text: qsTr("Install to internal storage")
            checked: page.flow.installChoice === "install-internal"
            onClicked: page.flow.installChoice = "install-internal"
        }

        RowLayout {
            visible: page.flow.installChoice === "install-internal"
            Layout.fillWidth: true
            spacing: 14

            Label {
                text: qsTr("Android userdata to keep")
                color: "#89a0aa"
                font.pixelSize: 17
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            SpinBox {
                id: androidKeepSpin

                from: 1
                to: 512
                value: page.flow.androidUserdataKeepGib
                editable: true
                font.pixelSize: 18
                Layout.preferredWidth: 116

                onValueModified: page.flow.androidUserdataKeepGib = value
            }

            Label {
                text: qsTr("GiB")
                color: "#f6fafc"
                font.pixelSize: 17
            }
        }
    }
}
