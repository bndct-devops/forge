import os
import secrets
from pathlib import Path

DATA_DIR = Path(os.environ.get("FORGE_DATA_DIR", "./data")).resolve()
DATA_DIR.mkdir(parents=True, exist_ok=True)

DATABASE_URL = f"sqlite:///{DATA_DIR / 'forge.db'}"

PORT = int(os.environ.get("FORGE_PORT", "8081"))

JWT_ALGORITHM = "HS256"
TOKEN_EXPIRE_DAYS = 30


def _load_secret_key() -> str:
    env_key = os.environ.get("FORGE_SECRET_KEY")
    if env_key:
        return env_key
    key_file = DATA_DIR / "secret_key"
    if key_file.exists():
        return key_file.read_text().strip()
    key = secrets.token_hex(32)
    key_file.write_text(key)
    key_file.chmod(0o600)
    return key


SECRET_KEY = _load_secret_key()


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


# ── OIDC single sign-on (optional; local login always keeps working) ─────────
OIDC_ENABLED = _env_bool("FORGE_OIDC_ENABLED", False)
OIDC_ISSUER = os.environ.get("FORGE_OIDC_ISSUER", "").strip()
OIDC_CLIENT_ID = os.environ.get("FORGE_OIDC_CLIENT_ID", "").strip()
OIDC_CLIENT_SECRET = os.environ.get("FORGE_OIDC_CLIENT_SECRET", "").strip()
# Explicit callback override; else derived from the request origin
OIDC_REDIRECT_URL = os.environ.get("FORGE_OIDC_REDIRECT_URL", "").strip()
OIDC_SCOPES = os.environ.get("FORGE_OIDC_SCOPES", "openid profile email groups")
OIDC_GROUPS_CLAIM = os.environ.get("FORGE_OIDC_GROUPS_CLAIM", "groups")
OIDC_ADMIN_GROUP = os.environ.get("FORGE_OIDC_ADMIN_GROUP", "").strip()
OIDC_ALLOWED_GROUP = os.environ.get("FORGE_OIDC_ALLOWED_GROUP", "").strip()
OIDC_AUTO_CREATE = _env_bool("FORGE_OIDC_AUTO_CREATE", True)
OIDC_BUTTON_LABEL = os.environ.get("FORGE_OIDC_BUTTON_LABEL", "Sign in with SSO")

OIDC_CONFIGURED = bool(OIDC_ENABLED and OIDC_ISSUER and OIDC_CLIENT_ID and OIDC_CLIENT_SECRET)
