"""Lazy Authlib OIDC client — built on first use so a bad or unreachable
issuer never breaks startup. Authorization Code + PKCE against any
discovery-capable IdP (Pocket ID, Authelia, Authentik, Keycloak, ...)."""
from authlib.integrations.starlette_client import OAuth

from backend.core import config

_oauth: OAuth | None = None


def get_oauth() -> OAuth:
    global _oauth
    if _oauth is None:
        oauth = OAuth()
        oauth.register(
            name="forge",
            server_metadata_url=(
                f"{config.OIDC_ISSUER.rstrip('/')}/.well-known/openid-configuration"
            ),
            client_id=config.OIDC_CLIENT_ID,
            client_secret=config.OIDC_CLIENT_SECRET,
            client_kwargs={
                "scope": config.OIDC_SCOPES,
                "code_challenge_method": "S256",
            },
        )
        _oauth = oauth
    return _oauth
