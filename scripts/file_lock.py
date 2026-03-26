"""
文件锁工具 — 防止多进程并发读写 JSON 文件导致数据丢失。

用法:
    from file_lock import atomic_json_update, atomic_json_read

    # 原子读取
    data = atomic_json_read(path, default=[])

    # 原子更新（读 → 修改 → 写回，全程持锁）
    def modifier(tasks):
        tasks.append(new_task)
        return tasks
    atomic_json_update(path, modifier, default=[])
"""
import json
import os
import pathlib
import sys
import tempfile
from typing import Any, Callable

# 跨平台文件锁支持
IS_WINDOWS = sys.platform == 'win32'
if IS_WINDOWS:
    import msvcrt
else:
    import fcntl


def _lock_file(fd: int, exclusive: bool = True) -> None:
    """跨平台文件锁"""
    if IS_WINDOWS:
        # Windows: 使用 msvcrt.locking
        mode = msvcrt.LK_NBLCK if exclusive else msvcrt.LK_NBRLCK
        try:
            msvcrt.locking(fd, mode, 1)
        except OSError:
            pass  # 锁定失败时继续（非阻塞模式）
    else:
        # Unix/Linux: 使用 fcntl
        lock_type = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
        fcntl.flock(fd, lock_type)


def _unlock_file(fd: int) -> None:
    """跨平台解锁"""
    if IS_WINDOWS:
        try:
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
    else:
        fcntl.flock(fd, fcntl.LOCK_UN)


def _lock_path(path: pathlib.Path) -> pathlib.Path:
    return path.parent / (path.name + '.lock')


def atomic_json_read(path: pathlib.Path, default: Any = None) -> Any:
    """持锁读取 JSON 文件。"""
    lock_file = _lock_path(path)
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lock_file), os.O_CREAT | os.O_RDWR)
    try:
        _lock_file(fd, exclusive=False)
        try:
            return json.loads(path.read_text(encoding='utf-8')) if path.exists() else default
        except Exception:
            return default
    finally:
        _unlock_file(fd)
        os.close(fd)


def atomic_json_update(
    path: pathlib.Path,
    modifier: Callable[[Any], Any],
    default: Any = None,
) -> Any:
    """
    原子地读取 → 修改 → 写回 JSON 文件。
    modifier(data) 应返回修改后的数据。
    使用临时文件 + rename 保证写入原子性。
    """
    lock_file = _lock_path(path)
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lock_file), os.O_CREAT | os.O_RDWR)
    try:
        _lock_file(fd, exclusive=True)
        # Read
        try:
            data = json.loads(path.read_text(encoding='utf-8')) if path.exists() else default
        except Exception:
            data = default
        # Modify
        result = modifier(data)
        # Atomic write via temp file + rename
        tmp_fd, tmp_path = tempfile.mkstemp(
            dir=str(path.parent), suffix='.tmp', prefix=path.stem + '_'
        )
        try:
            with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
            os.replace(tmp_path, str(path))
        except Exception:
            os.unlink(tmp_path)
            raise
        return result
    finally:
        _unlock_file(fd)
        os.close(fd)


def atomic_json_write(path: pathlib.Path, data: Any) -> None:
    """原子写入 JSON 文件（持排他锁 + tmpfile rename）。
    直接写入，不读取现有内容（避免 atomic_json_update 的多余读开销）。
    """
    lock_file = _lock_path(path)
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(lock_file), os.O_CREAT | os.O_RDWR)
    try:
        _lock_file(fd, exclusive=True)
        tmp_fd, tmp_path = tempfile.mkstemp(
            dir=str(path.parent), suffix='.tmp', prefix=path.stem + '_'
        )
        try:
            with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            os.replace(tmp_path, str(path))
        except Exception:
            os.unlink(tmp_path)
            raise
    finally:
        _unlock_file(fd)
        os.close(fd)
