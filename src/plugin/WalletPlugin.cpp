#include "WalletPlugin.h"

#include <QSettings>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QStandardPaths>

static constexpr const char* kCliPathKey = "logos-wallet/cliPath";

// ── Helpers ───────────────────────────────────────────────────────────────────

QString WalletPlugin::errorJson(const QString& msg)
{
    QJsonObject o;
    o[QStringLiteral("error")] = msg;
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

QString WalletPlugin::okJson()
{
    QJsonObject o;
    o[QStringLiteral("ok")] = true;
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

void WalletPlugin::appendLog(const QString& line, const QString& level)
{
    if (m_log.size() >= kMaxLogLines)
        m_log.removeFirst();
    LogEntry e;
    e.ts    = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"));
    e.msg   = line.trimmed();
    e.level = level;
    m_log.append(e);
}

QString WalletPlugin::cliPath() const
{
    QSettings s;
    QString stored = s.value(QLatin1String(kCliPathKey)).toString().trimmed();
    if (!stored.isEmpty())
        return stored;

    // Default: ~/.local/bin/wallet, then PATH lookup
    QString localBin = QDir::homePath() + QStringLiteral("/.local/bin/wallet");
    if (QFile::exists(localBin))
        return localBin;
    return QStringLiteral("wallet");
}

// ── QProcess runner ──────────────────────────────────────────────────────────

QString WalletPlugin::runWalletCommand(const QStringList& args, int timeoutMs)
{
    QString bin = cliPath();
    appendLog(QStringLiteral("run: wallet ") + args.join(QLatin1Char(' ')));

    QProcess proc;
    proc.setProcessChannelMode(QProcess::MergedChannels);
    proc.start(bin, args);

    if (!proc.waitForStarted(3000)) {
        appendLog(QStringLiteral("failed to start: ") + proc.errorString(), QStringLiteral("error"));
        return errorJson(QStringLiteral("wallet CLI not found: ") + bin
                         + QStringLiteral(" — configure path in ⚙ settings"));
    }

    if (!proc.waitForFinished(timeoutMs)) {
        proc.kill();
        appendLog(QStringLiteral("timeout after %1ms").arg(timeoutMs), QStringLiteral("error"));
        return errorJson(QStringLiteral("wallet command timed out"));
    }

    QString out = QString::fromUtf8(proc.readAll()).trimmed();
    int exitCode = proc.exitCode();

    if (exitCode != 0) {
        appendLog(QStringLiteral("exit %1: ").arg(exitCode) + out.left(120), QStringLiteral("error"));
        // Try to parse as JSON (some commands return JSON errors)
        QJsonParseError pe;
        QJsonDocument doc = QJsonDocument::fromJson(out.toUtf8(), &pe);
        if (pe.error == QJsonParseError::NoError)
            return out;
        return errorJson(out.isEmpty() ? QStringLiteral("wallet command failed (exit %1)").arg(exitCode) : out);
    }

    appendLog(QStringLiteral("ok: ") + out.left(80));

    // If output is valid JSON, return as-is
    QJsonParseError pe;
    QJsonDocument doc = QJsonDocument::fromJson(out.toUtf8(), &pe);
    if (pe.error == QJsonParseError::NoError)
        return out;

    // Otherwise wrap in {"ok":true,"output":"..."}
    QJsonObject o;
    o[QStringLiteral("ok")]     = true;
    o[QStringLiteral("output")] = out;
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

// ── Lifecycle ─────────────────────────────────────────────────────────────────

WalletPlugin::WalletPlugin(QObject* parent)
    : QObject(parent)
{}

void WalletPlugin::initLogos(LogosAPI* api)
{
    logosAPI = api;
    appendLog(QStringLiteral("logos_wallet: initLogos called"));
}

// ── Status / Config ───────────────────────────────────────────────────────────

QString WalletPlugin::getStatus() const
{
    QString bin = cliPath();
    bool found = QFile::exists(bin) || (bin == QStringLiteral("wallet")); // PATH lookup: assume present if name only

    // Attempt a real existence check for PATH-style name
    if (bin == QStringLiteral("wallet")) {
        QProcess check;
        check.start(QStringLiteral("which"), {QStringLiteral("wallet")});
        check.waitForFinished(2000);
        found = (check.exitCode() == 0);
    }

    QJsonObject o;
    o[QStringLiteral("cliFound")] = found;
    o[QStringLiteral("cliPath")]  = bin;
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

QString WalletPlugin::getConfig() const
{
    QSettings s;
    QString stored = s.value(QLatin1String(kCliPathKey)).toString();
    QJsonObject o;
    o[QStringLiteral("cliPath")]    = stored;
    o[QStringLiteral("cliPathEff")] = cliPath();
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

QString WalletPlugin::setCliPath(const QString& path)
{
    QString p = path.trimmed();
    if (p.isEmpty())
        return errorJson(QStringLiteral("path is empty"));

    QSettings s;
    s.setValue(QLatin1String(kCliPathKey), p);
    s.sync();
    appendLog(QStringLiteral("cliPath saved: ") + p);
    return okJson();
}

// ── Account management ────────────────────────────────────────────────────────

QString WalletPlugin::listAccounts()
{
    return runWalletCommand({
        QStringLiteral("account"),
        QStringLiteral("ls"),
        QStringLiteral("-l")
    });
}

QString WalletPlugin::getBalance(const QString& accountId)
{
    if (accountId.trimmed().isEmpty())
        return errorJson(QStringLiteral("accountId is required"));

    return runWalletCommand({
        QStringLiteral("account"),
        QStringLiteral("get"),
        QStringLiteral("--account-id"),
        accountId.trimmed()
    });
}

QString WalletPlugin::createAccount()
{
    return runWalletCommand({
        QStringLiteral("account"),
        QStringLiteral("new"),
        QStringLiteral("public")
    });
}

QString WalletPlugin::initAccount(const QString& accountId)
{
    if (accountId.trimmed().isEmpty())
        return errorJson(QStringLiteral("accountId is required"));

    return runWalletCommand({
        QStringLiteral("auth-transfer"),
        QStringLiteral("init"),
        QStringLiteral("--account-id"),
        accountId.trimmed()
    });
}

// ── Faucet ────────────────────────────────────────────────────────────────────

QString WalletPlugin::claimFaucet(const QString& accountId)
{
    if (accountId.trimmed().isEmpty())
        return errorJson(QStringLiteral("accountId is required"));

    // CLI expects: wallet pinata claim --to Public/ID  (capital P)
    QString id = accountId.trimmed();
    QString toArg = (id.startsWith(QStringLiteral("Public/")) || id.startsWith(QStringLiteral("Private/")))
                  ? id
                  : QStringLiteral("Public/") + id;

    QString result = runWalletCommand({
        QStringLiteral("pinata"),
        QStringLiteral("claim"),
        QStringLiteral("--to"),
        toArg
    }, 60000);

    QJsonDocument doc = QJsonDocument::fromJson(result.toUtf8());
    if (!doc.isNull() && doc.object().value(QStringLiteral("ok")).toBool()) {
        QJsonObject entry;
        entry[QStringLiteral("type")]     = QStringLiteral("faucet");
        entry[QStringLiteral("receiver")] = accountId.trimmed();
        entry[QStringLiteral("amount")]   = QStringLiteral("150");
        entry[QStringLiteral("txId")]     = doc.object().value(QStringLiteral("txHash")).toString();
        entry[QStringLiteral("ts")]       = QDateTime::currentDateTime().toString(Qt::ISODate);
        saveTx(accountId.trimmed(), entry);
    }

    return result;
}

// ── Transaction history (local store) ─────────────────────────────────────────

static QString txHistoryKey(const QString& accountId)
{
    // Sanitise accountId so it is safe as a QSettings key segment
    QString safe = accountId;
    safe.replace(QLatin1Char('/'), QLatin1Char('_'));
    return QStringLiteral("logos-wallet/txHistory/") + safe;
}

void WalletPlugin::saveTx(const QString& accountId, const QJsonObject& entry)
{
    QSettings s;
    QString key = txHistoryKey(accountId);
    QJsonArray arr = QJsonDocument::fromJson(
        s.value(key).toByteArray()).array();
    arr.prepend(entry);                // newest first
    if (arr.size() > 50) arr.removeLast();
    s.setValue(key, QJsonDocument(arr).toJson(QJsonDocument::Compact));
    s.sync();
}

QString WalletPlugin::getTransactions(const QString& accountId)
{
    if (accountId.trimmed().isEmpty())
        return errorJson(QStringLiteral("accountId is required"));
    QSettings s;
    QByteArray raw = s.value(txHistoryKey(accountId.trimmed())).toByteArray();
    QJsonArray arr = QJsonDocument::fromJson(raw).array();
    return QJsonDocument(arr).toJson(QJsonDocument::Compact);
}

// ── Transfer ──────────────────────────────────────────────────────────────────

QString WalletPlugin::sendTransfer(const QString& from,
                                    const QString& to,
                                    const QString& amount)
{
    if (from.trimmed().isEmpty())
        return errorJson(QStringLiteral("from account is required"));
    if (to.trimmed().isEmpty())
        return errorJson(QStringLiteral("to account is required"));
    if (amount.trimmed().isEmpty())
        return errorJson(QStringLiteral("amount is required"));

    appendLog(QStringLiteral("transfer: %1 → %2 (%3 tok)").arg(from, to, amount));

    QString result = runWalletCommand({
        QStringLiteral("auth-transfer"),
        QStringLiteral("send"),
        QStringLiteral("--from"),
        from.trimmed(),
        QStringLiteral("--to"),
        to.trimmed(),
        QStringLiteral("--amount"),
        amount.trimmed()
    }, 60000);

    // On success, persist to local tx history for both accounts
    QJsonDocument doc = QJsonDocument::fromJson(result.toUtf8());
    if (!doc.isNull() && doc.object().value(QStringLiteral("ok")).toBool()) {
        QJsonObject entry;
        entry[QStringLiteral("type")]     = QStringLiteral("send");
        entry[QStringLiteral("sender")]   = from.trimmed();
        entry[QStringLiteral("receiver")] = to.trimmed();
        entry[QStringLiteral("amount")]   = amount.trimmed();
        entry[QStringLiteral("txId")]     = doc.object().value(QStringLiteral("txId")).toString();
        entry[QStringLiteral("ts")]       = QDateTime::currentDateTime().toString(Qt::ISODate);
        saveTx(from.trimmed(), entry);
        saveTx(to.trimmed(), entry);
    }

    return result;
}
