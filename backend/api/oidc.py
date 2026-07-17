"""OIDC single sign-on — Authorization Code + PKCE relying party.

Login resolves users by their stable (sub, issuer) pair. Forge accounts have
no email, so there is no auto-link-by-email: existing accounts link
explicitly from Settings, and unknown IdP users are provisioned (unless
auto-create is off). The callback hands Forge's normal JWT to the SPA in the
URL fragment (never the query string, which would land in logs)."""
import logging
import re
import secrets

from fastapi import APIRouter, Depends, Request
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core import config
from backend.core.database import get_db
from backend.core.oidc import get_oauth
from backend.core.security import create_token, get_current_user, hash_password
from backend.models import User

router = APIRouter(prefix="/auth/oidc", tags=["auth"])
log = logging.getLogger("forge.oidc")


class SSOError(Exception):
    def __init__(self, code: str):
        self.code = code


def _redirect_uri(request: Request) -> str:
    if config.OIDC_REDIRECT_URL:
        return config.OIDC_REDIRECT_URL
    # uvicorn runs with --proxy-headers in the container, so the scheme and
    # host reflect the public origin behind Pangolin/Caddy
    return str(request.base_url).rstrip("/") + "/api/auth/oidc/callback"


def _groups(claims: dict) -> list[str]:
    raw = claims.get(config.OIDC_GROUPS_CLAIM)
    return [str(g) for g in raw] if isinstance(raw, list) else []


def _unique_username(db: Session, claims: dict) -> str:
    base = (
        claims.get("preferred_username")
        or (claims.get("email") or "").split("@")[0]
        or f"user-{str(claims.get('sub'))[:8]}"
    )
    base = re.sub(r"[^a-z0-9_.-]", "", base.lower())[:56] or f"user-{str(claims.get('sub'))[:8]}"
    username, n = base, 2
    while db.execute(select(User).where(User.username == username)).scalar_one_or_none():
        username = f"{base}{n}"
        n += 1
    return username


def _resolve_user(db: Session, claims: dict) -> User:
    sub = claims.get("sub")
    if not sub:
        raise SSOError("claims")
    issuer = claims.get("iss") or config.OIDC_ISSUER
    groups = _groups(claims)
    if config.OIDC_ALLOWED_GROUP and config.OIDC_ALLOWED_GROUP not in groups:
        raise SSOError("not_allowed")

    user = db.execute(
        select(User).where(User.oidc_sub == str(sub), User.oidc_issuer == issuer)
    ).scalar_one_or_none()
    if user is not None:
        if not user.is_active:
            raise SSOError("not_allowed")
        # The IdP is the source of truth for role — but only for accounts it
        # provisioned; linked local accounts (incl. the break-glass admin)
        # are never mutated
        if user.auth_source == "oidc" and config.OIDC_ADMIN_GROUP:
            user.is_admin = config.OIDC_ADMIN_GROUP in groups
            db.commit()
        return user

    if not config.OIDC_AUTO_CREATE:
        raise SSOError("no_account")
    user = User(
        username=_unique_username(db, claims),
        hashed_password=hash_password(secrets.token_urlsafe(24)),
        is_admin=bool(config.OIDC_ADMIN_GROUP and config.OIDC_ADMIN_GROUP in groups),
        auth_source="oidc",
        oidc_sub=str(sub),
        oidc_issuer=issuer,
    )
    db.add(user)
    db.commit()
    log.info("provisioned OIDC user %s", user.username)
    return user


@router.get("/config")
def oidc_config():
    return {
        "enabled": config.OIDC_CONFIGURED,
        "button_label": config.OIDC_BUTTON_LABEL,
    }


@router.get("/login")
async def oidc_login(request: Request):
    if not config.OIDC_CONFIGURED:
        return RedirectResponse(url="/login?sso_error=disabled")
    oauth = get_oauth()
    return await oauth.forge.authorize_redirect(request, _redirect_uri(request))


@router.post("/link/start")
def oidc_link_start(request: Request, user: User = Depends(get_current_user)):
    """Mark the next handshake as an account-link for the signed-in user."""
    request.session["oidc_link_user_id"] = user.id
    return {"ok": True}


@router.post("/unlink")
def oidc_unlink(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if user.auth_source == "oidc":
        raise SSOError("cannot_unlink")  # the IdP owns this account entirely
    user.oidc_sub = None
    user.oidc_issuer = None
    db.commit()
    return {"ok": True}


@router.get("/callback")
async def oidc_callback(request: Request, db: Session = Depends(get_db)):
    if not config.OIDC_CONFIGURED:
        return RedirectResponse(url="/login?sso_error=disabled")
    oauth = get_oauth()
    try:
        token = await oauth.forge.authorize_access_token(request)
    except Exception:
        log.exception("OIDC token exchange failed")
        return RedirectResponse(url="/login?sso_error=exchange")

    claims = dict(token.get("userinfo") or {})
    if not claims.get("sub"):
        return RedirectResponse(url="/login?sso_error=claims")

    link_user_id = request.session.pop("oidc_link_user_id", None)
    try:
        if link_user_id is not None:
            taken = db.execute(
                select(User).where(
                    User.oidc_sub == str(claims["sub"]),
                    User.oidc_issuer == (claims.get("iss") or config.OIDC_ISSUER),
                )
            ).scalar_one_or_none()
            if taken is not None and taken.id != link_user_id:
                return RedirectResponse(url="/settings?sso_error=already_linked")
            user = db.get(User, link_user_id)
            if user is None:
                return RedirectResponse(url="/login?sso_error=no_account")
            user.oidc_sub = str(claims["sub"])
            user.oidc_issuer = claims.get("iss") or config.OIDC_ISSUER
            db.commit()
            return RedirectResponse(url="/settings?sso_linked=1")
        user = _resolve_user(db, claims)
    except SSOError as e:
        return RedirectResponse(url=f"/login?sso_error={e.code}")

    jwt = create_token(user.id)
    return RedirectResponse(url=f"/auth/callback#token={jwt}")
