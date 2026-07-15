"""Web Push plumbing: VAPID key management and delivery.

Keys are generated once and persisted in the data dir, so subscriptions
survive restarts. Delivery failures with 404/410 mean the subscription is
gone — callers should drop it."""
import base64
import json
import logging
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from pywebpush import WebPushException, webpush

from backend.core.config import DATA_DIR

logger = logging.getLogger(__name__)

_PRIVATE_PEM = DATA_DIR / "vapid_private.pem"
VAPID_CLAIMS = {"sub": "mailto:admin@forge.local"}


def _ensure_keys() -> None:
    if _PRIVATE_PEM.exists():
        return
    key = ec.generate_private_key(ec.SECP256R1())
    _PRIVATE_PEM.write_bytes(
        key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
    )
    _PRIVATE_PEM.chmod(0o600)


def public_key_b64() -> str:
    """Uncompressed P-256 point, base64url — the applicationServerKey for JS."""
    _ensure_keys()
    key = serialization.load_pem_private_key(_PRIVATE_PEM.read_bytes(), password=None)
    raw = key.public_key().public_bytes(
        serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint
    )
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def send_push(subscription: dict, payload: dict) -> bool:
    """Deliver one push. Returns False when the subscription is dead."""
    _ensure_keys()
    try:
        webpush(
            subscription_info=subscription,
            data=json.dumps(payload),
            vapid_private_key=str(_PRIVATE_PEM),
            vapid_claims=dict(VAPID_CLAIMS),
            ttl=120,
        )
        return True
    except WebPushException as e:
        status = getattr(e.response, "status_code", None)
        if status in (404, 410):
            return False
        logger.warning("push delivery failed: %s", e)
        return True  # transient — keep the subscription
    except Exception as e:  # DNS failures etc. — never crash a timer thread
        logger.warning("push delivery error: %s", e)
        return True
