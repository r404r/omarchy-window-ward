"""Race-safe setup and removal for Window Ward's user-owned Hyprland binding."""
from __future__ import annotations

import errno
import fcntl
import os
import stat
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

BEGIN = "-- BEGIN WINDOW WARD (managed by setup)"
END = "-- END WINDOW WARD"
MAX_BINDINGS_BYTES = 2 * 1024 * 1024


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
        descriptor = os.open(name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=directory_fd)
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
        descriptor = os.open(".window-ward.integration.lock", os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600, dir_fd=directory_fd)
    except OSError as error:
        if error.errno == errno.ELOOP:
            fail("refusing symlinked integration lock")
        raise
    try:
        require_safe_regular(descriptor, "integration lock")
        fcntl.flock(descriptor, fcntl.LOCK_EX)
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


def run_setup() -> None:
    root, bin_dir, bindings = paths()
    cli, expected = bin_dir / "window-ward", str(root / "bin" / "window-ward")
    block = binding_block(cli)
    bin_fd, binding_fd = secure_directory(bin_dir), secure_directory(bindings.parent)
    created_link = False
    try:
        with integration_lock(binding_fd):
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
            begin_count, end_count = contents.count(BEGIN.encode()), contents.count(END.encode())
            if begin_count != end_count or begin_count > 1:
                fail("malformed or duplicate managed block")
            if begin_count == 1:
                start, finish = contents.index(BEGIN.encode()), contents.index(END.encode()) + len(END)
                if contents[start:finish] != block:
                    fail("managed block was modified; refusing to overwrite it")
            else:
                write_backup(binding_fd, bindings.name, contents, mode)
                write_atomic(binding_fd, bindings.name, contents + (b"\n" if contents else b"") + block + b"\n", mode)
    except Exception:
        if created_link:
            with integration_lock(binding_fd):
                try:
                    metadata = os.stat("window-ward", dir_fd=bin_fd, follow_symlinks=False)
                    if stat.S_ISLNK(metadata.st_mode) and os.readlink("window-ward", dir_fd=bin_fd) == expected:
                        os.unlink("window-ward", dir_fd=bin_fd)
                except FileNotFoundError:
                    pass
        raise
    finally:
        os.close(bin_fd); os.close(binding_fd)
    print("Window Ward installed. Run: hyprctl reload && hyprctl configerrors")


def run_uninstall() -> None:
    root, bin_dir, bindings = paths()
    cli, expected = bin_dir / "window-ward", str(root / "bin" / "window-ward")
    block = binding_block(cli)
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
                    if contents[start:finish] != block:
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
