"""Personal access tokens for the API — created in Settings, shown once."""
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import generate_api_token, get_current_user
from backend.models import ApiToken, User

router = APIRouter(prefix="/tokens", tags=["api-tokens"])

MAX_TOKENS = 20


class TokenCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    scope: Literal["read", "full"] = "full"


def _serialize(t: ApiToken) -> dict:
    return {
        "id": t.id,
        "name": t.name,
        "scope": t.scope,
        "prefix": t.prefix,
        "created_at": t.created_at,
        "last_used_at": t.last_used_at,
    }


@router.get("")
def list_tokens(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    tokens = db.execute(
        select(ApiToken).where(ApiToken.user_id == user.id).order_by(ApiToken.created_at)
    ).scalars()
    return [_serialize(t) for t in tokens]


@router.post("")
def create_api_token(
    body: TokenCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    count = len(
        db.execute(select(ApiToken).where(ApiToken.user_id == user.id)).scalars().all()
    )
    if count >= MAX_TOKENS:
        raise HTTPException(status_code=400, detail=f"Token limit reached ({MAX_TOKENS})")
    raw, token_hash, prefix = generate_api_token()
    token = ApiToken(
        user_id=user.id,
        name=body.name.strip(),
        token_hash=token_hash,
        prefix=prefix,
        scope=body.scope,
    )
    db.add(token)
    db.commit()
    # The only time the secret ever leaves the server
    return {**_serialize(token), "token": raw}


@router.delete("/{token_id}")
def delete_api_token(
    token_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    token = db.get(ApiToken, token_id)
    if token is None or token.user_id != user.id:
        raise HTTPException(status_code=404, detail="Token not found")
    db.delete(token)
    db.commit()
    return {"ok": True}
