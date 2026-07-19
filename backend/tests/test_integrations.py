"""Round-2 integrations: the widget payload, Health Auto Export ingest,
the weekly digest, and the MQTT topic/payload builders.
"""
from datetime import datetime

import pytest

from backend.api.measurements import ingest
from backend.api.widget import widget
from backend.core import mqtt
from backend.core.digest import build_digest, run_digests_if_due
from backend.models import Measurement

from .conftest import FROZEN_NOW, log_workout, make_exercise


class TestWidget:
    def test_payload_shape(self, db, user, freeze_now, monkeypatch):
        monkeypatch.setattr("backend.api.widget.utcnow", lambda: FROZEN_NOW)
        bench = make_exercise(db)
        log_workout(db, user, days_ago=0, entries=[(bench, [(100, 10)] * 2)])  # today (Mon)
        log_workout(db, user, days_ago=5, entries=[(bench, [(80, 10)])])       # last week
        data = widget(user=user, db=db)
        assert data["week_workouts"] == 1
        assert data["week_progress"] == "1/3"
        assert data["week_volume"] == 2000.0
        assert data["streak_weeks"] == 2
        assert data["last_workout"] == "today"
        assert data["days_since_last"] == 0

    def test_empty_history(self, db, user, freeze_now, monkeypatch):
        monkeypatch.setattr("backend.api.widget.utcnow", lambda: FROZEN_NOW)
        data = widget(user=user, db=db)
        assert data["streak_weeks"] == 0
        assert data["last_workout"] == "never"
        assert data["last_workout_at"] is None


HAE_PAYLOAD = {
    "data": {
        "metrics": [
            {
                "name": "weight_body_mass",
                "units": "kg",
                "data": [
                    {"date": "2026-07-19 08:01:12 +0200", "qty": 82.4},
                    {"date": "2026-07-20 08:03:40 +0200", "qty": 82.1},
                ],
            },
            {
                "name": "body_fat_percentage",
                "units": "%",
                "data": [{"date": "2026-07-20 08:03:40 +0200", "qty": 0.183}],
            },
            {
                "name": "step_count",
                "units": "count",
                "data": [{"date": "2026-07-20 00:00:00 +0200", "qty": 9000}],
            },
        ]
    }
}


class TestHealthIngest:
    def test_imports_weight_and_bodyfat(self, db, user):
        result = ingest(HAE_PAYLOAD, user=user, db=db)
        assert result["added"] == 3
        assert result["skipped"] == 1  # step_count is not a Forge kind
        rows = db.query(Measurement).order_by(Measurement.measured_at).all()
        kinds = {(m.kind, m.value) for m in rows}
        assert ("Weight", 82.4) in kinds and ("Weight", 82.1) in kinds
        # 0.183 fraction normalised to percent
        assert ("Body fat", 18.3) in kinds
        # timestamps converted to naive UTC (+0200 → -2h)
        assert rows[0].measured_at == datetime(2026, 7, 19, 6, 1, 12)

    def test_reimport_is_idempotent(self, db, user):
        ingest(HAE_PAYLOAD, user=user, db=db)
        result = ingest(HAE_PAYLOAD, user=user, db=db)
        assert result["added"] == 0
        assert db.query(Measurement).count() == 3

    def test_garbage_rejected(self, db, user):
        with pytest.raises(Exception) as e:
            ingest({"nope": 1}, user=user, db=db)
        assert getattr(e.value, "status_code", None) == 400


class TestDigest:
    def test_body_composition(self, db, user):
        bench = make_exercise(db)
        log_workout(db, user, days_ago=0, entries=[(bench, [(100, 10)] * 2)])   # this wk: 2000
        log_workout(db, user, days_ago=7, entries=[(bench, [(100, 10)])])       # last wk: 1000
        body = build_digest(db, user, FROZEN_NOW.date())
        assert body is not None
        assert "1/3 workouts" in body
        assert "2.0k kg (+100%)" in body

    def test_silent_with_no_recent_training(self, db, user):
        assert build_digest(db, user, FROZEN_NOW.date()) is None

    def test_only_fires_sunday_after_hour(self, monkeypatch):
        # FROZEN_NOW is a Monday — the tick must do nothing at all
        assert run_digests_if_due(now=FROZEN_NOW) == 0
        saturday_evening = datetime(2026, 7, 18, 20, 0, 0)
        assert run_digests_if_due(now=saturday_evening) == 0
        sunday_morning = datetime(2026, 7, 19, 8, 0, 0)
        assert run_digests_if_due(now=sunday_morning) == 0

    def test_sends_once_per_week(self, db, user, monkeypatch):
        sent = []
        monkeypatch.setattr("backend.core.digest._send_digest", lambda db, u, b: sent.append(b))
        monkeypatch.setattr("backend.core.digest.SessionLocal", lambda: db)
        monkeypatch.setattr(db, "close", lambda: None)
        user.weekly_digest = True
        bench = make_exercise(db)
        log_workout(db, user, days_ago=1, entries=[(bench, [(100, 10)])])
        db.commit()
        sunday = datetime(2026, 7, 26, 18, 0, 0)
        assert run_digests_if_due(now=sunday) == 1
        assert run_digests_if_due(now=sunday) == 0  # second tick same week: no-op
        assert len(sent) == 1


class TestMqtt:
    def test_topics(self):
        assert mqtt.state_topic("ben") == "forge/ben/state"
        assert mqtt.event_topic("ben", "workout_finished") == "forge/ben/event/workout_finished"

    def test_disabled_without_host(self, monkeypatch):
        monkeypatch.setattr(mqtt, "HOST", "")
        assert mqtt.enabled() is False
        # publish_async must be a silent no-op when disabled
        mqtt.publish_async("forge/x/state", {"a": 1})

    def test_state_payload_mirrors_widget(self):
        topic, payload = mqtt.build_state("ben", {"streak_weeks": 4})
        assert topic == "forge/ben/state"
        assert payload == {"streak_weeks": 4}
