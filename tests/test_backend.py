#!/usr/bin/env python3
"""Isolated regression tests for Window Ward's backend state boundaries."""
import copy
import os
import runpy
import tempfile
import unittest
from contextlib import contextmanager, nullcontext
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parent.parent


class MissingStore:
    def __init__(self):
        self.writes = []

    def read(self, missing_ok=False):
        return None

    def write(self, contents):
        self.writes.append(contents)


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.module = runpy.run_path(str(ROOT / "bin" / "window-ward"), run_name="ward_test")
        self.globals = self.module["close_window"].__globals__
        self.original = dict(self.globals)

    def tearDown(self):
        self.globals.clear()
        self.globals.update(self.original)

    def test_missing_default_is_normalized_and_independent(self):
        first, second = MissingStore(), MissingStore()
        first_config = self.module["load_config"](first)
        first_config["protectedApplications"][0]["match"]["initialClass"].append("changed")
        second_config = self.module["load_config"](second)
        self.assertEqual([], second_config["protectedApplications"][0]["match"]["initialClass"])
        self.assertIn(b'"initialClass":[]', first.writes[0])

    def test_add_focused_preserves_grouped_paused_rule(self):
        config = {"schemaVersion": 1, "enabled": True, "confirmWindowMs": 3000, "protectedApplications": [{"id": "chrome-group", "name": "Chrome", "enabled": False, "mode": "double-press", "match": {"class": ["chrome-*"], "initialClass": []}}]}
        writes = []

        @contextmanager
        def configuration():
            yield SimpleNamespace(write=lambda value: writes.append(value)), config

        self.globals.update(configuration=configuration, active_window=lambda: {"address": "0x1", "class": "chrome-pwa", "initialClass": "chrome-pwa"})
        self.module["add_focused"]("Chrome")
        self.assertFalse(config["protectedApplications"][0]["enabled"])
        self.assertEqual(["chrome-*"], config["protectedApplications"][0]["match"]["class"])
        self.assertEqual([], writes)

    def test_invalid_confirmation_tokens_rearm_without_dispatch(self):
        config = self.module["validate_config"](copy.deepcopy(self.module["DEFAULT_CONFIG"]))
        window = {"address": "0xabc", "class": "google-chrome", "initialClass": "google-chrome"}
        for token in (
            b"0xabc 1\n",
            b"v1 " + b"c" * 64 + b" " + b"b" * 64 + b" 1\n",
            b"v1 " + b"a" * 64 + b" " + b"b" * 64 + b" 200\n",
        ):
            events, stores = [], []

            class State:
                def __init__(self, *args):
                    self.directory_fd = os.open(tempfile.gettempdir(), os.O_RDONLY | os.O_DIRECTORY)
                    self.contents = token
                    stores.append(self)

                def locked(self): return nullcontext()
                def read(self, missing_ok=False): return self.contents
                def write(self, contents): self.contents = contents
                def remove(self): events.append("removed")
                def close(self): os.close(self.directory_fd)

            self.globals.update(
                configuration_snapshot=lambda: config,
                active_window=lambda: window,
                SecureStore=State,
                state_path=lambda: Path("/synthetic"),
                session_identity=lambda state: "a" * 64,
                window_identity=lambda item: "b" * 64,
                time=SimpleNamespace(monotonic_ns=lambda: 100 * 1_000_000),
                quiet_command=lambda argv: events.append("dispatch" if "eval" in argv else "notify"),
            )
            self.module["close_window"]()
            self.assertNotIn("dispatch", events)
            self.assertTrue(stores[0].contents.startswith(b"v1 "))

    def test_final_active_window_change_prevents_dispatch(self):
        events = []
        windows = iter((
            {"address": "0x1", "class": "terminal", "initialClass": "terminal"},
            {"address": "0x2", "class": "terminal", "initialClass": "terminal"},
        ))

        class State:
            def __init__(self, *args): self.directory_fd = os.open(tempfile.gettempdir(), os.O_RDONLY | os.O_DIRECTORY)
            def locked(self): return nullcontext()
            def remove(self): pass
            def close(self): os.close(self.directory_fd)

        self.globals.update(
            configuration_snapshot=lambda: {"enabled": False, "confirmWindowMs": 3000, "protectedApplications": []},
            active_window=lambda: next(windows),
            SecureStore=State,
            state_path=lambda: Path("/synthetic"),
            quiet_command=lambda argv: events.append(argv),
        )
        self.module["close_window"]()
        self.assertEqual([], events)

    def test_config_lock_is_not_held_during_external_query(self):
        held = [False]

        @contextmanager
        def configuration():
            held[0] = True
            try:
                yield None, {"enabled": False, "confirmWindowMs": 3000, "protectedApplications": []}
            finally:
                held[0] = False

        class State:
            def __init__(self, *args): self.directory_fd = os.open(tempfile.gettempdir(), os.O_RDONLY | os.O_DIRECTORY)
            def locked(self): return nullcontext()
            def remove(self): pass
            def close(self): os.close(self.directory_fd)

        def active_window():
            self.assertFalse(held[0])
            return {"address": "0x1", "class": "terminal", "initialClass": "terminal"}

        self.globals.update(configuration=configuration, active_window=active_window, SecureStore=State, state_path=lambda: Path("/synthetic"), quiet_command=lambda argv: None)
        self.module["close_window"]()


if __name__ == "__main__":
    unittest.main()
