"""Optional MQTT publisher for Home Assistant and friends. Configured
entirely by environment variables; a missing FORGE_MQTT_HOST (or a missing
paho-mqtt package) turns the whole module into a no-op.

Topics (prefix default 'forge'):
  {prefix}/{username}/state              retained JSON: streak, week counts…
  {prefix}/{username}/event/workout_finished   per-finish JSON event
Documented at /docs/webhooks-metrics.
"""
import json
import logging
import os
import threading

log = logging.getLogger("forge.mqtt")

HOST = os.environ.get("FORGE_MQTT_HOST", "")
PORT = int(os.environ.get("FORGE_MQTT_PORT", "1883"))
USERNAME = os.environ.get("FORGE_MQTT_USERNAME") or None
PASSWORD = os.environ.get("FORGE_MQTT_PASSWORD") or None
PREFIX = os.environ.get("FORGE_MQTT_PREFIX", "forge").strip("/")


def enabled() -> bool:
    return bool(HOST)


def _publish(topic: str, payload: dict, retain: bool = False) -> None:
    try:
        import paho.mqtt.publish as publish
    except ImportError:
        log.warning("FORGE_MQTT_HOST set but paho-mqtt is not installed")
        return
    auth = {"username": USERNAME, "password": PASSWORD} if USERNAME else None
    try:
        publish.single(
            topic,
            json.dumps(payload),
            hostname=HOST,
            port=PORT,
            auth=auth,
            retain=retain,
        )
    except Exception:
        log.exception("mqtt publish to %s failed", topic)


def publish_async(topic: str, payload: dict, retain: bool = False) -> None:
    """Fire-and-forget — a slow broker must never block a workout finish."""
    if not enabled():
        return
    threading.Thread(
        target=_publish, args=(topic, payload, retain), daemon=True
    ).start()


def state_topic(username: str) -> str:
    return f"{PREFIX}/{username}/state"


def event_topic(username: str, event: str) -> str:
    return f"{PREFIX}/{username}/event/{event}"


def build_state(username: str, widget_payload: dict) -> tuple[str, dict]:
    """The retained state message mirrors the /api/widget payload."""
    return state_topic(username), widget_payload


def publish_workout_finished(username: str, workout_summary: dict) -> None:
    publish_async(event_topic(username, "workout_finished"), workout_summary)


def publish_state(username: str, widget_payload: dict) -> None:
    topic, payload = build_state(username, widget_payload)
    publish_async(topic, payload, retain=True)
