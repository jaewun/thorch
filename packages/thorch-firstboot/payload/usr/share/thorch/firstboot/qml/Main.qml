import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "pages"

ApplicationWindow {
    id: root

    readonly property int pageMaxWidth: 720
    readonly property int optionMaxWidth: 620
    readonly property int contentPadX: 42
    readonly property int contentPadTop: 34
    readonly property int contentPadBottom: 26
    property var backendBridge: backend

    function thorchTopScreen() {
        const screens = Qt.application.screens;
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === "DSI-2") {
                return screens[i];
            }
        }
        return screens.length > 0 ? screens[0] : null;
    }

    function pageContentWidth() {
        return Math.max(0, Math.min(stack.width - (contentPadX * 2), pageMaxWidth));
    }

    screen: thorchTopScreen()
    width: screen ? screen.width : 960
    height: screen ? screen.height : 540
    visible: true
    visibility: Window.FullScreen
    title: qsTr("Thorch Setup")
    color: "#05080a"

    SetupFlow {
        id: flow
        backend: root.backendBridge
    }

    header: ToolBar {
        height: 76
        background: Rectangle { color: "#071014" }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            spacing: 18

            Label {
                text: qsTr("Thorch")
                color: "#26e6ff"
                font.pixelSize: 30
                font.bold: true
            }

            Label {
                text: qsTr("Setup")
                color: "#f6fafc"
                font.pixelSize: 24
                Layout.fillWidth: true
            }

            Label {
                text: flow.applied ? qsTr("Ready") : qsTr("Step %1 of %2").arg(Math.min(flow.page + 1, flow.donePage)).arg(flow.donePage)
                color: "#89a0aa"
                font.pixelSize: 18
            }
        }
    }

    footer: ToolBar {
        height: 86
        background: Rectangle { color: "#071014" }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 28
            anchors.rightMargin: 28
            spacing: 16

            Button {
                text: qsTr("Back")
                icon.name: "go-previous"
                enabled: flow.page > 0 && flow.page < flow.donePage && !flow.applying
                onClicked: flow.page -= 1
            }

            Button {
                text: qsTr("Skip")
                icon.name: "dialog-cancel"
                enabled: !flow.applying && !flow.postActionRunning
                onClicked: flow.skipFirstboot()
            }

            Button {
                text: qsTr("Start Again")
                icon.name: "edit-undo"
                enabled: !flow.applying && !flow.postActionRunning
                onClicked: flow.resetFirstboot()
            }

            Label {
                text: flow.resultMessage
                color: flow.applied ? "#45de80" : "#ffb84d"
                font.pixelSize: 16
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Button {
                text: flow.page === flow.applyPage ? qsTr("Continue") : qsTr("Next")
                icon.name: flow.page === flow.applyPage ? "dialog-ok-apply" : "go-next"
                enabled: flow.page < flow.donePage && flow.canContinue()
                onClicked: {
                    if (flow.page === flow.applyPage) {
                        flow.applyConfig();
                    } else {
                        flow.page += 1;
                    }
                }
            }
        }
    }

    StackLayout {
        id: stack

        anchors.fill: parent
        currentIndex: flow.page

        WifiPage {
            flow: flow
            pageWidth: root.pageContentWidth()
            optionMaxWidth: root.optionMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }

        StoragePage {
            flow: flow
            pageWidth: root.pageContentWidth()
            optionMaxWidth: root.optionMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }

        ModePage {
            flow: flow
            pageWidth: root.pageContentWidth()
            optionMaxWidth: root.optionMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }

        AndroidPage {
            flow: flow
            pageWidth: root.pageContentWidth()
            optionMaxWidth: root.optionMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }

        AccountPage {
            flow: flow
            pageWidth: root.pageContentWidth()
            optionMaxWidth: root.optionMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }

        ThemePage {
            flow: flow
            pageWidth: root.pageContentWidth()
            optionMaxWidth: root.optionMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }

        ReviewPage {
            flow: flow
            pageWidth: root.pageContentWidth()
            optionMaxWidth: root.optionMaxWidth
            pageMaxWidth: root.pageMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }

        CompletionPage {
            flow: flow
            pageWidth: root.pageContentWidth()
            pageMaxWidth: root.pageMaxWidth
            padX: root.contentPadX
            padTop: root.contentPadTop
            padBottom: root.contentPadBottom
        }
    }
}
