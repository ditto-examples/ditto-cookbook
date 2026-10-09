# Ditto Security Reference

Security model, production authentication, small-peers-only key handling, permissions, revocation, connection control, input validation, data at rest, and webhook security for Ditto SDK 5.1.0. Copied from `§ Security` in `../guide/reference/ditto.md`.

## Contents

- [Security model overview](#security-model-overview)
- [Authentication in production](#authentication-in-production)
- [Small-peers-only deployments](#small-peers-only-deployments)
- [Permissions](#permissions)
  - [Webhook response](#webhook-response)
  - [Design _id for permission scoping](#design-_id-for-permission-scoping)
  - [Write authority and peer-to-peer relaying](#write-authority-and-peer-to-peer-relaying)
  - [Identity metadata is visible to the mesh](#identity-metadata-is-visible-to-the-mesh)
- [Certificate revocation (SDK 5.1+)](#certificate-revocation-sdk-51)
- [Controlling incoming connections](#controlling-incoming-connections)
- [Input validation and query parameters](#input-validation-and-query-parameters)
- [Data at rest](#data-at-rest)
- [Webhook security](#webhook-security)
- [Security checklist](#security-checklist)

---

Ditto syncs data directly between devices, so security decisions apply to every peer in the mesh, not only to a server.

## Security model overview

| Layer | How Ditto protects it |
|---|---|
| Peer identity | Each authenticated peer holds a certificate issued for its identity. With a shared key, each peer issues a self-signed certificate with the shared private key. |
| Encryption in transit | TLS 1.3 between peers (mutual TLS) and TLS between peers and Ditto Server. **Exception:** `DittoConfigConnectSmallPeersOnly()` without a `privateKey` has no secret: peers do not authenticate each other, and the SDK documents the mode as unencrypted (see [Small-peers-only deployments](#small-peers-only-deployments)). |
| Authorization | Read and write permissions returned by your authentication webhook, enforced by Ditto Server and by every participating device. |
| Revocation | Certificates issued to server-authenticated peers can be revoked centrally (SDK 5.1+). |
| Data at rest | Not encrypted by Ditto. Rely on OS protections and application-level encryption (see [Data at rest](#data-at-rest)). |

`§ Security Model Overview`

## Authentication in production

For production apps with real users, connect with `DittoConfigConnectServer` and authenticate through an **authentication webhook** that you operate:

1. Your app signs the user in with your own identity system and receives a token (often a JWT).
2. In the expiration handler, the app calls `ditto.auth.login(token: ..., provider: 'YOUR_PROVIDER_NAME')`.
3. Ditto Server forwards the token to your webhook, which validates it and returns the user's ID, session lifetime, and permissions.
4. Ditto Server issues credentials to the device, and the device can sync within those permissions.

**✅ DO:**
- Use a webhook-based authentication provider for production.
- Issue short-lived tokens from your backend and fetch a fresh token every time the expiration handler runs.
- Keep `expirationSeconds` moderate (the example in [Webhook response](#webhook-response) uses 28800 seconds, 8 hours): permissions are issued together with the credentials, so changes in your webhook reach a device when it re-authenticates.
- Reject unknown or disabled users in the webhook with `{"authenticated": false}`.

**❌ DON'T:**
- Ship the development provider (`Authenticator.developmentProvider`) or the development token from the Ditto Portal in a production build. Anyone who has the development token gets the same access.
- Embed long-lived secrets or API keys in the app to mint tokens on the device.
- Rely only on client-side checks to restrict data access.

The client-side setup (expiration handler, `login`, `AuthResponse.exception`, `logout`) is described in [startup-and-lifecycle.md](startup-and-lifecycle.md#authentication).

`§ Authentication in Production`

## Small-peers-only deployments

`DittoConfigConnectSmallPeersOnly(privateKey: key)` lets devices sync without Ditto Server, for example in air-gapped or closed networks. All peers share one private key and trust any peer that holds it.

**✅ DO:**
- Always pass a `privateKey` in production. Without it, peers do not authenticate each other: any device that runs the SDK with your Database ID (and a valid offline license token) can join the mesh and read and write all data. The SDK's API reference describes this mode as unencrypted in transit. In our testing with SDK 5.1.0 over TCP, the traffic was TLS-wrapped, but no shared secret authenticated the peers, so treat the mode as unprotected.
- Roll out a new key to all devices together. Peers with different keys, or a peer with a key and one without, never connect. No API reports this; only `WARN` log lines appear on every retry (`invalid peer certificate: BadSignature`, or `DecryptError`).
- Distribute the key through a controlled channel, such as mobile device management (MDM) or secure provisioning, and keep it in secure storage on the device.
- Generate the key with Ditto's `ditto-authtool` or OpenSSL as described in the [authentication documentation](https://docs.ditto.live/key-concepts/authentication-and-authorization).
- Set the offline license token from Ditto with `ditto.setOfflineOnlyLicenseToken()` before `ditto.sync.start()`.

**❌ DON'T:**
- Hardcode the shared key in source code. Keys in an app binary can be extracted by decompiling the app.
- Use a shared key when you need per-user permissions or the ability to revoke a single device.

**Why:** Shared-key mode has no per-user identity. Every holder of the key has full access, individual devices cannot be revoked, and a leaked key compromises the whole deployment. If you need per-user access control or revocation, use a server connection with an authentication webhook.

```dart
// ✅ GOOD: The key and license token come from secure provisioning.
Future<Ditto> openProvisionedSmallPeer({
  required Future<String> Function() readKeyFromSecureStorage,
  required Future<String> Function() readLicenseFromSecureStorage,
}) async {
  final ditto = await Ditto.open(
    DittoConfig(
      databaseID: 'YOUR_DATABASE_ID', // any UUID shared by all peers
      connect: DittoConfigConnectSmallPeersOnly(
        privateKey: await readKeyFromSecureStorage(),
      ),
    ),
  );
  // Required before sync.start() in small-peers-only mode.
  ditto.setOfflineOnlyLicenseToken(await readLicenseFromSecureStorage());
  ditto.sync.start(); // no expiration handler is needed in this mode
  return ditto;
}
```

```dart
// ❌ BAD: No privateKey means peers are not authenticated (and the SDK
// documents the mode as unencrypted); a key in source code would be visible
// to anyone who decompiles the app.
Future<Ditto> openUnprotectedSmallPeer() {
  return Ditto.open(
    const DittoConfig(
      databaseID: 'YOUR_DATABASE_ID',
      connect: DittoConfigConnectSmallPeersOnly(),
    ),
  );
}
```

`§ Small-Peers-Only Deployments`

## Permissions

Your authentication webhook returns the user's permissions together with the authentication result. Permissions are expressed per collection as lists of queries for `read` and `write`.

### Webhook response

The webhook response must contain these fields (see the [authentication provider documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/cloud-authentication) for the full schema):
- `authenticated`
- when `authenticated` is `true`: `userID`, `expirationSeconds`, and `permissions`
- in each of `permissions.read` and `permissions.write`: both `everything` (boolean) and `queriesByCollection`

Use the response format and the permission query syntax shown in Ditto's [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) for the Ditto Server version you use.

```json
{
  "authenticated": true,
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

Express permission rules as simple comparisons on `_id` fields, as in the example above. Permission queries use Ditto's legacy query syntax, not DQL: compare with `==` (as in `_id.storeId == 'store-1'`), not with the DQL `=`. Note that `"true"` is a query string that matches every document (not a boolean). See the [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) before using more complex rules.

`§ Webhook response`

### Design _id for permission scoping

Permission queries can only reference the document's `_id`. Permissions on other (mutable) fields are not supported. Put every attribute you need for access control into a structured `_id`:

```dart
// ✅ GOOD: The store that owns the order is part of the immutable _id,
// so a permission rule such as "_id.storeId == 'store-1'" can match it.
Future<void> createOrder(Ditto ditto, String storeId, String orderId) async {
  await ditto.store.execute(
    'INSERT INTO orders DOCUMENTS (:order)',
    arguments: {
      'order': {
        '_id': {'storeId': storeId, 'orderId': orderId},
        'status': 'open',
        // utcTimestamp() is defined in the Timestamps section.
        'createdAt': utcTimestamp(),
      },
    },
  );
}
```

**✅ DO:**
- Decide on permission boundaries (user, store, organization) before shipping, and encode them in `_id`.
- Grant the narrowest `read` and `write` rules each role needs.

**❌ DON'T:**
- Plan to restrict access by a mutable field such as `status` or `ownerId`.
- Change the structure of `_id` later; document IDs cannot be changed after creation. See `§ Document IDs`.

``§ Design `_id` for permission scoping``

### Write authority and peer-to-peer relaying

Ditto's [data authorization documentation](https://docs.ditto.live/sdk/latest/auth-and-authorization/data-authorization) describes how write permissions affect relaying: a device accepts a document from another peer only if that peer is authorized to write the document. As a result, data that must travel peer-to-peer requires mutual write permissions: a peer with read-only access to a document cannot relay it to a third device, even if both are subscribed. Take this into account for read-only roles (for example, customers who read messages written by staff); the same page describes the read-only model and its trade-offs.

`§ Write authority and peer-to-peer relaying`

### Identity metadata is visible to the mesh

The optional `identityServiceMetadata` returned by your webhook is signed and shared with every peer in the mesh, not only with directly connected peers (for example, through presence and connection requests). Keep it small, and never put in it secrets or personal data that other peers should not see. The same applies to peer metadata you set through presence (see [transports-and-presence.md](transports-and-presence.md#presence)).

`§ Identity metadata is visible to the mesh`

## Certificate revocation (SDK 5.1+)

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

`§ Certificate Revocation (SDK 5.1+)`

## Controlling incoming connections

You can decide per connection whether to accept a peer, for example based on the signed `identityServiceMetadata`. The handler must return `allow` or `deny`. A handler that does not respond within about 10 seconds denies the connection, so keep it fast.

In our testing with SDK 5.1.0, the handler behaved as follows:
- **Both directions:** the handler runs not only for incoming connections but also for connections that this device initiates, and `deny` blocks those too.
- **New connections only:** switching the handler to `deny` does not drop existing connections. Setting it back to `null` lets peers in again.
- **Retries:** a denied peer retries about once per second, so the handler runs about once per second for each rejected peer. The rejected peer gets no API signal; only an error appears in its log.
- **Errors:** a handler that throws, or whose `Future` fails, denies the connection, but only after the 10-second timeout (observed with the JavaScript SDK). Catch errors and return `deny` explicitly.
- **Small-peers-only mode:** `identityServiceMetadata` is always empty, because there is no authentication webhook. `peerMetadata` is available, but each peer sets its own, so it is not a security check.

```dart
// ✅ GOOD: Accept only peers whose signed metadata belongs to this store.
// Requires DittoConfigConnectServer: identityServiceMetadata comes from your
// authentication webhook and is empty in small-peers-only mode.
void restrictConnectionsToStore(Ditto ditto, String storeId) {
  ditto.presence.connectionRequestHandler = (request) async {
    try {
      final metadata = request.identityServiceMetadata;
      return metadata['storeId'] == storeId
          ? ConnectionRequestAuthorization.allow
          : ConnectionRequestAuthorization.deny;
    } catch (_) {
      return ConnectionRequestAuthorization.deny; // decide now, not after the timeout
    }
  };
}
```

Permissions remain the primary access control; a connection handler is an additional filter. `global.syncGroup` in the transport configuration is an optimization, not a security boundary. To remove the handler, set `ditto.presence.connectionRequestHandler = null`.

`§ Controlling Incoming Connections`

## Input validation and query parameters

Ditto collections are schema-free, so the application is responsible for validating data before writing it. Always pass values to DQL as parameters.

**✅ DO:**
- Validate required fields, types, and ranges before `INSERT` or `UPDATE`.
- Pass every value through `arguments` (`:name` placeholders), including documents (`INSERT INTO orders DOCUMENTS (:order)`).
- Treat documents received from other peers as untrusted input when you render or process them.

**❌ DON'T:**
- Build DQL strings by interpolating user input.

```dart
// ✅ GOOD: Validate, then pass values as parameters.
Future<void> updateOrderStatus(Ditto ditto, String orderId, String status) async {
  const allowedStatuses = {'open', 'preparing', 'done'};
  if (orderId.isEmpty || !allowedStatuses.contains(status)) {
    throw ArgumentError('Invalid order update');
  }
  await ditto.store.execute(
    'UPDATE orders SET status = :status WHERE _id = :id',
    arguments: {'id': orderId, 'status': status},
  );
}
```

```dart
// ❌ BAD: User input becomes part of the query text (DQL injection).
Future<void> findOrdersByName(Ditto ditto, String name) async {
  await ditto.store.execute("SELECT * FROM orders WHERE customerName = '$name'");
}
```

**Why:** Parameters keep values separate from the query text, so input cannot change the meaning of a statement. See `§ Parameters and Literals`.

`§ Input Validation and Query Parameters`

## Data at rest

The Ditto SDK does **not** encrypt its local database at rest, and there is no supported API to enable it.

**✅ DO:**
- Rely on OS-level protection (iOS Data Protection, Android file-based encryption). These require a passcode or screen lock, and with the default settings they protect data mainly while the device is powered off or has not been unlocked since it started; they do not protect data on a device that has been unlocked since boot.
- For regulated or sensitive data, encrypt sensitive field values in your application before writing them to Ditto, and keep the keys in the platform's secure storage.
- On managed devices, enforce device encryption and screen locks through MDM.

**❌ DON'T:**
- Assume that apps installed from a public app store run on devices with encryption enabled; your app cannot enforce it.
- Store secrets such as tokens or keys in Ditto documents.

In Flutter Web apps, data is kept in memory only and is not written to disk.

`§ Data at Rest`

## Webhook security

Your authentication webhook decides who can access your data, so protect it like any other authentication endpoint:

- Serve it over HTTPS only, and validate the token's signature, issuer, audience, and expiry before returning `"authenticated": true`.
- Enable **webhook signatures** in the Ditto Portal or HTTP API. Ditto then sends a `ditto-signature` header (`t=<timestamp>,v1=<signature>`), an HMAC-SHA256 of `<timestamp>.<raw request body>` computed with your base64-decoded secret.
- Verify the signature against the **raw** request body (not re-serialized JSON), compare signatures in constant time, and reject requests whose timestamp is more than 300 seconds old.
- Accept any of the `v1` signatures during secret rotation, and rotate secrets periodically.

See the [webhook security documentation](https://docs.ditto.live/cloud/webhook-security) for reference implementations.

`§ Webhook Security`

## Security checklist

**✅ DO:**
- Use a server connection with a webhook-based authentication provider in production.
- Fetch fresh tokens from your backend in the expiration handler, and check `AuthResponse.exception`.
- In webhook responses, return `everything` and `queriesByCollection` for both `read` and `write`, in the format of the data authorization documentation, with the narrowest rules each role needs.
- Model access-control attributes in `_id`.
- Reject identities in the webhook before creating a revocation, and keep revocation checking enabled.
- Always use a `privateKey` in small-peers-only deployments, and provision it securely.
- Validate input and pass all values as DQL parameters.
- Protect sensitive data at rest with OS protections and application-level encryption.
- Verify webhook signatures.

**❌ DON'T:**
- Ship the development provider or development token.
- Hardcode shared keys, tokens, or API keys in the app.
- Use `DittoConfigConnectSmallPeersOnly()` without a key outside development and tests.
- Rely on mutable fields, `syncGroup`, sync scopes, or client-side checks for access control.
- Put sensitive information in `identityServiceMetadata` or peer metadata.
- Store secrets such as tokens or keys in Ditto documents.
- Interpolate user input into DQL strings.

`§ Security Checklist`
