"""Runnable check that the kit switches off pyannote's usage reporting (on by default upstream).
Run with the kit's venv python: python tests/test_privacy.py"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plugin", "skills", "meeting-minutes", "scripts"))
import speaker_profiles  # noqa: F401  (sets the switches on import, before pyannote is used)
from pyannote.audio.telemetry.metrics import is_metrics_enabled
assert not is_metrics_enabled(), "pyannote usage reporting is ON"
assert os.environ.get("HF_HUB_DISABLE_TELEMETRY") == "1"
print("telemetry off: ok")
