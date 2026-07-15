from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from backend.core.database import get_db
from backend.core.security import get_current_admin, hash_password
from backend.models.user import User
from backend.schemas import UserCreate, UserOut

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=list[UserOut])
def list_users(admin: User = Depends(get_current_admin), db: Session = Depends(get_db)):
    return db.execute(select(User).order_by(User.username)).scalars().all()


@router.post("", response_model=UserOut)
def create_user(
    body: UserCreate,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    username = body.username.strip()
    exists = db.execute(select(User).where(User.username == username)).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Username already taken")
    user = User(
        username=username,
        hashed_password=hash_password(body.password),
        is_admin=body.is_admin,
    )
    db.add(user)
    db.commit()
    return user


@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    if user_id == admin.id:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(user)
    db.commit()
    return {"ok": True}
