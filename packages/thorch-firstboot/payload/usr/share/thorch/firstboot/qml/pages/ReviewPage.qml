import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

SetupPage {
    id: page

    required property var flow
    required property int optionMaxWidth
    required property int pageMaxWidth

    title: qsTr("Review Your Choices")

    ColumnLayout {
        spacing: 16
        Layout.maximumWidth: page.optionMaxWidth
        Layout.fillWidth: true

        ReviewRow {
            label: qsTr("Wi-Fi")
            value: page.flow.wifiReviewLabel()
        }

        ReviewRow {
            label: qsTr("Storage")
            value: page.flow.storageChoiceLabel(page.flow.installChoice)
        }

        ReviewRow {
            visible: page.flow.installChoice === "install-internal"
            label: qsTr("Android")
            value: qsTr("%1 GiB kept").arg(page.flow.androidUserdataKeepGib)
        }

        ReviewRow {
            label: qsTr("Mode")
            value: page.flow.modeChoiceLabel(page.flow.finalMode())
        }

        ReviewRow {
            label: qsTr("Android apps")
            value: page.flow.waydroidChoiceLabel()
        }

        ReviewRow {
            label: qsTr("User")
            value: page.flow.username
        }

        ReviewRow {
            label: qsTr("Theme")
            value: page.flow.themeChoiceLabel(page.flow.themeChoice)
        }
    }

    DangerNotice {
        visible: page.flow.installChoice === "install-internal"
        message: page.flow.internalEraseWarning()
        checkboxText: qsTr("I understand this can erase internal storage and Android data.")
        checked: page.flow.internalDataLossAccepted
        Layout.maximumWidth: page.pageMaxWidth
        Layout.fillWidth: true
        onAcceptedChanged: accepted => page.flow.internalDataLossAccepted = accepted
    }

    BusyIndicator {
        running: page.flow.applying
        visible: running
    }
}
