# Single sign-on (OIDC)

Forge can sign users in through any OpenID Connect provider with a discovery
document — Pocket ID, Authelia, Authentik, Keycloak, Zitadel, and friends.
SSO is **additive**: username/password login keeps working, and a local admin
account always remains a break-glass login the IdP can't lock out.

## Provider setup

Create an OIDC client at your IdP:

- **Callback URL**: `https://<your-forge-host>/api/auth/oidc/callback` (must match exactly)
- **Grant**: Authorization Code (Forge uses PKCE automatically)
- **Scopes**: `openid profile email groups`

## Forge configuration

Add to the container environment:

```yaml
environment:
  - FORGE_OIDC_ENABLED=true
  - FORGE_OIDC_ISSUER=https://auth.example.com
  - FORGE_OIDC_CLIENT_ID=<from IdP>
  - FORGE_OIDC_CLIENT_SECRET=<from IdP>
```

| Variable | Default | Purpose |
|---|---|---|
| `FORGE_OIDC_ENABLED` | `false` | Master switch |
| `FORGE_OIDC_ISSUER` | – | IdP base URL (discovery is appended) |
| `FORGE_OIDC_CLIENT_ID` / `_CLIENT_SECRET` | – | Client credentials |
| `FORGE_OIDC_REDIRECT_URL` | derived | Explicit callback override (set behind unusual proxies) |
| `FORGE_OIDC_SCOPES` | `openid profile email groups` | |
| `FORGE_OIDC_GROUPS_CLAIM` | `groups` | Claim carrying group membership |
| `FORGE_OIDC_ADMIN_GROUP` | – | Members become Forge admins (IdP-provisioned accounts only) |
| `FORGE_OIDC_ALLOWED_GROUP` | – | If set, required to sign in at all |
| `FORGE_OIDC_AUTO_CREATE` | `true` | Provision unknown IdP users automatically |
| `FORGE_OIDC_BUTTON_LABEL` | `Sign in with SSO` | Login-page button text |

## How accounts resolve

1. A returning SSO user matches on the stable `(sub, issuer)` pair.
2. Unknown users are provisioned with a username derived from
   `preferred_username` (auto-create on), or rejected (off).
3. **Existing local accounts link explicitly**: sign in normally, then
   Settings → Account → *Link SSO sign-in*. After linking, both login paths
   reach the same account, and your password still works.

Admin mapping via `FORGE_OIDC_ADMIN_GROUP` only ever applies to accounts the
IdP provisioned — linked local accounts (like your original admin) are never
promoted or demoted by the IdP.

Pocket ID notes: the group's **Name** field (not Friendly Name) is what lands
in the `groups` claim, and per-client "Allowed User Groups" must include a
group for the claim to be emitted.
