from datetime import datetime

from pydantic import BaseModel, Field


# ── Auth / users ─────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    username: str
    password: str


class SetupRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=8)


class UserOut(BaseModel):
    id: int
    username: str
    is_admin: bool
    unit: str
    default_rest_seconds: int
    weekly_goal: int = 3

    model_config = {"from_attributes": True}


class TokenResponse(BaseModel):
    token: str
    user: UserOut


class UserUpdate(BaseModel):
    unit: str | None = None
    default_rest_seconds: int | None = Field(default=None, ge=0, le=3600)
    weekly_goal: int | None = Field(default=None, ge=1, le=7)
    password: str | None = Field(default=None, min_length=8)


class UserCreate(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=8)
    is_admin: bool = False


# ── Exercises ────────────────────────────────────────────────────────────────

class ExerciseCreate(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    muscle_group: str = Field(min_length=1, max_length=32)
    equipment: str = Field(default="Other", max_length=32)
    grip: str | None = Field(default=None, max_length=24)


class ExerciseOut(BaseModel):
    id: int
    name: str
    muscle_group: str
    equipment: str
    grip: str | None = None
    variant_of_id: int | None = None
    is_custom: bool
    last_used: datetime | None = None


# ── Routines ─────────────────────────────────────────────────────────────────

class RoutineExerciseIn(BaseModel):
    exercise_id: int
    set_count: int = Field(default=3, ge=1, le=20)
    rest_seconds: int | None = Field(default=None, ge=0, le=3600)
    superset_with_next: bool = False


class RoutineIn(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    exercises: list[RoutineExerciseIn] = []


# ── Workouts ─────────────────────────────────────────────────────────────────

class WorkoutStart(BaseModel):
    routine_id: int | None = None
    workout_id: int | None = None  # repeat a past workout's structure
    name: str | None = None


class WorkoutUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=128)
    notes: str | None = None
    started_at: datetime | None = None


class WorkoutExerciseOrder(BaseModel):
    exercise_ids: list[int]  # workout-exercise ids, in the desired order


class RecategorizeItem(BaseModel):
    id: int
    muscle_group: str = Field(min_length=1, max_length=32)


class RecategorizeIn(BaseModel):
    items: list[RecategorizeItem]


class WorkoutExerciseAdd(BaseModel):
    exercise_id: int


class WorkoutExerciseUpdate(BaseModel):
    rest_seconds: int | None = Field(default=None, ge=0, le=3600)
    superset_with_next: bool | None = None


class SetUpdate(BaseModel):
    weight: float | None = Field(default=None, ge=0)
    reps: int | None = Field(default=None, ge=0)
    is_completed: bool | None = None
    is_warmup: bool | None = None
    rpe: float | None = Field(default=None, ge=1, le=10)


class PastSet(BaseModel):
    weight: float | None
    reps: int | None
    is_pr: bool = False


class SetOut(BaseModel):
    id: int
    position: int
    weight: float | None
    reps: int | None
    is_completed: bool
    is_warmup: bool
    is_pr: bool

    model_config = {"from_attributes": True}


class WorkoutExerciseOut(BaseModel):
    id: int
    exercise_id: int
    name: str
    muscle_group: str
    equipment: str
    position: int
    rest_seconds: int | None
    sets: list[SetOut]
    previous_sets: list[PastSet]


class WorkoutOut(BaseModel):
    id: int
    name: str
    notes: str | None
    started_at: datetime
    finished_at: datetime | None
    exercises: list[WorkoutExerciseOut]


class PROut(BaseModel):
    exercise_name: str
    kind: str  # "weight" | "1rm"
    value: float
    reps: int


class WorkoutFinishResult(BaseModel):
    id: int
    name: str
    duration_seconds: int
    total_volume: float
    total_sets: int
    prs: list[PROut]


class WorkoutSummary(BaseModel):
    id: int
    name: str
    started_at: datetime
    finished_at: datetime | None
    duration_seconds: int
    total_volume: float
    total_sets: int
    pr_count: int
    exercise_summaries: list[str]
