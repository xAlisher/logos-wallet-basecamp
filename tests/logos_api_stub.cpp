// Minimal LogosAPI stubs for tests — no liblogos_sdk.a linked.
// WalletPlugin tests never call initLogos() so only the type definitions are needed.

#include "logos_api.h"
#include "cpp/logos_api_client.h"
#include "cpp/logos_object.h"
#include "cpp/logos_api_provider.h"
#include "cpp/token_manager.h"

// ── LogosAPI ──────────────────────────────────────────────────────────────────
LogosAPI::LogosAPI(const QString& /*module_name*/, QObject* parent)
    : QObject(parent), m_provider(nullptr), m_token_manager(nullptr) {}

LogosAPI::~LogosAPI() {}

LogosAPIProvider* LogosAPI::getProvider()    const { return nullptr; }
LogosAPIClient*   LogosAPI::getClient(const QString&) const { return nullptr; }
TokenManager*     LogosAPI::getTokenManager() const { return nullptr; }

// ── LogosAPIClient ────────────────────────────────────────────────────────────
bool LogosAPIClient::isConnected() const { return false; }

QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariantList&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&,
    const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&,
    const QVariant&, const QVariant&, Timeout) { return {}; }
QVariant LogosAPIClient::invokeRemoteMethod(
    const QString&, const QString&, const QVariant&, const QVariant&,
    const QVariant&, const QVariant&, const QVariant&, Timeout) { return {}; }

// onEvent not used by WalletPlugin — no stub needed
