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
    readonly property color errorRed:      "#EF4444"
    readonly property color accentOrange:  "#F97316"

    // ── State ─────────────────────────────────────────────────────────────────
    property bool   settingsOpen:        false
    property bool   cliFound:            false
    property string cliPath:             ""
    property var    accounts:            []
    property bool   pollBusy:            false

    property string selectedFromId:      ""
    property string selectedFromBalance: ""
    property string sendStatus:          ""
    property bool   sendBusy:            false
    property bool   sendOpen:            false
    property var    txHistory:           []

    property var    activityLog:         []

    // ── Helpers ───────────────────────────────────────────────────────────────
    function displayId(id) {
        if (id.indexOf("Public/") === 0)  return id.slice(7)
        if (id.indexOf("Private/") === 0) return id.slice(8)
        return id
    }

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

        var arr = []
        if (Array.isArray(r)) {
            arr = r
        } else if (r.accounts && Array.isArray(r.accounts)) {
            arr = r.accounts
        } else if (r.output) {
            accountModel.append({ id: r.output, type: "public", balance: "" })
            return
        }
        root.accounts = arr

        arr.sort(function(a, b) {
            var ta = (a.type || "public"), tb = (b.type || "public")
            if (ta === "public" && tb !== "public") return -1
            if (ta !== "public" && tb === "public") return 1
            return (parseFloat(b.balance) || 0) - (parseFloat(a.balance) || 0)
        })

        for (var i = 0; i < arr.length; i++) {
            var a = arr[i]
            accountModel.append({
                id:      a.id      || a.accountId || JSON.stringify(a),
                type:    a.type    || "public",
                balance: a.balance !== undefined ? String(a.balance) : "—"
            })
        }

        // Update balance of already-selected account (don't change selection)
        if (root.selectedFromId.length > 0) {
            for (var j = 0; j < accountModel.count; j++) {
                if (accountModel.get(j).id === root.selectedFromId) {
                    root.selectedFromBalance = accountModel.get(j).balance
                    break
                }
            }
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

    function refreshTxHistory() {
        if (typeof logos === "undefined" || !logos.callModule) return
        if (root.selectedFromId.length === 0) return
        var r = callModuleParse(logos.callModule("logos_wallet", "getTransactions", [root.selectedFromId]))
        root.txHistory = Array.isArray(r) ? r : []
        txHistoryModel.clear()
        for (var i = 0; i < root.txHistory.length; i++)
            txHistoryModel.append(root.txHistory[i])
    }

    function executeSend(from, to, amount) {
        if (typeof logos === "undefined" || !logos.callModule) {
            root.sendStatus = "Module not available"
            return
        }
        root.sendBusy = true
        root.sendOpen = false   // close form immediately
        var result = callModuleParse(
            logos.callModule("logos_wallet", "sendTransfer", [from, to, amount])
        )
        root.sendBusy = false
        if (!result || result.error) {
            logActivity("Transfer failed: " + (result && result.error ? result.error : "unknown"), true)
        } else {
            logActivity("Transfer: " + displayId(from) + " → " + displayId(to)
                        + " (" + amount + " TOK)", false)
            balanceRefreshTimer.restart()
            refreshTxHistory()
        }
    }

    // ── Timers ────────────────────────────────────────────────────────────────
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
        if (!root.cliFound) root.settingsOpen = true
    }

    onSelectedFromIdChanged: {
        root.txHistory = []
        txHistoryModel.clear()
        root.sendOpen = false
        toField.text = ""
        amountField.text = ""
        root.refreshTxHistory()
    }

    TextEdit { id: clipHelper; visible: false }

    // ── Root layout ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 10

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                spacing: 2
                Text { text: "Wallet"; font.pixelSize: 20; font.bold: true; color: root.textPrimary }
                Text { text: "Logos testnet"; font.pixelSize: 11; color: root.textSecondary }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                height: 24; implicitWidth: cliPillRow.implicitWidth + 16; radius: 12
                color: Qt.rgba(0.07, 0.07, 0.07, 1); border.color: root.borderColor; border.width: 1
                RowLayout {
                    id: cliPillRow
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    spacing: 5
                    Rectangle {
                        width: 6; height: 6; radius: 3
                        color: root.cliFound ? root.successGreen : root.errorRed
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text { text: root.cliFound ? "CLI ready" : "CLI not found"; font.pixelSize: 11; color: root.textPrimary }
                }
            }

            Rectangle {
                width: 28; height: 28; radius: 6; color: "transparent"
                border.color: root.settingsOpen ? root.accentOrange : root.borderColor; border.width: 1
                Text { anchors.centerIn: parent; text: "⚙"; font.pixelSize: 14; color: root.settingsOpen ? root.accentOrange : root.textSecondary }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.settingsOpen = !root.settingsOpen }
            }
        }

        // ── Settings panel ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            visible: root.settingsOpen
            height: visible ? settingsInner.implicitHeight + 20 : 0
            color: root.panelColor; border.color: root.borderColor; border.width: 1; radius: 4

            ColumnLayout {
                id: settingsInner
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 8

                Text { text: "Wallet CLI path"; color: root.textSecondary; font.pixelSize: 10 }
                Rectangle {
                    Layout.fillWidth: true; height: 26; color: "#0A0A0A"
                    border.color: root.borderColor; radius: 3
                    TextInput {
                        id: cliPathField
                        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.textPrimary; font.pixelSize: 11; font.family: "monospace"; clip: true
                        Text {
                            anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                            text: parent.text.length === 0 ? "~/.local/bin/wallet" : ""
                            color: root.textDisabled; font.pixelSize: 11; font.family: "monospace"
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 56; height: 24; radius: 4; color: "transparent"; border.color: root.accentOrange
                        Text { anchors.centerIn: parent; text: "Save"; color: root.accentOrange; font.pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
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

        // ── Two-column body ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // ── LEFT COLUMN — accounts ────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 180
                Layout.minimumWidth: 140
                Layout.fillHeight: true
                color: root.panelColor; border.color: root.borderColor; border.width: 1; radius: 6

                ColumnLayout {
                    anchors { fill: parent; margins: 8 }
                    spacing: 6

                    Text {
                        text: "ACCOUNTS"
                        color: root.accentOrange; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2
                    }

                    ListView {
                        id: accountListView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: ListModel { id: accountModel }
                        clip: true; spacing: 2

                        section.property: "type"
                        section.delegate: RowLayout {
                            width: accountListView.width
                            height: 20
                            spacing: 6
                            Text {
                                text: section === "public" ? "PUBLIC" : "PRIVATE"
                                color: root.textDisabled
                                font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2
                                Layout.leftMargin: 2
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: 1
                                color: root.borderColor
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: accountModel.count === 0
                            text: "No accounts"; color: root.textDisabled; font.pixelSize: 11
                        }

                        delegate: Rectangle {
                            required property string id
                            required property string type
                            required property string balance
                            width: accountListView.width
                            height: 40
                            radius: 4
                            color: root.selectedFromId === id
                                   ? Qt.rgba(249/255, 115/255, 22/255, 0.10)
                                   : (rowMa.containsMouse ? Qt.rgba(1,1,1,0.04) : "transparent")
                            border.color: root.selectedFromId === id
                                          ? Qt.rgba(249/255, 115/255, 22/255, 0.4)
                                          : "transparent"
                            border.width: 1

                            ColumnLayout {
                                anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 5; bottomMargin: 5 }
                                spacing: 2

                                Text {
                                    text: root.displayId(id)
                                    color: root.selectedFromId === id ? root.textPrimary : root.textSecondary
                                    font.pixelSize: 10; font.family: "monospace"
                                    Layout.fillWidth: true; elide: Text.ElideMiddle
                                }
                                Text {
                                    visible: balance !== "" && balance !== "—"
                                    text: balance + " TOK"
                                    color: root.selectedFromId === id ? root.accentOrange : root.textDisabled
                                    font.pixelSize: 9
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.selectedFromId      = id
                                    root.selectedFromBalance = balance
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 4; color: "transparent"
                        border.color: root.accentOrange
                        Text { anchors.centerIn: parent; text: "+ New Account"; color: root.accentOrange; font.pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.logActivity("Creating new account…", false)
                                var r = root.callModuleParse(logos.callModule("logos_wallet", "createAccount", []))
                                if (r && r.error) root.logActivity("createAccount: " + r.error, true)
                                else { root.logActivity("Account created", false); balanceRefreshTimer.restart() }
                            }
                        }
                    }
                }
            }

            // ── RIGHT COLUMN — balance + actions ─────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                // Big balance card
                Rectangle {
                    Layout.fillWidth: true
                    height: 96
                    color: root.panelColor; border.color: root.borderColor; border.width: 1; radius: 6

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        // Amount row: number + TOK (same size)
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 8

                            Text {
                                text: (root.selectedFromBalance !== "" && root.selectedFromBalance !== "—")
                                      ? root.selectedFromBalance : "0"
                                font.pixelSize: 38; font.bold: true; color: root.textPrimary
                            }
                            Text {
                                text: "TOK"
                                font.pixelSize: 38; font.bold: true; color: root.accentOrange
                            }
                        }

                        // Selected address + copy button
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4
                            visible: root.selectedFromId.length > 0

                            Text {
                                text: root.displayId(root.selectedFromId)
                                color: root.textDisabled; font.pixelSize: 10; font.family: "monospace"
                                elide: Text.ElideMiddle
                                Layout.maximumWidth: 220
                            }

                            Item {
                                width: 16; height: 16
                                Image {
                                    anchors.centerIn: parent
                                    width: 12; height: 12
                                    source: "icons/Copy.svg"; fillMode: Image.PreserveAspectFit
                                    opacity: addrCopyArea.pressed ? 0.4 : addrCopyArea.containsMouse ? 0.9 : 0.5
                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                }
                                MouseArea {
                                    id: addrCopyArea
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        clipHelper.text = root.selectedFromId
                                        clipHelper.selectAll(); clipHelper.copy()
                                    }
                                }
                            }
                        }
                    }
                }

                // Send + Claim Faucet buttons
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Send button — subtle when form open, prominent when Sending…
                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 4
                        color: root.sendBusy ? Qt.rgba(249/255, 115/255, 22/255, 0.08) : "transparent"
                        border.color: root.sendBusy ? root.accentOrange
                                    : root.sendOpen ? root.borderColor
                                    : root.accentOrange

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                visible: root.sendBusy
                                width: 6; height: 6; radius: 3
                                color: root.accentOrange
                                anchors.verticalCenter: parent.verticalCenter
                                SequentialAnimation on opacity {
                                    running: root.sendBusy; loops: Animation.Infinite
                                    NumberAnimation { to: 0.2; duration: 500 }
                                    NumberAnimation { to: 1.0; duration: 500 }
                                }
                            }

                            Text {
                                text: root.sendBusy ? "Sending…" : "Send"
                                color: root.sendBusy ? root.accentOrange
                                     : root.sendOpen  ? root.textSecondary
                                     : root.accentOrange
                                font.pixelSize: 12; font.bold: !root.sendOpen || root.sendBusy
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            enabled: !root.sendBusy
                            onClicked: root.sendOpen = !root.sendOpen
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: 34; radius: 4
                        color: "transparent"; border.color: root.borderColor
                        Text { anchors.centerIn: parent; text: "Claim Faucet"; color: root.textSecondary; font.pixelSize: 12 }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var acctId = root.selectedFromId
                                if (!acctId && accountModel.count > 0) acctId = accountModel.get(0).id
                                if (!acctId) { root.logActivity("No accounts — create one first", true); return }
                                root.logActivity("Claiming faucet → " + root.displayId(acctId).substring(0, 20) + "…", false)
                                var r = root.callModuleParse(logos.callModule("logos_wallet", "claimFaucet", [acctId]))
                                if (r && r.error) root.logActivity("claimFaucet: " + r.error, true)
                                else {
                                    root.logActivity("Faucet claim submitted (150 TOK)", false)
                                    balanceRefreshTimer.restart()
                                    root.refreshTxHistory()
                                }
                            }
                        }
                    }
                }

                // Send form — expands when sendOpen
                ColumnLayout {
                    visible: root.sendOpen
                    Layout.fillWidth: true
                    spacing: 6

                    Text { text: "To"; color: root.textSecondary; font.pixelSize: 10 }
                    Rectangle {
                        Layout.fillWidth: true; height: 26; color: "#0A0A0A"
                        border.color: toField.activeFocus ? root.accentOrange : root.borderColor; radius: 3
                        TextInput {
                            id: toField
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.textPrimary; font.pixelSize: 11; font.family: "monospace"; clip: true
                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: parent.text.length === 0 ? "recipient account id" : ""
                                color: root.textDisabled; font.pixelSize: 11; font.family: "monospace"
                            }
                        }
                    }

                    Text { text: "Amount (TOK)"; color: root.textSecondary; font.pixelSize: 10 }
                    Rectangle {
                        Layout.fillWidth: true; height: 26; color: "#0A0A0A"
                        border.color: amountField.activeFocus ? root.accentOrange : root.borderColor; radius: 3
                        TextInput {
                            id: amountField
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.textPrimary; font.pixelSize: 11; font.family: "monospace"; clip: true
                            inputMethodHints: Qt.ImhDigitsOnly
                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: parent.text.length === 0 ? "e.g. 10" : ""
                                color: root.textDisabled; font.pixelSize: 11; font.family: "monospace"
                            }
                        }
                    }

                    Rectangle {
                        id: confirmBtn
                        Layout.fillWidth: true; height: 36; radius: 4
                        property bool canSend: root.selectedFromId.length > 0
                                               && toField.text.trim().length > 0
                                               && amountField.text.trim().length > 0
                        color: canSend ? Qt.rgba(249/255, 115/255, 22/255, 0.12) : "transparent"
                        border.color: canSend ? root.accentOrange : root.borderColor
                        opacity: canSend ? 1.0 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: "Confirm Send"
                            color: confirmBtn.canSend ? root.accentOrange : root.textDisabled
                            font.pixelSize: 12; font.bold: confirmBtn.canSend
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: confirmBtn.canSend ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: confirmBtn.canSend
                            onClicked: {
                                root.executeSend(
                                    root.selectedFromId,
                                    toField.text.trim(),
                                    amountField.text.trim()
                                )
                            }
                        }
                    }
                }

                // Transaction history for selected account
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.panelColor; border.color: root.borderColor; border.width: 1; radius: 6

                    ColumnLayout {
                        anchors { fill: parent; margins: 8 }
                        spacing: 6

                        Text {
                            text: "TRANSACTIONS"
                            color: root.textDisabled; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1.2
                        }

                        Text {
                            visible: txHistoryModel.count === 0
                            text: "No transactions yet"
                            color: root.textDisabled; font.pixelSize: 11
                            Layout.alignment: Qt.AlignHCenter
                        }

                        ListView {
                            id: txHistoryView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: ListModel { id: txHistoryModel }
                            clip: true; spacing: 4

                            delegate: Rectangle {
                                required property string type
                                required property string amount
                                required property string ts
                                required property string sender
                                required property string receiver
                                width: txHistoryView.width
                                height: txRow.implicitHeight + 10
                                color: "transparent"
                                radius: 3

                                property bool isSent: type !== "faucet" && sender === root.selectedFromId
                                property string direction: type === "faucet" ? "Faucet"
                                                         : isSent ? "Sent" : "Received"
                                property string counterparty: isSent ? receiver : sender

                                ColumnLayout {
                                    id: txRow
                                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 5; leftMargin: 4; rightMargin: 4 }
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: direction
                                            color: root.textSecondary
                                            font.pixelSize: 11; font.bold: true
                                        }
                                        Text {
                                            text: amount + " TOK"
                                            color: root.textPrimary; font.pixelSize: 11; font.bold: true
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: ts.length > 10 ? ts.substring(11, 16) : ts
                                            color: root.textDisabled; font.pixelSize: 10
                                        }
                                    }

                                    Text {
                                        visible: type !== "faucet"
                                        text: (isSent ? "→ " : "← ") + root.displayId(counterparty)
                                        color: root.textDisabled; font.pixelSize: 10; font.family: "monospace"
                                        Layout.fillWidth: true; elide: Text.ElideMiddle
                                    }
                                }

                                Rectangle {
                                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                    height: 1; color: root.borderColor
                                    visible: index < txHistoryModel.count - 1
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Activity log (module ops) ──────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: -12
            height: 100
            color: "#0D0D0D"

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: root.borderColor
            }

            Item {
                anchors { top: parent.top; right: parent.right; topMargin: 4; rightMargin: 6 }
                width: 20; height: 20; z: 1
                Image {
                    anchors.centerIn: parent; width: 14; height: 14
                    source: "icons/Copy.svg"; fillMode: Image.PreserveAspectFit
                    opacity: logCopyArea.pressed ? 0.6 : logCopyArea.containsMouse ? 1.0 : 0.35
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    id: logCopyArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var text = "# activity log\n"
                        for (var i = 0; i < activityModel.count; i++) {
                            var e = activityModel.get(i)
                            text += "[" + e.ts + "] " + e.msg + "\n"
                        }
                        clipHelper.text = text; clipHelper.selectAll(); clipHelper.copy()
                    }
                }
            }

            ListView {
                id: activityView
                anchors { fill: parent; margins: 8 }
                model: ListModel { id: activityModel }
                clip: true; spacing: 1
                delegate: RowLayout {
                    required property string ts
                    required property string msg
                    required property bool   error
                    width: activityView.width
                    spacing: 6
                    Text {
                        text: ts
                        color: root.textDisabled; font.pixelSize: 10; font.family: "monospace"
                        Layout.alignment: Qt.AlignTop
                    }
                    Text {
                        text: msg
                        color: error ? root.errorRed : root.textSecondary
                        font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }

    } // ColumnLayout

    // ── Auto-select first account on initial load only ────────────────────────
    Connections {
        target: accountModel
        function onCountChanged() {
            // Only act when nothing is selected yet (first load)
            if (root.selectedFromId.length === 0 && accountModel.count > 0) {
                root.selectedFromId      = accountModel.get(0).id
                root.selectedFromBalance = accountModel.get(0).balance
            }
        }
    }
}
