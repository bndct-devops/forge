"""Update check — compares the running image version against ghcr tags.
Server-side because ghcr's registry API isn't CORS-friendly; cached so a
Settings visit doesn't hammer the registry."""
import json
import os
import re
import threading
import time
import urllib.request

from fastapi import APIRouter, Depends

from backend.core.security import get_current_user
from backend.models import User

router = APIRouter(prefix="/update-check", tags=["updates"])

IMAGE = "bndct-devops/forge"
CACHE_SECONDS = 6 * 3600

_lock = threading.Lock()
_cache: dict = {"at": 0.0, "latest": None}


def _fetch_latest_tag() -> str | None:
    token_res = urllib.request.urlopen(
        f"https://ghcr.io/token?scope=repository:{IMAGE}:pull", timeout=10
    )
    token = json.loads(token_res.read())["token"]
    req = urllib.request.Request(
        f"https://ghcr.io/v2/{IMAGE}/tags/list",
        headers={"Authorization": f"Bearer {token}"},
    )
    tags = json.loads(urllib.request.urlopen(req, timeout=10).read()).get("tags", [])
    versions = []
    for tag in tags:
        m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
        if m:
            versions.append((tuple(int(x) for x in m.groups()), tag))
    if not versions:
        return None
    return max(versions)[1]


@router.get("")
def update_check(force: bool = False, user: User = Depends(get_current_user)):
    current = os.environ.get("FORGE_VERSION", "dev")
    if not re.fullmatch(r"v\d+\.\d+\.\d+", current):
        return {"current": current, "latest": None, "update_available": False}

    with _lock:
        # a manual check bypasses the cache, throttled to once a minute
        max_age = 60 if force else CACHE_SECONDS
        if time.time() - _cache["at"] > max_age:
            try:
                _cache["latest"] = _fetch_latest_tag()
            except Exception:
                _cache["latest"] = None
            _cache["at"] = time.time()
        latest = _cache["latest"]

    def parse(v: str):
        return tuple(int(x) for x in v[1:].split("."))

    available = latest is not None and parse(latest) > parse(current)
    return {"current": current, "latest": latest, "update_available": available}
