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
