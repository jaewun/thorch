import QtQuick

Item {
    id: backend

    property bool done: false
    property var initialState: ({})
    property string initialBootRole: "sd"
    property int progressIndex: 0
    property var progressEvents: [
        {"progress": 2, "message": "Mock: starting the internal storage install.", "output": "Mock target: /dev/mockboot and /dev/mockroot"},
        {"progress": 3, "message": "Mock: creating an internal Thorch target.", "output": "Mock Android userdata kept at 32 GiB"},
        {"progress": 4, "message": "Mock: resizing Android userdata.", "output": "Mock userdata -> 32 GiB"},
        {"progress": 5, "message": "Mock: creating the internal boot partition.", "output": "Mock ROCKNIX boot partition"},
        {"progress": 6, "message": "Mock: creating the internal root partition.", "output": "Mock Thorch root partition"},
        {"progress": 8, "message": "Mock: preparing internal storage.", "output": "mkfs.vfat /dev/mockboot\nmkfs.ext4 /dev/mockroot"},
        {"progress": 18, "message": "Mock: copying Thorch to internal storage.", "output": "rsync / /mnt/thorch-internal"},
        {"progress": 38, "message": "Mock: copying Thorch to internal storage. 37%.", "output": "Copied 4.0 GiB of mock root."},
        {"progress": 62, "message": "Mock: copying Thorch to internal storage. 81%.", "output": "Copied 8.9 GiB of mock root."},
        {"progress": 72, "message": "Mock: copying boot files.", "output": "Copying ROCKNIX boot assets."},
        {"progress": 80, "message": "Mock: preparing the internal startup files.", "output": "mkinitcpio -P"},
        {"progress": 90, "message": "Mock: preparing the boot image.", "output": "thorch-rebuild-abl-kernel"},
        {"progress": 98, "message": "Mock: finishing writes to disk.", "output": "sync"}
    ]

    signal applyFinished(bool ok, string message, string action)
    signal wifiScanFinished(bool ok, string message, var networks)
    signal wifiConnectFinished(bool ok, string message)
    signal rebootStarted(bool ok, string message)
    signal postActionStarted(bool ok, string message)
    signal postActionProgress(int progress, string message, string output)
    signal postActionFinished(bool ok, string message, string output)
    signal resetFinished(bool ok, string message)

    function apply(config) {
        if (config.installChoice === "install-internal" && !config.internalDataLossAccepted) {
            applyFinished(false, "Mock: acknowledge the destructive install warning first.", "");
            return;
        }
        if (config.installChoice === "install-internal") {
            initialState = {
                "username": config.username,
                "mode": config.mode,
                "theme": config.theme,
                "installChoice": "install-internal",
                "phase": "internal-install-ready",
                "internalDataLossAccepted": true,
                "androidUserdataKeepGib": config.androidUserdataKeepGib || 32,
                "installWaydroid": config.installWaydroid
            };
            applyFinished(true, "Mock: choices saved. Installing to internal storage next.", "install-internal");
            return;
        }
        if (config.installChoice === "expand-sd") {
            initialState = {
                "mode": config.mode,
                "theme": config.theme,
                "installChoice": "expand-sd",
                "phase": "expand-sd-ready",
                "installWaydroid": config.installWaydroid
            };
            applyFinished(true, "Mock: setup saved. The SD card will expand next.", "expand-sd");
            return;
        }
        if (config.installWaydroid) {
            initialState = {
                "mode": config.mode,
                "theme": config.theme,
                "installChoice": config.installChoice,
                "phase": "waydroid-setup-ready",
                "installWaydroid": true
            };
            applyFinished(true, "Mock: setup saved. Android app support will install next.", "waydroid-setup");
            return;
        }
        done = true;
        applyFinished(true, "Mock: setup is complete.", "");
    }

    function scanWifi() {
        wifiScanTimer.restart();
    }

    function connectWifi(ssid, password) {
        wifiConnectFinished(true, "Mock: connected to " + ssid + ".");
    }

    function skipFirstboot() {
        done = true;
        postActionStarted(true, "Mock: skipping first boot setup.");
        postActionFinished(true, "Mock: first boot setup was skipped.", "");
    }

    function resetFirstboot() {
        initialState = {};
        done = false;
        resetFinished(true, "Mock: first boot setup has been reset.");
    }

    function launchPostAction(action) {
        if (action === "install-internal") {
            progressIndex = 0;
            postActionStarted(true, "Mock: installing to internal storage.");
            installTimer.restart();
            return;
        }
        if (action === "steam-setup") {
            postActionStarted(true, "Mock: installing Steam support.");
            postActionFinished(true, "Mock: Steam support is installed.", "Mock: FEX ready\nMock: Steam launcher ready");
            return;
        }
        if (action === "waydroid-setup") {
            initialState.waydroidSetupDone = true;
            postActionStarted(true, "Mock: installing Android app support.");
            postActionFinished(true, "Mock: Android app support is installed.", "Mock: Waydroid package installed\nMock: Android images initialized");
            return;
        }
        if (action === "finish-and-launch-steam") {
            done = true;
            postActionStarted(true, "Mock: finishing setup and launching Steam.");
            postActionFinished(true, "Mock: Steam is launching.", "Mock: FEX ready\nMock: Steam launcher ready\nMock: SteamOS mode started");
            return;
        }
        if (action === "finish-firstboot") {
            done = true;
            postActionStarted(true, "Mock: finishing setup.");
            postActionFinished(true, "Mock: setup is complete.", "");
            return;
        }
        if (action === "expand-sd") {
            postActionStarted(true, "Mock: using the rest of the SD card.");
            if (initialState.installWaydroid && !initialState.waydroidSetupDone) {
                initialState.phase = "waydroid-setup-ready";
            } else {
                initialState.phase = "complete";
                done = true;
            }
            postActionFinished(true, "Mock: the SD card is ready to use its full space.", "Mock: growpart + resize2fs complete.");
            return;
        }
        postActionStarted(false, "Mock: no action for " + action + ".");
    }

    function reboot() {
        rebootStarted(true, "Mock reboot requested.");
    }

    Timer {
        id: installTimer
        interval: 350
        repeat: true
        onTriggered: {
            if (backend.progressIndex >= backend.progressEvents.length) {
                stop();
                backend.initialState = {};
                backend.postActionFinished(true, "Mock: Thorch has been copied to internal storage. Remove the SD card, then reboot.", "Mock install finished cleanly.");
                return;
            }
            const event = backend.progressEvents[backend.progressIndex];
            backend.progressIndex += 1;
            backend.postActionProgress(event.progress, event.message, event.output);
        }
    }

    Timer {
        id: wifiScanTimer
        interval: 300
        repeat: false
        onTriggered: {
            backend.wifiScanFinished(true, "Mock: found 3 Wi-Fi networks.", [
                {"ssid": "Thorch Lab", "security": "WPA2", "signal": 92, "active": true},
                {"ssid": "Coffee Shop", "security": "WPA2", "signal": 67, "active": false},
                {"ssid": "Open Test Network", "security": "", "signal": 41, "active": false}
            ])
        }
    }
}
