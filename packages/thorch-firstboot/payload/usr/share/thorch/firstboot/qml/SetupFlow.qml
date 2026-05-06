import QtQuick

QtObject {
    id: flow

    required property var backend

    readonly property int applyPage: 6
    readonly property int donePage: 7

    property int page: 0
    property var wifiNetworks: []
    property int wifiSelectedIndex: -1
    property string wifiPassword: ""
    property string wifiMessage: ""
    property string wifiConnectedSsid: ""
    property bool wifiScanning: false
    property bool wifiConnecting: false
    property string installChoice: "expand-sd"
    property string modeChoice: "desktop"
    property string steamCompanion: "mobile"
    property bool installWaydroid: false
    property bool waydroidChoiceTouched: false
    property bool waydroidSetupDone: false
    property string themeChoice: "thorch-oled"
    property string username: "thorch"
    property string password: ""
    property string confirmPassword: ""
    property bool applying: false
    property bool applied: false
    property string resultMessage: ""
    property string nextAction: ""
    property string activePostAction: ""
    property bool postActionRunning: false
    property string postActionOutput: ""
    property bool postActionFailed: false
    property int postActionProgressValue: 0
    property string postActionProgressMessage: ""
    property bool autoInternalInstallStarted: false
    property string pendingAutoPostAction: ""
    property bool internalDataLossAccepted: false
    property int androidUserdataKeepGib: 32
    property var savedState: backend.initialState || ({})
    property string bootRole: backend.initialBootRole || "unknown"
    property bool secondStage: false
    property bool removeSdStage: false

    function resetLocalState() {
        page = 0;
        wifiSelectedIndex = -1;
        wifiPassword = "";
        wifiMessage = "";
        wifiConnectedSsid = "";
        installChoice = "expand-sd";
        modeChoice = "desktop";
        steamCompanion = "mobile";
        installWaydroid = hasNetwork();
        waydroidChoiceTouched = false;
        waydroidSetupDone = false;
        themeChoice = "thorch-oled";
        username = "thorch";
        password = "";
        confirmPassword = "";
        applying = false;
        applied = false;
        resultMessage = "";
        nextAction = "";
        activePostAction = "";
        postActionRunning = false;
        postActionOutput = "";
        postActionFailed = false;
        postActionProgressValue = 0;
        postActionProgressMessage = "";
        autoInternalInstallStarted = false;
        pendingAutoPostAction = "";
        internalDataLossAccepted = false;
        androidUserdataKeepGib = 32;
        savedState = {};
        secondStage = false;
        removeSdStage = false;
    }

    function selectedWifiSsid() {
        if (wifiSelectedIndex < 0 || wifiSelectedIndex >= wifiNetworks.length) {
            return "";
        }
        return wifiNetworks[wifiSelectedIndex].ssid || "";
    }

    function wifiLabel(network) {
        const lock = network.security && network.security.length > 0 ? qsTr(" secured") : qsTr(" open");
        const active = network.active ? qsTr("Connected: ") : "";
        return active + network.ssid + "  " + network.signal + "%" + lock;
    }

    function wifiReviewLabel() {
        return wifiConnectedSsid.length > 0 ? wifiConnectedSsid : qsTr("Not connected");
    }

    function finalMode() {
        if (modeChoice !== "steamos") {
            return modeChoice;
        }
        return steamCompanion === "desktop" ? "steamos-desktop" : "steamos-mobile";
    }

    function activeMode() {
        return savedState && savedState.mode ? savedState.mode : finalMode();
    }

    function wantsSteamSetup() {
        return activeMode().indexOf("steamos") === 0;
    }

    function hasNetwork() {
        return wifiConnectedSsid.length > 0;
    }

    function wantsWaydroidSetup() {
        return installWaydroid && !waydroidSetupDone;
    }

    function updateWaydroidDefault() {
        if (!waydroidChoiceTouched) {
            installWaydroid = hasNetwork();
        }
    }

    function waydroidChoiceLabel() {
        if (waydroidSetupDone) {
            return qsTr("Installed");
        }
        return installWaydroid ? qsTr("Install during setup") : qsTr("Install later");
    }

    function storageChoiceLabel(choice) {
        if (choice === "install-internal") {
            return qsTr("Install to internal storage");
        }
        if (choice === "expand-sd") {
            return qsTr("Use the full SD card");
        }
        return qsTr("Use the full SD card");
    }

    function modeChoiceLabel(mode) {
        if (mode === "mobile") {
            return qsTr("Mobile");
        }
        if (mode === "steamos-desktop") {
            return qsTr("Steam on top, KDE Desktop below");
        }
        if (mode === "steamos-mobile" || mode === "steamos") {
            return qsTr("Steam on top, Plasma Mobile below");
        }
        return qsTr("Desktop");
    }

    function themeChoiceLabel(theme) {
        if (theme === "breeze-dark") {
            return qsTr("Breeze Dark");
        }
        if (theme === "breeze-light") {
            return qsTr("Breeze Light");
        }
        if (theme === "high-contrast") {
            return qsTr("High Contrast");
        }
        return qsTr("Thorch OLED");
    }

    function internalEraseWarning() {
        return qsTr("Installing to internal storage can erase data on this device. If Thorch creates space from Android, Android's userdata partition (apps, files, and settings) will be wiped and recreated at the selected size. Back up anything important before continuing.");
    }

    function installWarningAccepted() {
        return internalDataLossAccepted
            || (savedState && savedState.internalDataLossAccepted === true);
    }

    function canAutoStartPostAction(action) {
        if (!action || action.length === 0) {
            return false;
        }
        if (action === "install-internal") {
            return !secondStage && !removeSdStage && installWarningAccepted();
        }
        if (action === "expand-sd") {
            return !secondStage && !removeSdStage;
        }
        if (action === "waydroid-setup") {
            return !removeSdStage && wantsWaydroidSetup();
        }
        return false;
    }

    function shouldAutoStartPostAction(action) {
        return action && action.length > 0
            && canAutoStartPostAction(action)
            && !postActionRunning
            && !postActionFailed
            && activePostAction.length === 0;
    }

    function scheduleAutomaticPostAction(action) {
        if (shouldAutoStartPostAction(action)) {
            pendingAutoPostAction = action;
            autoPostActionTimer.restart();
        }
    }

    function runPostAction(action) {
        if (!action || action.length === 0 || postActionRunning) {
            return;
        }
        pendingAutoPostAction = "";
        if (action === "install-internal") {
            autoInternalInstallStarted = true;
        }
        activePostAction = action;
        backend.launchPostAction(action);
    }

    function skipFirstboot() {
        if (applying || postActionRunning) {
            return;
        }
        pendingAutoPostAction = "";
        activePostAction = "skip-firstboot";
        backend.skipFirstboot();
    }

    function resetFirstboot() {
        if (applying || postActionRunning) {
            return;
        }
        pendingAutoPostAction = "";
        backend.resetFirstboot();
    }

    function scheduleInternalInstall() {
        if (!autoInternalInstallStarted && nextAction === "install-internal") {
            scheduleAutomaticPostAction("install-internal");
        }
    }

    function restoreStateChoices(state) {
        if (!state) {
            return;
        }
        if (state.username) {
            username = state.username;
        }
        if (state.theme) {
            themeChoice = state.theme;
        }
        if (state.installChoice) {
            installChoice = state.installChoice === "live-sd" ? "expand-sd" : state.installChoice;
        }
        if (state.internalDataLossAccepted === true) {
            internalDataLossAccepted = true;
        }
        if (state.androidUserdataKeepGib !== undefined) {
            const keepGib = Number(state.androidUserdataKeepGib);
            if (keepGib >= 1 && keepGib <= 512) {
                androidUserdataKeepGib = Math.round(keepGib);
            }
        }
        if (state.installWaydroid === true || state.installWaydroid === false) {
            installWaydroid = state.installWaydroid;
            waydroidChoiceTouched = true;
        }
        if (state.waydroidSetupDone === true) {
            waydroidSetupDone = true;
        }
        if (state.mode === "desktop" || state.mode === "mobile") {
            modeChoice = state.mode;
        } else if (state.mode === "steamos-desktop" || state.mode === "steamos-mobile") {
            modeChoice = "steamos";
            steamCompanion = state.mode === "steamos-desktop" ? "desktop" : "mobile";
        }
    }

    function restoreInternalStage() {
        const state = savedState || {};
        restoreStateChoices(state);

        if ((state.phase === "internal-install-ready" || state.phase === "internal-install-complete-remove-sd") && bootRole === "internal") {
            applied = true;
            secondStage = true;
            nextAction = wantsWaydroidSetup() ? "waydroid-setup" : "";
            resultMessage = wantsSteamSetup()
                ? qsTr("You're now running from internal storage. Finish the remaining setup actions next.")
                : qsTr("You're now running from internal storage. Finish setup to keep these choices.");
            page = donePage;
            scheduleAutomaticPostAction(nextAction);
        } else if (state.phase === "internal-install-ready") {
            applied = true;
            nextAction = "install-internal";
            resultMessage = installWarningAccepted()
                ? qsTr("Your choices are saved. Installing Thorch to internal storage now. Keep the SD card inserted until this finishes.")
                : qsTr("Your choices are saved. Review the erase warning to continue.");
            page = donePage;
            scheduleInternalInstall();
        } else if (state.phase === "internal-install-complete-remove-sd") {
            applied = true;
            removeSdStage = true;
            resultMessage = qsTr("Thorch has been copied to internal storage. Remove the SD card, then reboot.");
            page = donePage;
        } else if (state.phase === "expand-sd-ready") {
            applied = true;
            nextAction = "expand-sd";
            resultMessage = installChoice === "install-internal"
                ? qsTr("Using the rest of the SD card now, then installing Thorch to internal storage.")
                : (wantsWaydroidSetup()
                    ? qsTr("Using the rest of the SD card now, then Android app support will install.")
                    : qsTr("Using the rest of the SD card now."));
            page = donePage;
            scheduleAutomaticPostAction(nextAction);
        } else if (state.phase === "waydroid-setup-ready" || state.phase === "waydroid-setup-complete") {
            applied = true;
            nextAction = state.phase === "waydroid-setup-complete" ? "" : "waydroid-setup";
            resultMessage = state.phase === "waydroid-setup-complete"
                ? qsTr("Android app support is installed. Finish setup when you're ready.")
                : qsTr("Installing Android app support now.");
            page = donePage;
            scheduleAutomaticPostAction(nextAction);
        }
    }

    function validUsername() {
        return /^[a-z_][a-z0-9_-]{0,31}$/.test(username);
    }

    function canContinue() {
        if (page === 4) {
            if (!validUsername() || password.length === 0 || password !== confirmPassword) {
                return false;
            }
        }
        if (page === applyPage && installChoice === "install-internal" && !internalDataLossAccepted) {
            return false;
        }
        return !applying;
    }

    function applyConfig() {
        applying = true;
        resultMessage = "";
        backend.apply({
            "installChoice": installChoice,
            "mode": finalMode(),
            "theme": themeChoice,
            "username": username,
            "password": password,
            "internalDataLossAccepted": internalDataLossAccepted,
            "androidUserdataKeepGib": androidUserdataKeepGib,
            "installWaydroid": installWaydroid
        });
    }

    Component.onCompleted: {
        restoreInternalStage();
        wifiScanning = true;
        wifiMessage = qsTr("Looking for Wi-Fi networks...");
        backend.scanWifi();
    }

    property Timer autoPostActionTimer: Timer {
        interval: 700
        repeat: false
        onTriggered: {
            const action = flow.pendingAutoPostAction;
            flow.pendingAutoPostAction = "";
            if (flow.shouldAutoStartPostAction(action)) {
                flow.runPostAction(action);
            }
        }
    }

    property Connections backendConnections: Connections {
        target: flow.backend

        function onApplyFinished(ok, message, action) {
            flow.applying = false;
            flow.applied = ok;
            flow.resultMessage = message;
            flow.nextAction = action;
            if (ok) {
                flow.page = flow.donePage;
                if (action === "install-internal") {
                    flow.resultMessage = qsTr("Your choices are saved. Installing Thorch to internal storage now. Keep the SD card inserted until this finishes.");
                    flow.scheduleInternalInstall();
                } else {
                    flow.scheduleAutomaticPostAction(action);
                }
            }
        }

        function onWifiScanFinished(ok, message, networks) {
            flow.wifiScanning = false;
            flow.wifiMessage = message;
            flow.wifiNetworks = networks || [];
            if (flow.wifiNetworks.length > 0 && (flow.wifiSelectedIndex < 0 || flow.wifiSelectedIndex >= flow.wifiNetworks.length)) {
                flow.wifiSelectedIndex = 0;
            }
            for (let i = 0; i < flow.wifiNetworks.length; i++) {
                if (flow.wifiNetworks[i].active) {
                    flow.wifiConnectedSsid = flow.wifiNetworks[i].ssid || "";
                    break;
                }
            }
            flow.updateWaydroidDefault();
        }

        function onWifiConnectFinished(ok, message) {
            flow.wifiConnecting = false;
            flow.wifiMessage = message;
            if (ok) {
                flow.wifiConnectedSsid = flow.selectedWifiSsid();
                flow.updateWaydroidDefault();
                flow.backend.scanWifi();
            }
        }

        function onPostActionStarted(ok, message) {
            flow.resultMessage = message;
            if (ok) {
                flow.postActionRunning = true;
                flow.postActionOutput = "";
                flow.postActionFailed = false;
                flow.postActionProgressValue = flow.activePostAction === "install-internal" ? 2 : 0;
                flow.postActionProgressMessage = message;
            }
        }

        function onPostActionProgress(progress, message, output) {
            flow.postActionProgressValue = progress;
            flow.postActionProgressMessage = message;
            if (message.length > 0) {
                flow.resultMessage = message;
            }
            flow.postActionOutput = output;
        }

        function onPostActionFinished(ok, message, output) {
            const finishedAction = flow.activePostAction;
            let followupAction = "";
            flow.postActionRunning = false;
            flow.resultMessage = message;
            flow.postActionOutput = output;
            flow.postActionFailed = !ok;
            flow.postActionProgressValue = ok ? 100 : flow.postActionProgressValue;
            flow.postActionProgressMessage = message;
            if (ok && finishedAction === "install-internal") {
                flow.removeSdStage = true;
                flow.nextAction = "";
            }
            if (ok && finishedAction === "expand-sd" && flow.installChoice === "install-internal") {
                flow.nextAction = "install-internal";
                flow.resultMessage = qsTr("The SD card is ready. Installing Thorch to internal storage next.");
                followupAction = "install-internal";
            } else if (ok && finishedAction === "expand-sd" && flow.wantsWaydroidSetup()) {
                flow.nextAction = "waydroid-setup";
                flow.resultMessage = qsTr("The SD card is ready. Installing Android app support next.");
                followupAction = "waydroid-setup";
            } else if (ok && finishedAction === "expand-sd") {
                flow.nextAction = "";
            }
            if (ok && finishedAction === "waydroid-setup") {
                flow.waydroidSetupDone = true;
                if (flow.nextAction === "waydroid-setup") {
                    flow.nextAction = "";
                }
            }
            if (ok && (finishedAction === "finish-firstboot" || finishedAction === "finish-and-launch-steam")) {
                flow.secondStage = false;
                flow.removeSdStage = false;
            }
            if (ok && finishedAction === "skip-firstboot") {
                flow.applied = true;
                flow.nextAction = "";
                flow.secondStage = false;
                flow.removeSdStage = false;
            }
            flow.activePostAction = "";
            if (ok && followupAction.length > 0) {
                flow.scheduleAutomaticPostAction(followupAction);
            }
            if (ok && finishedAction === "waydroid-setup" && !flow.secondStage) {
                flow.runPostAction("finish-firstboot");
            }
        }

        function onRebootStarted(ok, message) {
            flow.resultMessage = message;
        }

        function onResetFinished(ok, message) {
            if (ok) {
                flow.resetLocalState();
            }
            flow.resultMessage = message;
        }
    }
}
