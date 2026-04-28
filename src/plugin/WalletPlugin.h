#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QProcess>

#include "interface.h"

class WalletPlugin : public QObject, public PluginInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.logos.WalletModuleInterface" FILE "metadata.json")
    Q_INTERFACES(PluginInterface)

public:
    explicit WalletPlugin(QObject* parent = nullptr);
    ~WalletPlugin() override = default;

    QString name()    const override { return QStringLiteral("logos_wallet"); }
    QString version() const override { return QStringLiteral("0.1.0"); }

    Q_INVOKABLE void    initLogos(LogosAPI* api);

    // Status — checks if wallet CLI binary is available
    Q_INVOKABLE QString getStatus() const;

    // Config — wallet CLI binary path
    Q_INVOKABLE QString getConfig() const;
    Q_INVOKABLE QString setCliPath(const QString& path);

    // Account management
    Q_INVOKABLE QString listAccounts();
    Q_INVOKABLE QString getBalance(const QString& accountId);
    Q_INVOKABLE QString createAccount();
    Q_INVOKABLE QString initAccount(const QString& accountId);

    // Faucet
    Q_INVOKABLE QString claimFaucet(const QString& accountId);

    // Transfer — keycard auth must be performed in QML before calling this
    Q_INVOKABLE QString sendTransfer(const QString& from,
                                     const QString& to,
                                     const QString& amount);

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);

private:
    QString runWalletCommand(const QStringList& args, int timeoutMs = 30000);
    QString cliPath() const;

    static QString errorJson(const QString& msg);
    static QString okJson();

    void appendLog(const QString& line, const QString& level = QStringLiteral("info"));

    struct LogEntry { QString ts; QString msg; QString level; };
    QList<LogEntry> m_log;
    static constexpr int kMaxLogLines = 200;
};
