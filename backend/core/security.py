import hashlib
import secrets
from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.clock import utcnow
from backend.core.config import JWT_ALGORITHM, SECRET_KEY, TOKEN_EXPIRE_DAYS
from backend.models.api_token import ApiToken
from backend.core.database import get_db
from backend.models.user import User

bearer_scheme = HTTPBearer(auto_error=False)

PAT_PREFIX = "forge_pat_"
READ_METHODS = {"GET", "HEAD", "OPTIONS"}


def generate_api_token() -> tuple[str, str, str]:
    """Returns (token, sha256_hash, display_prefix)."""
    token = PAT_PREFIX + secrets.token_urlsafe(32)
    return token, hashlib.sha256(token.encode()).hexdigest(), token[:16]


def _pat_user(request: Request, raw: str, db: Session) -> User:
    token = db.execute(
        select(ApiToken).where(
            ApiToken.token_hash == hashlib.sha256(raw.encode()).hexdigest()
        )
    ).scalar_one_or_none()
    if token is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    if token.scope == "read" and request.method not in READ_METHODS:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This token is read-only",
        )
    user = db.get(User, token.user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    # last-used is informational — throttle writes to one per 5 minutes
    now = utcnow()
    if token.last_used_at is None or (now - token.last_used_at).total_seconds() > 300:
        token.last_used_at = now
        db.commit()
    return user


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode(), hashed.encode())


def create_token(user_id: int) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=TOKEN_EXPIRE_DAYS)
    return jwt.encode({"sub": str(user_id), "exp": expire}, SECRET_KEY, algorithm=JWT_ALGORITHM)


def get_current_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    if credentials.credentials.startswith(PAT_PREFIX):
        return _pat_user(request, credentials.credentials, db)
    try:
        payload = jwt.decode(credentials.credentials, SECRET_KEY, algorithms=[JWT_ALGORITHM])
        user_id = int(payload["sub"])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user = db.get(User, user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def get_current_admin(user: User = Depends(get_current_user)) -> User:
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin only")
    return user
