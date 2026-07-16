from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from backend.core import loginguard
from backend.core.database import get_db
from backend.core.security import (
    create_token,
    get_current_user,
    hash_password,
    verify_password,
)
from backend.models.user import User
from backend.schemas import (
    LoginRequest,
    SetupRequest,
    TokenResponse,
    UserOut,
    UserUpdate,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/setup-status")
def setup_status(db: Session = Depends(get_db)):
    count = db.execute(select(func.count(User.id))).scalar()
    return {"needs_setup": count == 0}


@router.post("/setup", response_model=TokenResponse)
def setup(body: SetupRequest, db: Session = Depends(get_db)):
    count = db.execute(select(func.count(User.id))).scalar()
    if count > 0:
        raise HTTPException(status_code=400, detail="Setup already completed")
    user = User(
        username=body.username.strip(),
        hashed_password=hash_password(body.password),
        is_admin=True,
    )
    db.add(user)
    db.commit()
    return TokenResponse(token=create_token(user.id), user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, request: Request, db: Session = Depends(get_db)):
    username = body.username.strip()
    ip = request.client.host if request.client else "unknown"
    wait = loginguard.retry_after(username, ip)
    if wait:
        raise HTTPException(
            status_code=429,
            detail=f"Too many attempts — try again in {wait}s",
            headers={"Retry-After": str(wait)},
        )
    user = db.execute(
        select(User).where(User.username == username)
    ).scalar_one_or_none()
    if user is None or not verify_password(body.password, user.hashed_password):
        loginguard.record_failure(username, ip)
        raise HTTPException(status_code=401, detail="Invalid username or password")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="Account disabled")
    loginguard.record_success(username, ip)
    return TokenResponse(token=create_token(user.id), user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user


@router.patch("/me", response_model=UserOut)
def update_me(
    body: UserUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.unit is not None:
        if body.unit not in ("kg", "lb"):
            raise HTTPException(status_code=400, detail="Unit must be kg or lb")
        user.unit = body.unit
    if body.default_rest_seconds is not None:
        user.default_rest_seconds = body.default_rest_seconds
    if body.weekly_goal is not None:
        user.weekly_goal = body.weekly_goal
    if body.password is not None:
        user.hashed_password = hash_password(body.password)
    db.add(user)
    db.commit()
    return user
