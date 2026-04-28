import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: "#0A0A0A"
    anchors.fill: parent

    // ── Palette ───────────────────────────────────────────────────────────────
    readonly property color bgColor:       "#0A0A0A"
    readonly property color panelColor:    "#111111"
    readonly property color borderColor:   "#1E1E1E"
    readonly property color textPrimary:   "#E5E7EB"
    readonly property color textSecondary: "#9CA3AF"
    readonly property color textDisabled:  "#4B5563"
    readonly property color successGreen:  "#22C55E"
    readonly property color warnAmber:     "#F59E0B"
    readonly property color errorRed:      "#EF4444"
    readonly property color accentBlue:    "#38BDF8"

    // ── State ─────────────────────────────────────────────────────────────────
    property int    activeTab:       0   // 0=Accounts  1=Send
    property bool   settingsOpen:    false
    property bool   cliFound:        false
    property string cliPath:         ""
    property var    accounts:        []
    property bool   pollBusy:        false
    property string statusMsg:       ""
    property bool   statusIsError:   false

    // Send tab state
    property string sendFrom:        ""
    property string sendStatus:      ""
    property bool   sendBusy:        false

    // Keycard auth state
    property string kcAuthId:        ""
    property bool   kcPending:       false
    property string pendingFrom:     ""
    property string pendingTo:       ""
    property string pendingAmount:   ""

    // Activity log (last 20 ops)
    property var    activityLog:     []

    // ── Helpers ───────────────────────────────────────────────────────────────
    function callModuleParse(raw) {
        try {
            var t = JSON.parse(raw)
            if (typeof t === 'string') { try { return JSON.parse(t) } catch(e) { return t } }
            return t
        } catch(e) { return null }
    }

    function logActivity(msg, isError) {
        var ts = new Date().toLocaleTimeString(Qt.locale(), "HH:mm:ss")
        var entry = { ts: ts, msg: msg, error: isError === true }
        var arr = root.activityLog.slice()
        if (arr.length >= 20) arr.shift()
        arr.push(entry)
        root.activityLog = arr
        activityModel.clear()
        for (var i = 0; i < arr.length; i++)
            activityModel.append(arr[i])
        activityView.positionViewAtEnd()
    }

    function refreshAccounts() {
        if (typeof logos === "undefined" || !logos.callModule) return
        var r = callModuleParse(logos.callModule("logos_wallet", "listAccounts", []))
        accountModel.clear()
        if (!r) return
        if (r.error) { logActivity("listAccounts: " + r.error, true); return }

        // Accept array at top level or wrapped in {accounts:[...]} or {output:"..."}
        var arr = []
        if (Array.isArray(r)) {
            arr = r
        } else if (r.accounts && Array.isArray(r.accounts)) {
            arr = r.accounts
        } else if (r.output) {
            // CLI returned plain text — show raw
            accountModel.append({ id: r.output, type: "", balance: "" })
            return
        }
        root.accounts = arr
        for (var i = 0; i < arr.length; i++) {
            var a = arr[i]
            accountModel.append({
                id:      a.id      || a.accountId || JSON.stringify(a),
                type:    a.type    || "public",
                balance: a.balance !== undefined ? String(a.balance) : "—"
            })
        }
    }

    function refreshStatus() {
        if (typeof logos === "undefined" || !logos.callModule) return
        var s = callModuleParse(logos.callModule("logos_wallet", "getStatus", []))
        if (s) {
            root.cliFound = s.cliFound === true
            root.cliPath  = s.cliPath || ""
        }
    }

    // ── Keycard auth flow ─────────────────────────────────────────────────────
    function authorizeAndSend(from, to, amount) {
        if (typeof logos === "undefined" || !logos.callModule) {
            root.sendStatus = "Module not available"
            return
        }
        root.pendingFrom   = from
        root.pendingTo     = to
        root.pendingAmount = amount
        root.sendBusy      = true
        root.sendStatus    = "Requesting Keycard approval…"
        logActivity("Requesting keycard auth for transfer", false)

        var authResp = callModuleParse(
            logos.callModule("keycard", "requestAuth", ["wallet_transfer", "logos_wallet"])
        )
        if (!authResp || !authResp.authId) {
            root.sendBusy   = false
            root.sendStatus = "Keycard unavailable — " + (authResp && authResp.error ? authResp.error : "no authId")
            logActivity(root.sendStatus, true)
            return
        }
        root.kcAuthId  = authResp.authId
        root.kcPending = true
        kcPollTimer.start()
    }

    Timer {
        id: kcPollTimer
        interval: 1000; repeat: true
        onTriggered: {
            if (!root.kcPending) { stop(); return }
            var r = root.callModuleParse(
                logos.callModule("keycard", "checkAuthStatus", [root.kcAuthId])
            )
            if (!r) return
            if (r.error) {
                stop()
                root.kcPending  = false
                root.sendBusy   = false
                root.sendStatus = "Keycard auth expired: " + r.error
                root.logActivity(root.sendStatus, true)
                return
            }
            if (r.status === "complete") {
                stop()
                root.kcPending = false
                root.sendStatus = "Keycard approved — sending…"
                root.logActivity("Keycard approved, executing transfer", false)
                executeSend()
            } else if (r.status === "rejected") {
                stop()
                root.kcPending  = false
                root.sendBusy   = false
                root.sendStatus = "Transfer declined by keycard"
                root.logActivity(root.sendStatus, true)
            }
            // "pending" → keep polling
        }
    }

    function executeSend() {
        var result = callModuleParse(
            logos.callModule("logos_wallet", "sendTransfer",
                [root.pendingFrom, root.pendingTo, root.pendingAmount])
        )
        root.sendBusy = false
        if (!result || result.error) {
            root.sendStatus = "Transfer failed: " + (result && result.error ? result.error : "unknown")
            logActivity(root.sendStatus, true)
        } else {
            root.sendStatus = "Transfer submitted"
            logActivity("Transfer: " + root.pendingFrom + " → " + root.pendingTo
                        + " (" + root.pendingAmount + " tok)", false)
            balanceRefreshTimer.restart()
        }
        root.pendingFrom = ""; root.pendingTo = ""; root.pendingAmount = ""
    }

    // ── Poll / timers ─────────────────────────────────────────────────────────
    Timer {
        interval: 10000; running: true; repeat: true
        onTriggered: {
            if (root.pollBusy) return
            root.pollBusy = true
            root.refreshStatus()
            root.refreshAccounts()
            root.pollBusy = false
        }
    }

    Timer {
        id: balanceRefreshTimer
        interval: 3000; onTriggered: root.refreshAccounts()
    }

    Component.onCompleted: {
        if (typeof logos === "undefined" || !logos.callModule) return
        var cfg = callModuleParse(logos.callModule("logos_wallet", "getConfig", []))
        if (cfg && cfg.cliPathEff) cliPathField.text = cfg.cliPathEff
        root.refreshStatus()
        root.refreshAccounts()
    }

    TextEdit { id: clipHelper; visible: false }

    // ── Root layout ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Toolbar ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12; Layout.leftMargin: 12; Layout.rightMargin: 12
            spacing: 8

            Rectangle { width: 8; height: 8; radius: 4
                color: root.cliFound ? root.successGreen : root.errorRed }
            Text { text: root.cliFound ? "CLI ready" : "CLI not found"
                   color: root.textSecondary; font.pixelSize: 12 }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 24; height: 24; radius: 4; color: "transparent"
                border.color: root.settingsOpen ? root.accentBlue : root.borderColor
                Text { anchors.centerIn: parent; text: "⚙"
                       color: root.settingsOpen ? root.accentBlue : root.textSecondary
                       font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: root.settingsOpen = !root.settingsOpen }
            }
        }

        // ── Settings panel ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 12; Layout.rightMargin: 12
            visible: root.settingsOpen
            height: visible ? settingsInner.implicitHeight + 20 : 0
            color: root.panelColor; border.color: root.borderColor; radius: 4

            ColumnLayout {
                id: settingsInner
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 8

                Text { text: "Wallet CLI path"; color: root.textSecondary; font.pixelSize: 10 }
                Rectangle { Layout.fillWidth: true; height: 26; color: "#0A0A0A"
                    border.color: root.borderColor; radius: 3
                    TextInput { id: cliPathField
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.textPrimary; font.pixelSize: 11; font.family: "monospace"; clip: true
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                               text: parent.text.length === 0 ? "~/.local/bin/wallet" : ""
                               color: root.textDisabled; font.pixelSize: 11; font.family: "monospace" }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Rectangle { width: 56; height: 24; radius: 4; color: "transparent"
                        border.color: root.successGreen
                        Text { anchors.centerIn: parent; text: "Save"
                               color: root.successGreen; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                logos.callModule("logos_wallet", "setCliPath", [cliPathField.text])
                                root.settingsOpen = false
                                root.refreshStatus()
                            }
                        }
                    }
                }
            }
        }

        // ── Tab bar ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10; Layout.leftMargin: 12; Layout.rightMargin: 12
            spacing: 0

            Repeater {
                model: ["Accounts", "Send"]
                delegate: Item {
                    required property string modelData
                    required property int    index
                    Layout.fillWidth: true; height: 28

                    Text { anchors.centerIn: parent; text: modelData
                           color: root.activeTab === index ? root.textPrimary : root.textDisabled
                           font.pixelSize: 12; font.bold: root.activeTab === index }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 2; radius: 1
                        color: root.activeTab === index ? root.accentBlue : root.borderColor
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.activeTab = index }
                }
            }
        }

        // ── Tab content ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8

            // ── ACCOUNTS TAB ──────────────────────────────────────────────────
            ColumnLayout {
                visible: root.activeTab === 0
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 8

                // Account list
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.panelColor; border.color: root.borderColor; radius: 4

                    Text { anchors.centerIn: parent
                           visible: accountModel.count === 0
                           text: "No accounts yet — click New Account"
                           color: root.textDisabled; font.pixelSize: 11 }

                    ListView {
                        id: accountListView
                        anchors { fill: parent; margins: 6 }
                        model: ListModel { id: accountModel }
                        clip: true; spacing: 4

                        delegate: Rectangle {
                            required property string id
                            required property string type
                            required property string balance
                            width: accountListView.width; height: 40
                            color: "#0D0D0D"; radius: 3

                            RowLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                spacing: 8

                                Rectangle { width: 6; height: 6; radius: 3
                                    color: root.accentBlue }
                                Text { text: id.length > 32 ? id.substring(0, 28) + "…" : id
                                       color: root.textPrimary; font.pixelSize: 11
                                       font.family: "monospace"; Layout.fillWidth: true
                                       elide: Text.ElideRight }
                                Text { text: balance !== "" ? balance + " tok" : "—"
                                       color: balance !== "" && balance !== "0" ? root.successGreen : root.textDisabled
                                       font.pixelSize: 11; font.bold: true }
                            }
                        }
                    }
                }

                // Account action buttons
                RowLayout {
                    Layout.fillWidth: true; spacing: 6

                    Rectangle { height: 28; Layout.fillWidth: true; radius: 4; color: "transparent"
                        border.color: root.accentBlue
                        Text { anchors.centerIn: parent; text: "+ New Account"
                               color: root.accentBlue; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.logActivity("Creating new public account…", false)
                                var r = root.callModuleParse(
                                    logos.callModule("logos_wallet", "createAccount", []))
                                if (r && r.error) {
                                    root.logActivity("createAccount: " + r.error, true)
                                } else {
                                    root.logActivity("Account created", false)
                                    balanceRefreshTimer.restart()
                                }
                            }
                        }
                    }

                    Rectangle { height: 28; Layout.fillWidth: true; radius: 4; color: "transparent"
                        border.color: root.warnAmber
                        Text { anchors.centerIn: parent; text: "Claim Faucet"
                               color: root.warnAmber; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (accountModel.count === 0) {
                                    root.logActivity("No accounts — create one first", true)
                                    return
                                }
                                // Use first account
                                var acctId = accountModel.get(0).id
                                root.logActivity("Claiming faucet → " + acctId.substring(0, 20) + "…", false)
                                var r = root.callModuleParse(
                                    logos.callModule("logos_wallet", "claimFaucet", [acctId]))
                                if (r && r.error) {
                                    root.logActivity("claimFaucet: " + r.error, true)
                                } else {
                                    root.logActivity("Faucet claim submitted (150 tok)", false)
                                    balanceRefreshTimer.restart()
                                }
                            }
                        }
                    }

                    Rectangle { height: 28; width: 36; radius: 4; color: "transparent"
                        border.color: root.borderColor
                        Text { anchors.centerIn: parent; text: "↺"
                               color: root.textSecondary; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshAccounts() }
                    }
                }
            }

            // ── SEND TAB ──────────────────────────────────────────────────────
            ColumnLayout {
                visible: root.activeTab === 1
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 8

                // Keycard warning if no card present
                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: 4
                    color: Qt.rgba(245/255, 158/255, 11/255, 0.08)
                    border.color: root.warnAmber
                    visible: true

                    Text { anchors.centerIn: parent
                           text: "⚠  Keycard approval required before each transfer"
                           color: root.warnAmber; font.pixelSize: 11 }
                }

                // From
                Text { text: "From"; color: root.textSecondary; font.pixelSize: 10 }
                Rectangle { Layout.fillWidth: true; height: 26; color: "#0A0A0A"
                    border.color: root.borderColor; radius: 3

                    ComboBox {
                        id: fromCombo
                        anchors.fill: parent
                        model: ListModel { id: fromModel }
                        textRole: "id"
                        background: Rectangle { color: "transparent" }
                        contentItem: Text {
                            leftPadding: 6
                            text: fromCombo.currentIndex >= 0 && fromModel.count > 0
                                  ? fromModel.get(fromCombo.currentIndex).id : "— select account —"
                            color: fromCombo.currentIndex >= 0 ? root.textPrimary : root.textDisabled
                            font.pixelSize: 11; font.family: "monospace"
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
                        }
                        indicator: Text { anchors.right: parent.right; anchors.rightMargin: 8
                                          anchors.verticalCenter: parent.verticalCenter
                                          text: "▼"; color: root.textDisabled; font.pixelSize: 9 }
                        popup: Popup {
                            y: fromCombo.height; width: fromCombo.width; padding: 0
                            background: Rectangle { color: root.panelColor; border.color: root.borderColor; radius: 3 }
                            contentItem: ListView {
                                model: fromCombo.model; clip: true
                                implicitHeight: Math.min(contentHeight, 120)
                                delegate: Item {
                                    required property string id
                                    required property int    index
                                    width: parent ? parent.width : 0; height: 26
                                    Text { anchors { fill: parent; leftMargin: 6 }
                                           text: id; color: root.textPrimary; font.pixelSize: 11
                                           font.family: "monospace"; verticalAlignment: Text.AlignVCenter
                                           elide: Text.ElideRight }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: { fromCombo.currentIndex = index; fromCombo.popup.close() } }
                                }
                            }
                        }
                    }
                }

                // To
                Text { text: "To"; color: root.textSecondary; font.pixelSize: 10 }
                Rectangle { Layout.fillWidth: true; height: 26; color: "#0A0A0A"
                    border.color: root.borderColor; radius: 3
                    TextInput { id: toField
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.textPrimary; font.pixelSize: 11; font.family: "monospace"; clip: true
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                               text: parent.text.length === 0 ? "recipient account id" : ""
                               color: root.textDisabled; font.pixelSize: 11; font.family: "monospace" }
                    }
                }

                // Amount
                Text { text: "Amount"; color: root.textSecondary; font.pixelSize: 10 }
                Rectangle { Layout.fillWidth: true; height: 26; color: "#0A0A0A"
                    border.color: root.borderColor; radius: 3
                    TextInput { id: amountField
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.textPrimary; font.pixelSize: 11; font.family: "monospace"; clip: true
                        inputMethodHints: Qt.ImhDigitsOnly
                        Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                               text: parent.text.length === 0 ? "e.g. 10" : ""
                               color: root.textDisabled; font.pixelSize: 11; font.family: "monospace" }
                    }
                }

                // Send button
                Rectangle {
                    Layout.fillWidth: true; height: 36; radius: 4
                    color: root.sendBusy ? "transparent" : Qt.rgba(56/255, 189/255, 248/255, 0.12)
                    border.color: root.sendBusy ? root.borderColor : root.accentBlue
                    opacity: root.sendBusy ? 0.6 : 1.0

                    Text { anchors.centerIn: parent
                           text: root.sendBusy ? "Waiting for Keycard…" : "Authorize & Send"
                           color: root.sendBusy ? root.textDisabled : root.accentBlue
                           font.pixelSize: 12; font.bold: !root.sendBusy }

                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        enabled: !root.sendBusy
                        onClicked: {
                            var fromId = (fromModel.count > 0 && fromCombo.currentIndex >= 0)
                                       ? fromModel.get(fromCombo.currentIndex).id : ""
                            var toId = toField.text.trim()
                            var amt  = amountField.text.trim()
                            if (!fromId) { root.sendStatus = "Select a From account"; return }
                            if (!toId)   { root.sendStatus = "Enter a To address"; return }
                            if (!amt)    { root.sendStatus = "Enter an amount"; return }
                            root.authorizeAndSend(fromId, toId, amt)
                        }
                    }
                }

                // Send status
                Text { visible: root.sendStatus.length > 0; text: root.sendStatus
                       color: root.sendBusy ? root.warnAmber : root.textSecondary
                       font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }

                Item { Layout.fillHeight: true }
            }
        }

        // ── Activity log — fixed height, always visible ───────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 110
            color: "#0D0D0D"

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: root.borderColor
            }

            ListView {
                id: activityView
                anchors { fill: parent; margins: 8 }
                model: ListModel { id: activityModel }
                clip: true; spacing: 1

                delegate: Text {
                    required property string ts
                    required property string msg
                    required property bool   error
                    width: activityView.width
                    text: "[" + ts + "] " + msg
                    color: error ? root.errorRed : root.textSecondary
                    font.pixelSize: 11; font.family: "Courier New, monospace"
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

    } // ColumnLayout

    // ── onCompleted: populate fromModel from accountModel after accounts load ─
    Connections {
        target: accountModel
        function onCountChanged() {
            fromModel.clear()
            for (var i = 0; i < accountModel.count; i++)
                fromModel.append({ id: accountModel.get(i).id })
        }
    }
}
