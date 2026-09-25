#!/usr/bin/env python3
"""Isolated ownership, timeout and interrupted-transaction checks."""
import importlib.util
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "window_ward_integration.py"
spec = importlib.util.spec_from_file_location("ward_integration_test", MODULE_PATH)
assert spec and spec.loader
integration = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = integration
spec.loader.exec_module(integration)


def environment(tmp: Path) -> dict[str, str]:
    values = os.environ.copy()
    values.update({
        "WINDOW_WARD_TESTING": "1",
        "WINDOW_WARD_BIN_DIR": str(tmp / "bin"),
        "WINDOW_WARD_BINDINGS": str(tmp / "bindings.lua"),
        "WINDOW_WARD_CONFIG": str(tmp / "config.json"),
        "XDG_RUNTIME_DIR": str(tmp / "runtime"),
        "PYTHONDONTWRITEBYTECODE": "1",
    })
    return values


def checked(command: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, timeout=10)


with tempfile.TemporaryDirectory(prefix="window-ward-integration-") as temporary:
    tmp = Path(temporary)
    (tmp / "bin").mkdir()
    (tmp / "runtime").mkdir()
    (tmp / "bindings.lua").write_text("-- user binding\n", encoding="utf-8")
    env = environment(tmp)

    # Normal install/remove remains idempotent and preserves config.
    checked([sys.executable, "-B", str(ROOT / "scripts" / "setup")], env)
    checked([sys.executable, "-B", str(ROOT / "scripts" / "setup")], env)
    assert (tmp / "bin" / "window-ward").is_symlink()
    installed_block = (tmp / "bindings.lua").read_text(encoding="utf-8")
    assert installed_block.count(integration.BEGIN) == 1
    assert installed_block.count('hl.unbind("SUPER + W")') == 1
    assert installed_block.count('hl.unbind("SUPER + Q")') == 1
    assert installed_block.count('o.bind("SUPER + W", "Close window safely"') == 1
    assert installed_block.count('o.bind("SUPER + Q", "Close window safely"') == 1
    assert "o.rebind" not in installed_block
    checked([sys.executable, "-B", str(ROOT / "scripts" / "uninstall")], env)
    assert not (tmp / "bin" / "window-ward").exists()
    assert (tmp / "config.json").is_file()

    # The exact W-only block emitted through 0.4.0 is backed up and migrated.
    migration = tmp / "migration"
    (migration / "bin").mkdir(parents=True)
    (migration / "runtime").mkdir()
    migration_env = environment(migration)
    migration_launcher = migration / "bin" / "window-ward"
    migration_bindings = migration / "bindings.lua"
    migration_bindings.write_bytes(b"-- user binding\n" + integration.legacy_binding_block(migration_launcher) + b"\n")
    checked([sys.executable, "-B", str(ROOT / "scripts" / "setup")], migration_env)
    assert integration.binding_block(migration_launcher) in migration_bindings.read_bytes()
    assert integration.legacy_binding_block(migration_launcher) not in migration_bindings.read_bytes()
    assert len(list(migration.glob("bindings.lua.window-ward-backup.*"))) == 1
    checked([sys.executable, "-B", str(ROOT / "scripts" / "setup")], migration_env)
    assert len(list(migration.glob("bindings.lua.window-ward-backup.*"))) == 1
    checked([sys.executable, "-B", str(ROOT / "scripts" / "uninstall")], migration_env)
    assert not migration_launcher.exists()
    assert integration.BEGIN.encode() not in migration_bindings.read_bytes()

    # A current uninstall can also clean up an exact legacy block before setup
    # is rerun, but still refuses any user-edited variant.
    legacy_remove = tmp / "legacy-remove"
    (legacy_remove / "bin").mkdir(parents=True)
    (legacy_remove / "runtime").mkdir()
    legacy_env = environment(legacy_remove)
    legacy_launcher = legacy_remove / "bin" / "window-ward"
    legacy_launcher.symlink_to(ROOT / "bin" / "window-ward")
    legacy_bindings = legacy_remove / "bindings.lua"
    legacy_bindings.write_bytes(integration.legacy_binding_block(legacy_launcher) + b"\n")
    checked([sys.executable, "-B", str(ROOT / "scripts" / "uninstall")], legacy_env)
    assert not legacy_launcher.exists()
    assert integration.BEGIN.encode() not in legacy_bindings.read_bytes()

    # Similar-looking legacy blocks are user-owned once edited: neither setup
    # nor uninstall may normalize or remove them by guessing intent.
    edited_legacy = tmp / "edited-legacy"
    (edited_legacy / "bin").mkdir(parents=True)
    (edited_legacy / "runtime").mkdir()
    edited_env = environment(edited_legacy)
    edited_launcher = edited_legacy / "bin" / "window-ward"
    edited_bindings = edited_legacy / "bindings.lua"
    edited_contents = integration.legacy_binding_block(edited_launcher).replace(
        b'"Close window safely"', b'"My close command"'
    ) + b"\n"
    edited_bindings.write_bytes(edited_contents)
    failed = subprocess.run(
        [sys.executable, "-B", str(ROOT / "scripts" / "setup")],
        env=edited_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    )
    assert failed.returncode != 0
    assert edited_bindings.read_bytes() == edited_contents
    assert not edited_launcher.exists()
    edited_launcher.symlink_to(ROOT / "bin" / "window-ward")
    failed = subprocess.run(
        [sys.executable, "-B", str(ROOT / "scripts" / "uninstall")],
        env=edited_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    )
    assert failed.returncode != 0
    assert edited_bindings.read_bytes() == edited_contents
    assert edited_launcher.is_symlink()

    # FIFO input is rejected, not opened indefinitely before fstat validation.
    fifo = tmp / "bindings.lua"
    fifo.unlink()
    os.mkfifo(fifo, 0o600)
    failed = subprocess.run([sys.executable, "-B", str(ROOT / "scripts" / "setup")], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
    assert failed.returncode != 0
    fifo.unlink()
    fifo.write_text("-- user binding\n", encoding="utf-8")

    # Special integration locks are rejected before a potentially blocking
    # flock/open path is trusted.
    lock_fifo = tmp / ".window-ward.integration.lock"
    lock_fifo.unlink()
    os.mkfifo(lock_fifo, 0o600)
    failed = subprocess.run([sys.executable, "-B", str(ROOT / "scripts" / "setup")], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
    assert failed.returncode != 0
    lock_fifo.unlink()

    # Existing shared target directories are not chmodded or accepted.
    shared = tmp / "shared-bin"
    shared.mkdir(mode=0o777)
    shared.chmod(0o777)
    shared_env = environment(tmp)
    shared_env["WINDOW_WARD_BIN_DIR"] = str(shared)
    failed = subprocess.run([sys.executable, "-B", str(ROOT / "scripts" / "setup")], env=shared_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
    assert failed.returncode != 0 and (shared.stat().st_mode & 0o777) == 0o777

    # An exclusive lock holder produces a bounded, non-mutating failure.
    fd = os.open(tmp / ".window-ward.integration.lock", os.O_CREAT | os.O_RDWR, 0o600)
    import fcntl
    fcntl.flock(fd, fcntl.LOCK_EX)
    started = time.monotonic()
    failed = subprocess.run([sys.executable, "-B", str(ROOT / "scripts" / "setup")], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    elapsed = time.monotonic() - started
    fcntl.flock(fd, fcntl.LOCK_UN)
    os.close(fd)
    assert failed.returncode != 0 and 2.5 <= elapsed < 4.5
    assert integration.BEGIN not in fifo.read_text(encoding="utf-8")

    # Fault after rename: the binding already references the exact launcher,
    # so rollback must retain that launcher instead of creating a dangling key.
    original_fsync = integration.os.fsync
    calls = {"directories": 0}
    def fail_binding_directory_fsync(fd: int) -> None:
        mode = os.fstat(fd).st_mode
        if os.path.isdir(f"/proc/self/fd/{fd}"):
            calls["directories"] += 1
            if calls["directories"] == 2:
                raise OSError("injected post-rename fsync failure")
        original_fsync(fd)
    integration.os.fsync = fail_binding_directory_fsync
    previous = os.environ.copy()
    os.environ.update(env)
    try:
        try:
            integration.run_setup()
        except integration.IntegrationError as error:
            assert "managed integration was retained" in str(error)
        else:
            raise AssertionError("injected post-rename failure was not observed")
    finally:
        integration.os.fsync = original_fsync
    binding = fifo.read_text(encoding="utf-8")
    launcher = tmp / "bin" / "window-ward"
    assert integration.BEGIN in binding and launcher.is_symlink()

    # Return to a known base before exercising an independent source-drift
    # transaction.
    integration.run_uninstall()
    assert not launcher.exists()
    assert integration.BEGIN not in fifo.read_text(encoding="utf-8")

    # A source drift after an ambiguous rename must keep the launcher too;
    # only the exact pre-transaction bytes authorize rollback cleanup.
    binding_path = fifo
    original_write_atomic = integration.write_atomic
    def drift_then_fail(directory_fd, name, contents, mode):
        original_write_atomic(directory_fd, name, contents, mode)
        if name == binding_path.name:
            binding_path.write_text(binding_path.read_text(encoding="utf-8") + "-- drift during recovery\n", encoding="utf-8")
            raise OSError("injected post-rename drift")
    integration.write_atomic = drift_then_fail
    try:
        try:
            integration.run_setup()
        except integration.IntegrationError as error:
            assert "managed integration was retained" in str(error)
        else:
            raise AssertionError("drifted post-rename failure was not observed")
    finally:
        integration.write_atomic = original_write_atomic
    assert launcher.is_symlink() and "drift during recovery" in binding_path.read_text(encoding="utf-8")

    # Uninstall after an ambiguous post-rename fsync failure is safely
    # retryable: first pass retains launcher, retry removes the now-unreferenced
    # exact launcher without touching configuration.
    binding_path.write_bytes(integration.binding_block(launcher))
    integration.os.fsync = fail_binding_directory_fsync
    calls["directories"] = 0
    try:
        try:
            integration.run_uninstall()
        except OSError:
            pass
        else:
            raise AssertionError("uninstall post-rename failure was not observed")
    finally:
        integration.os.fsync = original_fsync
    assert launcher.is_symlink() and integration.BEGIN not in binding_path.read_text(encoding="utf-8")
    integration.run_uninstall()
    assert not launcher.exists()
    os.environ.clear(); os.environ.update(previous)

print("ok")
