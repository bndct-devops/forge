"""Measurement trend smoothing: the time-aware EMA, rate, change window,
and the /measurements/{kind}/trend endpoint. Documented at /docs/the-math."""
from datetime import datetime, timedelta

import pytest

from backend.api.measurements import trend as trend_endpoint
from backend.models.measurement import Measurement
from backend.trend import change_over, rate_per_week, smooth

T0 = datetime(2026, 6, 1, 8, 0, 0)


def _entries(pairs):
    return [(T0 + timedelta(days=d), v) for d, v in pairs]


class TestSmooth:
    def test_first_entry_is_its_own_trend(self):
        assert smooth(_entries([(0, 100.0)])) == [100.0]

    def test_daily_step_is_ten_percent(self):
        t = smooth(_entries([(0, 100.0), (1, 110.0)]))
        assert t[1] == pytest.approx(101.0)

    def test_weekly_gap_takes_a_proportionally_bigger_step(self):
        # 1 - 0.9^7 ≈ 0.5217 — a week away pulls halfway, like 7 daily steps
        t = smooth(_entries([(0, 100.0), (7, 110.0)]))
        assert t[1] == pytest.approx(100 + 10 * (1 - 0.9**7))

    def test_gap_equals_repeated_daily_readings(self):
        # One reading after an 8-day gap ≡ that same value read daily for 8
        # days: the time-aware alpha makes sparse and dense logging agree
        daily = smooth(_entries([(0, 100.0)] + [(d, 110.0) for d in range(1, 9)]))
        gapped = smooth(_entries([(0, 100.0), (8, 110.0)]))
        assert daily[-1] == pytest.approx(gapped[-1])

    def test_noise_is_damped(self):
        values = [(0, 100.0), (1, 102.0), (2, 98.5), (3, 101.0), (4, 99.0)]
        t = smooth(_entries(values))
        # Trend never leaves the band of the data and moves far less than raw
        assert all(98.5 <= x <= 102.0 for x in t)
        assert max(t) - min(t) < 1.5


class TestRateAndChange:
    def test_linear_loss_recovers_the_slope(self):
        # 0.5/week loss, daily readings: after the startup transient decays,
        # the trend tracks the ramp with constant lag — same slope
        entries = _entries([(d, 100.0 - 0.5 * d / 7) for d in range(57)])
        t = smooth(entries)
        rate = rate_per_week(entries, t)
        assert rate == pytest.approx(-0.5, abs=0.02)

    def test_rate_needs_five_days_of_span(self):
        entries = _entries([(0, 100.0), (3, 99.5)])
        assert rate_per_week(entries, smooth(entries)) is None

    def test_change_28d_reads_trend_not_raw(self):
        entries = _entries([(0, 100.0), (7, 99.0), (14, 98.0), (28, 96.0)])
        t = smooth(entries)
        change = change_over(entries, t)
        assert change == pytest.approx(t[-1] - t[0])

    def test_change_none_for_single_entry(self):
        entries = _entries([(0, 100.0)])
        assert change_over(entries, smooth(entries)) is None


class TestTrendEndpoint:
    def _log(self, db, user, kind, pairs):
        for d, v in pairs:
            db.add(
                Measurement(
                    user_id=user.id, kind=kind, value=v, measured_at=T0 + timedelta(days=d)
                )
            )
        db.commit()

    def test_weight_trend_with_bmi(self, db, user):
        self._log(db, user, "Weight", [(0, 99.0), (7, 98.4), (14, 97.9), (21, 97.1)])
        self._log(db, user, "Height", [(0, 180.0)])
        data = trend_endpoint("Weight", user=user, db=db)
        assert len(data["points"]) == 4
        assert data["points"][0]["trend"] == 99.0
        assert data["rate_per_week"] is not None and data["rate_per_week"] < 0
        # BMI uses the *trend* weight over the latest height
        assert data["bmi"] == pytest.approx(data["trend"] / 1.80**2, abs=0.1)

    def test_bmi_absent_without_height(self, db, user):
        self._log(db, user, "Weight", [(0, 99.0), (7, 98.0)])
        assert trend_endpoint("Weight", user=user, db=db)["bmi"] is None

    def test_height_has_no_trend(self, db, user):
        with pytest.raises(Exception) as e:
            trend_endpoint("Height", user=user, db=db)
        assert getattr(e.value, "status_code", None) == 404
