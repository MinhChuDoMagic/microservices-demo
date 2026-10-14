#!/usr/bin/env python3
import os
import signal
import subprocess
import sys
import time

DEADLINE_SECONDS = 900
TERMINATION_GRACE_SECONDS = 10


def signal_process_group(process: subprocess.Popen[bytes], signal_number: int) -> None:
    try:
        os.killpg(process.pid, signal_number)
    except ProcessLookupError:
        pass


def main() -> int:
    process = subprocess.Popen(["bash", "sh/down.sh"], start_new_session=True)
    deadline = time.monotonic() + DEADLINE_SECONDS

    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            return process.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            continue

    signal_process_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        pass
    finally:
        signal_process_group(process, signal.SIGKILL)
        process.wait()

    print(
        f"ERROR: make down exceeded its fixed {DEADLINE_SECONDS}-second deadline.",
        file=sys.stderr,
    )
    return 124


if __name__ == "__main__":
    raise SystemExit(main())