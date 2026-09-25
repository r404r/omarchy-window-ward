"""Race-safe setup and removal for Window Ward's user-owned Hyprland binding."""
from __future__ import annotations

import errno
import fcntl
import os
import stat
import subprocess
import sys
import time
from contextlib import contextmanager
from pathlib import Path

BEGIN = "-- BEGIN WINDOW WARD (managed by setup)"
END = "-- END WINDOW WARD"
MAX_BINDINGS_BYTES = 2 * 1024 * 1024
LOCK_TIMEOUT_SECONDS = 3


class IntegrationError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise IntegrationError(message)


def testing_path(variable: str, default: Path) -> Path:
    if os.environ.get("WINDOW_WARD_TESTING") == "1" and os.environ.get(variable):
        return Path(os.environ[variable])
    return default


def secure_directory(path: Path, create: bool = True) -> int:
    """Open every ancestor with O_NOFOLLOW; create only missing directory components."""
    absolute = Path(os.path.abspath(path))
    descriptor = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
    try:
        for component in absolute.parts[1:]:
            try:
                next_descriptor = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=descriptor)
            except FileNotFoundError:
                if not create:
                    raise
                try:
                    os.mkdir(component, 0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
                next_descriptor = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=descriptor)
            except OSError as error:
                if error.errno in (errno.ELOOP, errno.ENOTDIR):
                    fail(f"refusing unsafe directory: {absolute}")
                raise
            os.close(descriptor)
            descriptor = next_descriptor
    except Exception:
        os.close(descriptor)
        raise
    metadata = os.fstat(descriptor)
    # We may create our own missing leaf directories, but must never "repair"
    # permissions on an existing user directory: doing so could weaken or alter
    # unrelated launcher/config ownership.
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o022:
        os.close(descriptor)
        fail(f"refusing unsafe directory: {path}")
    return descriptor


def require_safe_regular(fd: int, label: str) -> tuple[int, int]:
    metadata = os.fstat(fd)
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid() or metadata.st_mode & 0o022:
        fail(f"refusing unsafe {label}")
    if metadata.st_size > MAX_BINDINGS_BYTES:
        fail(f"{label} exceeds the {MAX_BINDINGS_BYTES}-byte limit")
    return metadata.st_size, stat.S_IMODE(metadata.st_mode)


def read_file(directory_fd: int, name: str, label: str) -> tuple[bytes, int] | None:
    try:
        descriptor = os.open(name, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=directory_fd)
    except FileNotFoundError:
        return None
    except OSError as error:
        if error.errno == errno.ELOOP:
            fail(f"refusing symlinked {label}")
        raise
    try:
        size, mode = require_safe_regular(descriptor, label)
        remaining, chunks = size + 1, []
        while remaining:
            chunk = os.read(descriptor, min(8192, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        contents = b"".join(chunks)
        if len(contents) > MAX_BINDINGS_BYTES:
            fail(f"{label} exceeds the {MAX_BINDINGS_BYTES}-byte limit")
        return contents, mode
    finally:
        os.close(descriptor)


def write_atomic(directory_fd: int, name: str, contents: bytes, mode: int) -> None:
    temporary = f".{name}.{os.urandom(12).hex()}.tmp"
    descriptor = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_CLOEXEC | os.O_NOFOLLOW, mode, dir_fd=directory_fd)
    try:
        offset = 0
        while offset < len(contents):
            offset += os.write(descriptor, contents[offset:])
        os.fsync(descriptor)
    except Exception:
        try: os.unlink(temporary, dir_fd=directory_fd)
        except FileNotFoundError: pass
        raise
    finally:
        os.close(descriptor)
    os.replace(temporary, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
    os.fsync(directory_fd)


def write_backup(directory_fd: int, name: str, contents: bytes, mode: int) -> None:
    write_atomic(directory_fd, f"{name}.window-ward-backup.{os.urandom(12).hex()}", contents, mode)


@contextmanager
def integration_lock(directory_fd: int):
    """Serialize setup/uninstall without accepting a pre-created symlink lock."""
    try:
        descriptor = os.open(".window-ward.integration.lock", os.O_CREAT | os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
    except OSError as error:
        if error.errno == errno.ELOOP:
            fail("refusing symlinked integration lock")
        raise
    try:
        require_safe_regular(descriptor, "integration lock")
        deadline = time.monotonic() + LOCK_TIMEOUT_SECONDS
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    fail("timed out waiting for integration lock")
                time.sleep(0.05)
        yield
    finally:
        os.close(descriptor)


def plugin_root() -> Path:
    return Path(__file__).resolve().parent.parent


def paths() -> tuple[Path, Path, Path]:
    home = Path.home()
    bin_dir = testing_path("WINDOW_WARD_BIN_DIR", home / ".local" / "bin")
    bindings = testing_path("WINDOW_WARD_BINDINGS", home / ".config" / "hypr" / "bindings.lua")
    return plugin_root(), bin_dir, bindings


def binding_block(cli: Path) -> bytes:
    # Omarchy 4.0.4 stable does not define o.rebind(). Keep its equivalent
    # explicit unbind/bind sequence so one generated block works on both the
    # supported stable release and current quattro.
    location = str(cli)
    if any(character in location for character in ('"', "\\", "\n")) or any(character.isspace() for character in location):
        fail("install path cannot contain quotes, backslashes, or whitespace")
    return (
        f'{BEGIN}\n'
        'hl.unbind("SUPER + W")\n'
        f'o.bind("SUPER + W", "Close window safely", "{location} close")\n'
        'hl.unbind("SUPER + Q")\n'
        f'o.bind("SUPER + Q", "Close window safely", "{location} close")\n'
        f'{END}'
    ).encode()


def legacy_binding_block(cli: Path) -> bytes:
    """Return the exact W-only block generated through Window Ward 0.4.0."""
    location = str(cli)
    if any(character in location for character in ('"', "\\", "\n")) or any(character.isspace() for character in location):
        fail("install path cannot contain quotes, backslashes, or whitespace")
    return f'{BEGIN}\nhl.unbind("SUPER + W")\no.bind("SUPER + W", "Close window safely", "{location} close")\n{END}'.encode()


def link_matches(directory_fd: int, expected: str) -> bool:
    try:
        metadata = os.stat("window-ward", dir_fd=directory_fd, follow_symlinks=False)
    except FileNotFoundError:
        return False
    if not stat.S_ISLNK(metadata.st_mode):
        fail("refusing to replace existing window-ward command")
    return os.readlink("window-ward", dir_fd=directory_fd) == expected


def binding_contents(directory_fd: int, name: str) -> bytes | None:
    existing = read_file(directory_fd, name, "bindings file")
    return existing[0] if existing is not None else None


def managed_block_present(contents: bytes | None, block: bytes) -> bool:
    if contents is None:
        return False
    begin_count, end_count = contents.count(BEGIN.encode()), contents.count(END.encode())
    if begin_count != 1 or end_count != 1:
        return False
    start, finish = contents.index(BEGIN.encode()), contents.index(END.encode()) + len(END)
    return contents[start:finish] == block


def reconcile_setup_failure(bin_fd: int, binding_fd: int, bindings_name: str, expected: str, block: bytes, original: bytes | None, created_link: bool) -> bool:
    """Leave a usable pair after an uncertain rename/fsync failure.

    A failed directory fsync can happen after rename.  Never overwrite an
    unknown user edit: inspect the exact managed block and only remove the link
    that this invocation created when the original binding is still present.
    """
    contents = binding_contents(binding_fd, bindings_name)
    if managed_block_present(contents, block):
        # The binding still names our launcher, so retaining an exact launcher
        # is safer than creating a dangling keybinding.
        return True
    # Only the byte-for-byte pre-transaction source establishes that no
    # binding can still reference our launcher.  A malformed or user-edited
    # block is source drift, not permission to remove a possibly referenced
    # link.
    if contents != original:
        return True
    if created_link and link_matches(bin_fd, expected):
        os.unlink("window-ward", dir_fd=bin_fd)
    return False


def run_setup() -> None:
    root, bin_dir, bindings = paths()
    cli, expected = bin_dir / "window-ward", str(root / "bin" / "window-ward")
    block = binding_block(cli)
    legacy_block = legacy_binding_block(cli)
    bin_fd, binding_fd = secure_directory(bin_dir), secure_directory(bindings.parent)
    created_link = False
    transaction_started = False
    original_binding: bytes | None = None
    try:
        with integration_lock(binding_fd):
            transaction_started = True
            existing_link = link_matches(bin_fd, expected)
            try:
                subprocess.run([expected, "status"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, check=True, timeout=3)
            except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                fail(f"cannot initialize configuration: {error}")
            if not existing_link:
                try:
                    os.symlink(expected, "window-ward", dir_fd=bin_fd)
                except FileExistsError:
                    fail("refusing to replace existing window-ward command")
                created_link = True
            existing = read_file(binding_fd, bindings.name, "bindings file")
            contents, mode = existing if existing is not None else (b"", 0o600)
            original_binding = existing[0] if existing is not None else None
            begin_count, end_count = contents.count(BEGIN.encode()), contents.count(END.encode())
            if begin_count != end_count or begin_count > 1:
                fail("malformed or duplicate managed block")
            if begin_count == 1:
                start, finish = contents.index(BEGIN.encode()), contents.index(END.encode()) + len(END)
                existing_block = contents[start:finish]
                if existing_block == legacy_block:
                    write_backup(binding_fd, bindings.name, contents, mode)
                    write_atomic(binding_fd, bindings.name, contents[:start] + block + contents[finish:], mode)
                elif existing_block != block:
                    fail("managed block was modified; refusing to overwrite it")
            else:
                write_backup(binding_fd, bindings.name, contents, mode)
                write_atomic(binding_fd, bindings.name, contents + (b"\n" if contents else b"") + block + b"\n", mode)
    except Exception:
        # Reacquire before inspecting.  The reconciliation deliberately does
        # not restore a backup or overwrite a drifted binding: a post-rename
        # fsync error is ambiguous.
        retained_integration = False
        if transaction_started:
            try:
                with integration_lock(binding_fd):
                    retained_integration = reconcile_setup_failure(bin_fd, binding_fd, bindings.name, expected, block, original_binding, created_link)
            except IntegrationError:
                # Another cooperative setup may be completing the transaction.
                # Preserve its files rather than guessing which launcher is safe
                # to remove; the original failure is still reported below.
                retained_integration = True
        if retained_integration:
            raise IntegrationError("setup interrupted after a binding update; managed integration was retained for safety. Verify bindings.lua and rerun setup or uninstall.")
        raise
    finally:
        os.close(bin_fd); os.close(binding_fd)
    print("Window Ward installed. Run: hyprctl reload && hyprctl configerrors")


def run_uninstall() -> None:
    root, bin_dir, bindings = paths()
    cli, expected = bin_dir / "window-ward", str(root / "bin" / "window-ward")
    block = binding_block(cli)
    legacy_block = legacy_binding_block(cli)
    bin_fd, binding_fd = secure_directory(bin_dir), secure_directory(bindings.parent)
    try:
        with integration_lock(binding_fd):
            existing = read_file(binding_fd, bindings.name, "bindings file")
            if existing is not None:
                contents, mode = existing
                begin_count, end_count = contents.count(BEGIN.encode()), contents.count(END.encode())
                if begin_count != end_count or begin_count > 1:
                    fail("malformed or duplicate managed block; refusing to remove it")
                if begin_count == 1:
                    start, finish = contents.index(BEGIN.encode()), contents.index(END.encode()) + len(END)
                    if contents[start:finish] not in (block, legacy_block):
                        fail("managed block was modified; refusing to remove it")
                    write_backup(binding_fd, bindings.name, contents, mode)
                    write_atomic(binding_fd, bindings.name, contents[:start] + contents[finish:], mode)
            if link_matches(bin_fd, expected):
                os.unlink("window-ward", dir_fd=bin_fd)
    finally:
        os.close(bin_fd); os.close(binding_fd)
    print("Window Ward integration removed; user configuration was preserved.")


def main(action: str) -> None:
    try:
        if action == "setup": run_setup()
        elif action == "uninstall": run_uninstall()
        else: fail("unknown integration action")
    except IntegrationError as error:
        print(f"Window Ward: {error}", file=sys.stderr)
        raise SystemExit(1)
