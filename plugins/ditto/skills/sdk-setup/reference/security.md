# Ditto Security Reference

Security model, production authentication, small-peers-only deployments, permissions, certificate revocation, incoming connections, input validation, data at rest, and webhooks for Ditto SDK 5.2.0, for every SDK. Copied from `§ Security` in `../../guide/reference/best-practices/security.md`; the code for each SDK is on its page in `../../guide/reference/best-practices/platforms/`, linked from each section.

## Security Model Overview

| Layer | How Ditto protects it |
|---|---|
| Peer identity | Each authenticated peer holds a certificate issued for its identity. With a shared key, each peer issues a self-signed certificate with the shared private key. |
| Encryption in transit | TLS 1.3 between peers (mutual TLS) and TLS between peers and Ditto Server. **Exception:** small-peers-only without a private key has no secret: peers do not authenticate each other, and the SDK documents the mode as unencrypted (see [Small-Peers-Only Deployments](../../guide/reference/best-practices/security.md#small-peers-only-deployments)). |
| Authorization | Read and write permissions returned by your authentication webhook, enforced by Ditto Server and by every participating device. |
| Revocation | Certificates issued to server-authenticated peers can be revoked centrally (SDK 5.1+). |
| Data at rest | Encrypted with an app-provided key on Swift and Kotlin (SDK 5.2+). On Flutter, JavaScript, and the other SDKs, not encrypted by Ditto: rely on OS protections and application-level encryption (see [Data at Rest](../../guide/reference/best-practices/security.md#data-at-rest)). |


## Authentication in Production

For production apps with real users, connect to Ditto Server and authenticate through an **authentication webhook** that you operate:

1. Your app signs the user in with your own identity system and receives a token (often a JWT).
2. In the expiration handler, the app calls `ditto.auth.login(token: ..., provider: 'YOUR_PROVIDER_NAME')`.
3. Ditto Server forwards the token to your webhook, which validates it and returns the user's ID, session lifetime, and permissions.
4. Ditto Server issues credentials to the device, and the device can sync within those permissions.

**✅ DO:**
- Use a webhook-based authentication provider for production.
- Issue short-lived tokens from your backend and fetch a fresh token every time the expiration handler runs.
- Keep `expirationSeconds` moderate (the example in [Webhook response](../../guide/reference/best-practices/security.md#webhook-response) uses 28800 seconds, 8 hours): permissions are issued together with the credentials, so changes in your webhook reach a device when it re-authenticates.
- Reject unknown or disabled users in the webhook with `{"authenticated": false}`.

**❌ DON'T:**
- Ship the development provider (`Authenticator.developmentProvider`) or the development token from the Ditto Portal in a production build. Anyone who has the development token gets the same access.
- Embed long-lived secrets or API keys in the app to mint tokens on the device.
- Rely only on client-side checks to restrict data access.

The client-side setup (expiration handler, `login`, `AuthResponse.exception`, `logout`) is described in [Authentication](../../guide/reference/best-practices/setup-and-lifecycle.md#authentication).


## Small-Peers-Only Deployments

Small-peers-only with a private key lets devices sync without Ditto Server, for example in air-gapped or closed networks. All peers share one private key and trust any peer that holds it.

**✅ DO:**
- Always pass a private key in production. Without it, peers do not authenticate each other: any device that runs the SDK with your Database ID (and a valid offline license token) can join the mesh and read and write all data. The SDK's API reference describes this mode as unencrypted in transit. In our testing over TCP, the traffic was TLS-wrapped with and without a key, but without a key no shared secret authenticated the peers, so treat the mode as unprotected (see [Shared keys must match, and traffic is TLS-wrapped without a key](../../guide/reference/knowledge/observations/connections-and-presence.md#shared-keys-must-match-and-traffic-is-tls-wrapped-without-a-key)).
- Roll out a new key to all devices together. Peers with different keys, or a peer with a key and one without, never connect. No API reports this; only `WARN` log lines appear on every retry (`invalid peer certificate: BadSignature`, or `DecryptError`).
- Distribute the key through a controlled channel, such as mobile device management (MDM) or secure provisioning, and keep it in secure storage on the device.
- Generate the key with Ditto's `ditto-authtool` or OpenSSL as described in the [authentication documentation](https://docs.ditto.live/key-concepts/authentication-and-authorization). The private key is a P-256 key with a named curve, as PKCS#8 DER encoded in base64 on one line: `openssl ecparam -name prime256v1 -genkey -noout | openssl pkcs8 -topk8 -nocrypt -outform DER | base64` (on Linux, `base64 -w 0`). In our testing, opening Ditto failed with a PEM file and with keys in other formats, such as those that `openssl genpkey` produces by default with LibreSSL on macOS (see [Shared keys must match, and traffic is TLS-wrapped without a key](../../guide/reference/knowledge/observations/connections-and-presence.md#shared-keys-must-match-and-traffic-is-tls-wrapped-without-a-key) for the error messages).
- Set the offline license token from Ditto with `setOfflineOnlyLicenseToken` before you start sync, and distribute a new token well before the current one expires. The expiry is checked against the device clock when the token is set: in our testing, a device whose clock was past the expiry could not start sync, while a running device whose clock jumped past the expiry kept syncing for the 10 seconds we watched (see [The offline license token expiry is checked against the device clock](../../guide/reference/knowledge/observations/configuration-and-diagnostics.md#the-offline-license-token-expiry-is-checked-against-the-device-clock)).

**❌ DON'T:**
- Hardcode the shared key in source code. Keys in an app binary can be extracted by decompiling the app.
- Use a shared key when you need per-user permissions or the ability to revoke a single device.

**Why:** Shared-key mode has no per-user identity. Every holder of the key has full access, individual devices cannot be revoked, and a leaked key compromises the whole deployment. If you need per-user access control or revocation, use a server connection with an authentication webhook.

The code that reads the key and the license token from secure provisioning, and the mistake of opening without a key: [DittoConfig in Flutter](../../guide/reference/best-practices/platforms/flutter.md#dittoconfig-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#dittoconfig-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#dittoconfig-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#dittoconfig-in-swift).


## Permissions

**Return the narrowest `read` and `write` rules that each role needs, as simple comparisons on `_id` fields in the legacy query syntax (`==`), and give peers that must relay data to each other write permission for it.** Your authentication webhook returns the user's permissions together with the authentication result. Permissions are expressed per collection as lists of queries for `read` and `write`.

### Webhook response

The webhook response must contain these fields (see the [authentication provider documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication) for the full schema):
- `authenticated`
- when `authenticated` is `true`: `userID`, `expirationSeconds`, and `permissions`
- `version`: `"1"` when the request contains `"version": "1"`; the authentication provider documentation includes it in its examples and says that a response without it is treated as the legacy format
- in each of `permissions.read` and `permissions.write`: both `everything` (boolean) and `queriesByCollection`

Use the response format and the permission query syntax shown in Ditto's [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) for the Ditto Server version you use.

```json
{
  "authenticated": true,
  "version": "1",
  "userID": "user-123",
  "expirationSeconds": 28800,
  "permissions": {
    "read": {
      "everything": false,
      "queriesByCollection": {
        "orders": ["_id.storeId == 'store-1'"],
        "products": ["true"]
      }
    },
    "write": {
      "everything": false,
      "queriesByCollection": {
        "orders": ["_id.storeId == 'store-1'"]
      }
    }
  }
}
```

Express permission rules as simple comparisons on `_id` fields, as in the example above. Permission queries use Ditto's legacy query syntax, not DQL: compare with `==` (as in `_id.storeId == 'store-1'`), not with the DQL `=`. The response schema also has a `qlVersion` field in `permissions`, next to `read` and `write` (`1` for DQL, `0`, the default, for the legacy syntax), but the data authorization documentation says that permissions must use the legacy syntax, so leave it out, as the example does. Note that `"true"` is a query string that matches every document (not a boolean). See the [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) before using more complex rules.

### Design `_id` for permission scoping

Permission queries can only reference the document's `_id`. Permissions on other (mutable) fields are not supported. Put every attribute you need for access control into a structured `_id`:

```sql
-- ✅ GOOD: The store that owns the order is part of the immutable _id,
-- so a permission rule such as "_id.storeId == 'store-1'" can match it
-- Arguments: {"order": {"_id": {"storeId": "store-1", "orderId": "order-1"}, "status": "open", "createdAt": "2026-01-15T10:30:00.000Z"}}
INSERT INTO orders DOCUMENTS (:order)
```

**✅ DO:**
- Decide on permission boundaries (user, store, organization) before shipping, and encode them in `_id`.
- Grant the narrowest `read` and `write` rules each role needs.

**❌ DON'T:**
- Plan to restrict access by a mutable field such as `status` or `ownerId`.
- Change the structure of `_id` later; document IDs cannot be changed after creation. See [Document IDs](../../guide/reference/best-practices/data-modeling.md#document-ids).

### Write authority and peer-to-peer relaying

Ditto's [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) describes how write permissions affect relaying: a device accepts a document from another peer only if that peer is authorized to write the document. As a result, data that must travel peer-to-peer requires mutual write permissions: a peer with read-only access to a document cannot relay it to a third device, even if both are subscribed. Take this into account for read-only roles (for example, customers who read messages written by staff); the same page describes the read-only model and its trade-offs.

### Identity metadata is visible to the mesh

The optional `identityServiceMetadata` returned by your webhook is signed and shared with every peer in the mesh, not only with directly connected peers (for example, through presence and connection requests). Keep it small, and never put in it secrets or personal data that other peers should not see. The same applies to peer metadata you set through presence (see [Presence](../../guide/reference/best-practices/setup-and-lifecycle.md#presence)).


## Certificate Revocation (SDK 5.1+)

With server authentication, you can revoke the certificates of users or devices that should lose access, for example after offboarding or when a device is lost. Revocations are created through the Ditto Server HTTP API with a filter on `userID` or `identityServiceMetadata` fields, signed, and propagated from Ditto Server to Small Peers and from peer to peer. Each peer verifies the revocation, refuses new connections from revoked peers, and drops existing ones.

**✅ DO:**
- **Reject the identity in your authentication webhook first**, then create the revocation. A revocation only applies to certificates issued before it was created; if the webhook still accepts the user, the device re-authenticates and regains access with a new certificate.
- Expect a delay for peers that are fully offline: they learn about the revocation when they next connect to a peer that has it.
- Treat revocations as permanent; they cannot be deleted.

**❌ DON'T:**
- Disable revocation checking in production.
- Expect revocation to work in shared-key deployments; it applies only to server-authenticated identities.

Revocation checking is **enabled by default** and controlled by the system parameter `PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED`:

```sql
SHOW PEER_CERTIFICATE_REVOCATION_CHECK_ENABLED
```

See the [revocations documentation](https://docs.ditto.live/cloud/revocations) for the HTTP API.


## Controlling Incoming Connections

**Use a connection request handler only as an additional filter on top of permissions: decide within a few seconds, and catch every error and deny explicitly: what an uncaught error does differs by SDK.** You can decide per connection whether to accept a peer, for example based on the signed `identityServiceMetadata`. The handler must return `allow` or `deny`. A handler that does not respond within about 10 seconds denies the connection, so keep it fast.

In our testing with SDK 5.1.0 and 5.2.0, the handler behaved as follows (see [A denied peer retries at the retry interval](../../guide/reference/knowledge/observations/connections-and-presence.md#a-denied-peer-retries-at-the-retry-interval)):
- **Both directions:** the handler runs not only for incoming connections but also for connections that this device initiates, and `deny` blocks those too.
- **New connections only:** switching the handler to `deny` does not drop existing connections. Removing the handler lets peers in again.
- **Retries:** a denied peer retries at its connection retry interval (`connect.retryInterval` of the transport configuration, 5 seconds by default), so the handler runs again at that interval for each rejected peer. The rejected peer gets no API signal; only an error appears in its log.
- **Errors and slow answers:** Ditto waits 10 seconds for the handler and then rejects the peer; a later `allow` does not let it in. A handler that throws is denied at once in Flutter, rejected after the 10 seconds in JavaScript, and **ends the app** in Kotlin, where a handler that does not answer keeps new peers out, cannot be removed, and ends the app when Ditto closes (connected peers keep syncing); the Swift handler cannot throw (in testing with SDK 5.1.0 and 5.2.0, `§ A connection request handler that does not answer within 10 seconds rejects the peer, and one that throws differs by SDK`). Catch every error, return `deny` explicitly, and answer well within 10 seconds.
- **Small-peers-only mode:** `identityServiceMetadata` is always empty, because there is no authentication webhook. `peerMetadata` is available, but each peer sets its own, so it is not a security check.

A handler that accepts only peers whose signed metadata belongs to this store, and denies at once on any error: [Transports and Presence in Flutter](../../guide/reference/best-practices/platforms/flutter.md#transports-and-presence-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#transports-and-presence-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#transports-and-presence-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#transports-and-presence-in-swift).

`global.syncGroup` in the transport configuration is an optimization, not a security boundary.


## Input Validation and Query Parameters

Ditto collections are schema-free, so the application is responsible for validating data before writing it. Always pass values to DQL as parameters.

**✅ DO:**
- Validate required fields, types, and ranges before `INSERT` or `UPDATE`.
- Pass every value as an argument (`:name` placeholders), including documents (`INSERT INTO orders DOCUMENTS (:order)`).
- Treat documents received from other peers as untrusted input when you render or process them.

**❌ DON'T:**
- Filter subscriptions by personal data or secrets, such as an email address. The subscription query and its arguments go to directly connected devices, and both devices write them to their on-disk logs (see [On-disk logs and exporting them](../../guide/reference/best-practices/logging-and-observability.md#on-disk-logs-and-exporting-them) and [Subscription queries and arguments appear in other devices' logs](../../guide/reference/knowledge/observations/configuration-and-diagnostics.md#subscription-queries-and-arguments-appear-in-other-devices-logs)). Filter by IDs that mean nothing on their own.
- Build DQL strings by interpolating user input. In our testing, the input `nobody' OR '1'='1` embedded as a string literal made a `SELECT` return every document and a `DELETE` delete every document; passed as an argument, it matched none (see [User input embedded in a statement changes what it matches](../../guide/reference/knowledge/observations/dql-behavior.md#user-input-embedded-in-a-statement-changes-what-it-matches)).

```sql
-- ✅ GOOD: Validate the values in app code (a known order ID, a status from
-- an allow list), then pass them as parameters
-- Arguments: {"id": "order-1", "status": "preparing"}
UPDATE orders SET status = :status WHERE _id = :id
```

How each SDK passes arguments, and what interpolated input does to a statement: [Executing DQL in Flutter](../../guide/reference/best-practices/platforms/flutter.md#executing-dql-in-flutter) · [JavaScript](../../guide/reference/best-practices/platforms/javascript.md#executing-dql-in-javascript) · [Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#executing-dql-in-kotlin) · [Swift](../../guide/reference/best-practices/platforms/swift.md#executing-dql-in-swift).

**Why:** Parameters keep values separate from the query text, so input cannot change the meaning of a statement. See [Parameters and Literals](../../guide/reference/best-practices/dql.md#parameters-and-literals).


## Data at Rest

**On Swift and Kotlin (SDK 5.2+), encrypt the local store with `DittoConfig.encryptionKey`; on Flutter and the other SDKs, rely on OS protection and encrypt sensitive values in your app.** Since SDK 5.2, the **Swift and Kotlin** SDKs can encrypt the local store, including attachments, with a 32-byte key that your app generates and passes in `DittoConfig.encryptionKey` on every open. Ditto does not store or manage the key: keep it outside the persistence directory, in the Keychain or the Android Keystore. Ditto does not convert an existing store in place, so switching between encrypted and unencrypted storage means deleting the local store (`Ditto.deleteStore` or `DittoFactory.deleteStore`) and syncing it again. The **Flutter**, JavaScript, and other SDKs do not encrypt the local database at rest, and have no API to enable it; see the [encryption at rest documentation](https://docs.ditto.live/sdk/latest/sync/encryption-at-rest).

Every SDK reports a typed error when a store cannot be opened for an encryption reason, with a reason such as a required, unexpected, or invalid key, an unsupported scheme, or corrupt metadata (see [DittoConfig in Kotlin](../../guide/reference/best-practices/platforms/kotlin.md#dittoconfig-in-kotlin) and [DittoConfig in Swift](../../guide/reference/best-practices/platforms/swift.md#dittoconfig-in-swift)).

The rest of this section applies wherever Ditto does not encrypt the store.

**✅ DO:**
- Rely on OS-level protection (iOS Data Protection, Android file-based encryption). These require a passcode or screen lock, and with the default settings they protect data mainly while the device is powered off or has not been unlocked since it started; they do not protect data on a device that has been unlocked since boot.
- For regulated or sensitive data, encrypt sensitive field values in your application before writing them to Ditto, and keep the keys in the platform's secure storage.
- On managed devices, enforce device encryption and screen locks through MDM.

**❌ DON'T:**
- Assume that apps installed from a public app store run on devices with encryption enabled; your app cannot enforce it.
- Store secrets such as tokens or keys in Ditto documents.
- Rely on `DELETE` or `EVICT` to remove values from the device. **Note (SDK 5.1.0 and 5.2.0):** in our testing, most deleted and evicted values could still be read from the store's database files after Ditto was closed, and they probably remain until the space is reused or reclaimed (see [Most deleted and evicted values remain in the database files](../../guide/reference/knowledge/observations/storage-and-deletion.md#most-deleted-and-evicted-values-remain-in-the-database-files)). To remove data from a device for sure, for example when a user logs out of a shared device (see [Switching users on a shared device](../../guide/reference/best-practices/setup-and-lifecycle.md#switching-users-on-a-shared-device)), close Ditto and delete the persistence directory (`deleteStore` in Swift and Kotlin), or encrypt the values in your app.

In Flutter Web apps, data is kept in memory only and is not written to disk.


## Webhook Security

Your authentication webhook decides who can access your data, so protect it like any other authentication endpoint:

- Serve it over HTTPS only, and validate the token's signature, issuer, audience, and expiry before returning `"authenticated": true`.
- Enable **webhook signatures** in the Ditto Portal or HTTP API. Ditto then sends a `ditto-signature` header (`t=<timestamp>,v1=<signature>`), an HMAC-SHA256 of `<timestamp>.<raw request body>` computed with your base64-decoded secret.
- Verify the signature against the **raw** request body (not re-serialized JSON), compare signatures in constant time, and reject requests whose timestamp is more than 300 seconds old.
- Accept any of the `v1` signatures during secret rotation, and rotate secrets periodically.

See the [webhook security documentation](https://docs.ditto.live/cloud/webhook-security) for reference implementations.


## Security Checklist

**✅ DO:**
- Use a server connection with a webhook-based authentication provider in production.
- Fetch fresh tokens from your backend in the expiration handler, and check `AuthResponse.exception`.
- In webhook responses, return `version` as the request sends it, and `everything` and `queriesByCollection` for both `read` and `write`, in the format of the authentication provider and data authorization documentation, with the narrowest rules each role needs.
- Model access-control attributes in `_id`.
- Reject identities in the webhook before creating a revocation, and keep revocation checking enabled.
- On devices that several people share, sign users out as described in [Switching users on a shared device](../../guide/reference/best-practices/setup-and-lifecycle.md#switching-users-on-a-shared-device).
- Always use a `privateKey` in small-peers-only deployments, and provision it securely.
- Decide which devices accept connections from other devices. A device that only sets `connect.tcpServers` also listens on all interfaces; bind `listen.tcp` to `127.0.0.1` where it must not (see [Transport Configuration](../../guide/reference/best-practices/setup-and-lifecycle.md#transport-configuration) and [A device that only connects over TCP also listens for TCP connections](../../guide/reference/knowledge/observations/connections-and-presence.md#a-device-that-only-connects-over-tcp-also-listens-for-tcp-connections)).
- Validate input and pass all values as DQL parameters.
- Protect sensitive data at rest: with `DittoConfig.encryptionKey` on Swift and Kotlin (SDK 5.2+), and elsewhere with OS protections and application-level encryption.
- Verify webhook signatures.

**❌ DON'T:**
- Ship the development provider or development token.
- Hardcode shared keys, tokens, or API keys in the app.
- Use small-peers-only without a private key outside development and tests.
- Rely on mutable fields, `syncGroup`, sync scopes, or client-side checks for access control.
- Put sensitive information in `identityServiceMetadata` or peer metadata.
- Store secrets such as tokens or keys in Ditto documents.
- Interpolate user input into DQL strings.
