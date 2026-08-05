#!/usr/bin/env python3
"""Capture distinct live PX4 EV fusion snapshots through the upstream listener.

PX4's multi-message ``listener -n/-r`` mode is a rate-limited observer, not a
guarantee that every printed payload represents a distinct fusion.  This tool
uses independent one-message latest-value copies, ignores exact duplicate
samples, and accepts only a strictly advancing sequence.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from typing import Callable, Literal


TOPIC = "estimator_aid_src_ev_pos"
ANSI_ESCAPE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
NONFINITE = re.compile(r"(^|[^A-Za-z])(nan|inf)([^A-Za-z]|$)", re.IGNORECASE)


class SnapshotError(RuntimeError):
    """A live snapshot violates the frozen readiness contract."""


@dataclass(frozen=True)
class AidSnapshot:
    raw: str
    estimator_instance: int
    timestamp: int
    timestamp_sample: int
    time_last_fuse: int
    fused: bool
    innovation_rejected: bool


def _single_field(text: str, name: str) -> str:
    prefix = f"{name}:"
    values: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith(prefix):
            continue
        remainder = stripped[len(prefix) :].strip()
        if not remainder:
            raise SnapshotError(f"empty field: {name}")
        values.append(remainder.split()[0])
    if len(values) != 1:
        raise SnapshotError(f"field {name} occurs {len(values)} times")
    return values[0]


def _positive_integer(text: str, name: str) -> int:
    if not re.fullmatch(r"[1-9][0-9]*", text):
        raise SnapshotError(f"field {name} is not a positive integer: {text!r}")
    return int(text)


def parse_snapshot(raw: str) -> AidSnapshot:
    text = ANSI_ESCAPE.sub("", raw)
    headers = [line for line in text.splitlines() if line.strip() == f"TOPIC: {TOPIC}"]
    if len(headers) != 1:
        raise SnapshotError(f"expected one {TOPIC}[0] block, got {len(headers)}")
    if NONFINITE.search(text):
        raise SnapshotError("snapshot contains NaN or Inf")
    lowered = text.lower()
    if "never published" in lowered or "without a message" in lowered:
        raise SnapshotError("PX4 listener did not receive a message")

    instance_text = _single_field(text, "estimator_instance")
    if instance_text != "0":
        raise SnapshotError(f"unexpected estimator instance: {instance_text!r}")
    fused_text = _single_field(text, "fused")
    rejected_text = _single_field(text, "innovation_rejected")
    if fused_text not in {"True", "False"}:
        raise SnapshotError(f"invalid fused value: {fused_text!r}")
    if rejected_text not in {"True", "False"}:
        raise SnapshotError(
            f"invalid innovation_rejected value: {rejected_text!r}"
        )
    if fused_text != "True":
        raise SnapshotError("PX4 reports fused=False")
    if rejected_text != "False":
        raise SnapshotError("PX4 reports innovation_rejected=True")

    return AidSnapshot(
        raw=text.rstrip() + "\n",
        estimator_instance=0,
        timestamp=_positive_integer(_single_field(text, "timestamp"), "timestamp"),
        timestamp_sample=_positive_integer(
            _single_field(text, "timestamp_sample"), "timestamp_sample"
        ),
        time_last_fuse=_positive_integer(
            _single_field(text, "time_last_fuse"), "time_last_fuse"
        ),
        fused=True,
        innovation_rejected=False,
    )


class SequenceValidator:
    def __init__(self) -> None:
        self.accepted: list[AidSnapshot] = []
        self.duplicates = 0

    def observe(self, sample: AidSnapshot) -> Literal["accepted", "duplicate"]:
        if not self.accepted:
            self.accepted.append(sample)
            return "accepted"

        previous = self.accepted[-1]
        if sample.timestamp == previous.timestamp:
            if (
                sample.timestamp_sample != previous.timestamp_sample
                or sample.time_last_fuse != previous.time_last_fuse
            ):
                raise SnapshotError(
                    "duplicate producer timestamp changed sample or fusion time"
                )
            self.duplicates += 1
            return "duplicate"
        if sample.timestamp < previous.timestamp:
            raise SnapshotError("producer timestamp moved backwards")
        if sample.timestamp_sample <= previous.timestamp_sample:
            raise SnapshotError("timestamp_sample did not strictly advance")
        if sample.time_last_fuse <= previous.time_last_fuse:
            raise SnapshotError("time_last_fuse did not strictly advance")
        self.accepted.append(sample)
        return "accepted"


def _write_private(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        stream.write(text)


def _listener_command(project_dir: Path) -> list[str]:
    return [
        str(project_dir / "scripts/proot-run.sh"),
        "bash",
        "-lc",
        (
            "cd /project/vendor/PX4-Autopilot && "
            "LC_ALL=C timeout --signal=INT --kill-after=2s 6s "
            "./build/px4_sitl_default/bin/px4-listener --instance 0 "
            f"{TOPIC} -n 1"
        ),
    ]


ListenerResult = subprocess.CompletedProcess[str]
ListenerRunner = Callable[[list[str], Path, float], ListenerResult]
Clock = Callable[[], float]
Sleeper = Callable[[float], None]


def _run_listener(command: list[str], cwd: Path, timeout: float) -> ListenerResult:
    return subprocess.run(
        command,
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )


def _text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def _record_stream(
    diagnostics: list[str], attempt: int, stream_name: str, value: object
) -> None:
    rendered = _text(value)
    if rendered:
        diagnostics.append(f"attempt={attempt} listener_{stream_name}:\n{rendered}")


def capture(
    project_dir: Path,
    output: Path,
    stderr_output: Path,
    wanted: int,
    deadline_seconds: float,
    interval_seconds: float,
    *,
    runner: ListenerRunner = _run_listener,
    monotonic: Clock = time.monotonic,
    sleeper: Sleeper = time.sleep,
) -> dict[str, object]:
    if (
        wanted < 2
        or not math.isfinite(deadline_seconds)
        or deadline_seconds <= 0
        or not math.isfinite(interval_seconds)
        or interval_seconds < 0
    ):
        raise SnapshotError("invalid capture bounds")

    validator = SequenceValidator()
    diagnostics: list[str] = []
    deadline = monotonic() + deadline_seconds
    attempts = 0

    try:
        while len(validator.accepted) < wanted:
            remaining = deadline - monotonic()
            if remaining <= 0:
                raise SnapshotError(
                    f"deadline expired with {len(validator.accepted)}/{wanted} "
                    "distinct samples"
                )
            attempts += 1
            try:
                result = runner(
                    _listener_command(project_dir), project_dir, min(8.5, remaining)
                )
            except subprocess.TimeoutExpired as error:
                _record_stream(diagnostics, attempts, "stdout", error.output)
                _record_stream(diagnostics, attempts, "stderr", error.stderr)
                raise SnapshotError("one-message PX4 listener timed out") from error
            _record_stream(diagnostics, attempts, "stderr", result.stderr)
            if monotonic() >= deadline:
                _record_stream(diagnostics, attempts, "stdout", result.stdout)
                raise SnapshotError("deadline expired after PX4 listener returned")
            if result.returncode != 0:
                _record_stream(diagnostics, attempts, "stdout", result.stdout)
                raise SnapshotError(
                    f"one-message PX4 listener exited {result.returncode}"
                )

            try:
                sample = parse_snapshot(_text(result.stdout))
            except SnapshotError:
                _record_stream(diagnostics, attempts, "stdout", result.stdout)
                raise
            if monotonic() >= deadline:
                _record_stream(diagnostics, attempts, "stdout", result.stdout)
                raise SnapshotError("deadline expired before accepting PX4 sample")
            try:
                disposition = validator.observe(sample)
            except SnapshotError:
                _record_stream(diagnostics, attempts, "stdout", result.stdout)
                raise
            if disposition == "duplicate":
                diagnostics.append(
                    "attempt="
                    f"{attempts} duplicate timestamp={sample.timestamp}"
                )
            if len(validator.accepted) < wanted:
                sleeper(min(interval_seconds, max(0.0, deadline - monotonic())))
    except Exception as error:
        diagnostics.append(f"FAIL: {error}")
        raise
    finally:
        rendered = "".join(
            f"SNAPSHOT: {index}/{wanted}\n{sample.raw}\n"
            for index, sample in enumerate(validator.accepted, start=1)
        )
        _write_private(output, rendered)
        _write_private(
            stderr_output,
            "\n".join(diagnostics) + ("\n" if diagnostics else ""),
        )

    first = validator.accepted[0]
    last = validator.accepted[-1]
    return {
        "result": "PASS",
        "topic": TOPIC,
        "estimator_instance": 0,
        "unique_samples": len(validator.accepted),
        "duplicate_retries": validator.duplicates,
        "attempts": attempts,
        "first_timestamp": first.timestamp,
        "last_timestamp": last.timestamp,
        "first_timestamp_sample": first.timestamp_sample,
        "last_timestamp_sample": last.timestamp_sample,
        "first_time_last_fuse": first.time_last_fuse,
        "last_time_last_fuse": last.time_last_fuse,
    }


def _fixture(
    timestamp: str = "1001000",
    timestamp_sample: str = "1000000",
    time_last_fuse: str = "999000",
    instance: str = "0",
    fused: str = "True",
    rejected: str = "False",
) -> str:
    return f"""
TOPIC: {TOPIC}
 {TOPIC}
    timestamp: {timestamp} (1000 us ago)
    timestamp_sample: {timestamp_sample}
    time_last_fuse: {time_last_fuse}
    observation: [0.0, 0.0]
    estimator_instance: {instance}
    innovation_rejected: {rejected}
    fused: {fused}
"""


def self_test() -> dict[str, object]:
    checks = 0

    def passed(condition: bool, message: str) -> None:
        nonlocal checks
        if not condition:
            raise AssertionError(message)
        checks += 1

    def expect_error(function: Callable[[], object]) -> None:
        nonlocal checks
        try:
            function()
        except SnapshotError:
            checks += 1
            return
        raise AssertionError("negative fixture unexpectedly passed")

    def indexed_fixture(index: int) -> str:
        return _fixture(
            timestamp=str(1_001_000 + index * 20_000),
            timestamp_sample=str(1_000_000 + index * 20_000),
            time_last_fuse=str(999_000 + index * 20_000),
        )

    sequence = SequenceValidator()
    for index in range(10):
        sample = parse_snapshot(indexed_fixture(index))
        assert sequence.observe(sample) == "accepted"
    passed(len(sequence.accepted) == 10, "ten advancing snapshots were not accepted")

    duplicate_sequence = SequenceValidator()
    duplicate = parse_snapshot(_fixture())
    for _ in range(10):
        duplicate_sequence.observe(duplicate)
    passed(
        len(duplicate_sequence.accepted) == 1
        and duplicate_sequence.duplicates == 9,
        "exact duplicates were not retried without acceptance",
    )

    insufficient = SequenceValidator()
    for index in (0, 1, 1, 2, 2):
        insufficient.observe(parse_snapshot(indexed_fixture(index)))
    passed(len(insufficient.accepted) == 3, "duplicates inflated unique count")

    def sequence_error(first: str, second: str) -> None:
        validator = SequenceValidator()
        validator.observe(parse_snapshot(first))
        validator.observe(parse_snapshot(second))

    expect_error(
        lambda: sequence_error(
            indexed_fixture(1),
            _fixture(
                timestamp="1000000",
                timestamp_sample="1040000",
                time_last_fuse="1039000",
            ),
        )
    )
    expect_error(
        lambda: sequence_error(
            indexed_fixture(1),
            _fixture(
                timestamp="1041000",
                timestamp_sample="1000000",
                time_last_fuse="1039000",
            ),
        )
    )
    expect_error(
        lambda: sequence_error(
            indexed_fixture(0),
            _fixture(
                timestamp="1021000",
                timestamp_sample="1000000",
                time_last_fuse="1019000",
            ),
        )
    )
    expect_error(
        lambda: sequence_error(
            indexed_fixture(0),
            _fixture(
                timestamp="1021000",
                timestamp_sample="1020000",
                time_last_fuse="999000",
            ),
        )
    )
    expect_error(
        lambda: sequence_error(
            indexed_fixture(1),
            _fixture(
                timestamp="1041000",
                timestamp_sample="1040000",
                time_last_fuse="998000",
            ),
        )
    )
    expect_error(
        lambda: sequence_error(
            indexed_fixture(0),
            _fixture(
                timestamp="1001000",
                timestamp_sample="1020000",
                time_last_fuse="1019000",
            ),
        )
    )
    expect_error(
        lambda: sequence_error(
            indexed_fixture(0),
            _fixture(
                timestamp="1001000",
                timestamp_sample="1000000",
                time_last_fuse="1000000",
            ),
        )
    )

    expect_error(lambda: parse_snapshot(_fixture(fused="False")))
    expect_error(lambda: parse_snapshot(_fixture(rejected="True")))
    expect_error(lambda: parse_snapshot(_fixture(instance="1")))
    expect_error(lambda: parse_snapshot(_fixture(timestamp="0")))
    expect_error(lambda: parse_snapshot(_fixture(timestamp="abc")))
    expect_error(lambda: parse_snapshot(_fixture(timestamp_sample="0")))
    expect_error(lambda: parse_snapshot(_fixture(timestamp_sample="abc")))
    expect_error(lambda: parse_snapshot(_fixture(time_last_fuse="-1")))
    expect_error(lambda: parse_snapshot(_fixture() + "    fused: True\n"))
    expect_error(lambda: parse_snapshot(_fixture().replace("    fused: True\n", "")))
    expect_error(lambda: parse_snapshot(_fixture() + "    timestamp: 1002000\n"))
    expect_error(
        lambda: parse_snapshot(
            _fixture().replace("    timestamp: 1001000 (1000 us ago)\n", "")
        )
    )
    expect_error(lambda: parse_snapshot(_fixture() + "    innovation: [nan, 0.0]\n"))
    expect_error(lambda: parse_snapshot(_fixture() + "    variance: [inf, 1.0]\n"))
    expect_error(
        lambda: parse_snapshot(
            _fixture().replace(
                f"TOPIC: {TOPIC}", f"TOPIC: {TOPIC} instance 0 #1"
            )
        )
    )

    listener_command = _listener_command(Path("/project"))
    listener_shell = listener_command[-1]
    passed(
        listener_command[:3] == [
            "/project/scripts/proot-run.sh",
            "bash",
            "-lc",
        ]
        and "px4-listener --instance 0" in listener_shell
        and f"{TOPIC} -n 1" in listener_shell
        and " -i " not in listener_shell
        and " -r " not in listener_shell,
        "listener command did not select the one-message latest-copy branch",
    )

    class FakeClock:
        def __init__(self) -> None:
            self.now = 0.0

        def __call__(self) -> float:
            return self.now

        def sleep(self, seconds: float) -> None:
            self.now += seconds

    def make_runner(
        clock: FakeClock,
        payloads: list[str],
        *,
        advance: float,
        repeat_last: bool = False,
        returncode: int = 0,
        stderr: str = "",
    ) -> tuple[ListenerRunner, list[float]]:
        index = 0
        observed_timeouts: list[float] = []

        def fake_runner(command: list[str], cwd: Path, timeout: float) -> ListenerResult:
            nonlocal index
            del cwd
            observed_timeouts.append(timeout)
            clock.now += advance
            if index < len(payloads):
                payload = payloads[index]
                index += 1
            elif repeat_last and payloads:
                payload = payloads[-1]
            else:
                raise AssertionError("fake listener exhausted")
            return subprocess.CompletedProcess(command, returncode, payload, stderr)

        return fake_runner, observed_timeouts

    with tempfile.TemporaryDirectory(prefix="px4-live-fusion-selftest-") as temp:
        temp_dir = Path(temp)
        project_dir = temp_dir / "project"
        project_dir.mkdir()

        success_clock = FakeClock()
        success_payloads = [indexed_fixture(0), indexed_fixture(0)] + [
            indexed_fixture(index) for index in range(1, 10)
        ]
        success_runner, success_timeouts = make_runner(
            success_clock, success_payloads, advance=0.01
        )
        success_out = temp_dir / "success.txt"
        success_err = temp_dir / "success.stderr"
        summary = capture(
            project_dir,
            success_out,
            success_err,
            10,
            5.0,
            0.01,
            runner=success_runner,
            monotonic=success_clock,
            sleeper=success_clock.sleep,
        )
        passed(
            summary["unique_samples"] == 10
            and summary["duplicate_retries"] == 1
            and success_out.read_text(encoding="utf-8").count("SNAPSHOT:") == 10
            and "duplicate timestamp=" in success_err.read_text(encoding="utf-8")
            and max(success_timeouts) <= 5.0
            and (success_out.stat().st_mode & 0o777) == 0o600,
            "capture success path did not preserve the frozen contract",
        )

        duplicate_clock = FakeClock()
        duplicate_runner, _ = make_runner(
            duplicate_clock, [indexed_fixture(0)], advance=0.20, repeat_last=True
        )
        duplicate_out = temp_dir / "duplicate.txt"
        duplicate_err = temp_dir / "duplicate.stderr"
        duplicate_out.write_text("OLD OUTPUT", encoding="utf-8")
        duplicate_err.write_text("OLD STDERR", encoding="utf-8")
        expect_error(
            lambda: capture(
                project_dir,
                duplicate_out,
                duplicate_err,
                10,
                0.75,
                0.10,
                runner=duplicate_runner,
                monotonic=duplicate_clock,
                sleeper=duplicate_clock.sleep,
            )
        )
        passed(
            "OLD" not in duplicate_out.read_text(encoding="utf-8")
            and duplicate_out.read_text(encoding="utf-8").count("SNAPSHOT:") == 1
            and "FAIL: deadline expired" in duplicate_err.read_text(encoding="utf-8"),
            "duplicate deadline failure did not replace stale evidence",
        )

        insufficient_clock = FakeClock()
        insufficient_runner, _ = make_runner(
            insufficient_clock,
            [indexed_fixture(index) for index in range(3)],
            advance=0.15,
            repeat_last=True,
        )
        insufficient_out = temp_dir / "insufficient.txt"
        insufficient_err = temp_dir / "insufficient.stderr"
        expect_error(
            lambda: capture(
                project_dir,
                insufficient_out,
                insufficient_err,
                10,
                1.0,
                0.05,
                runner=insufficient_runner,
                monotonic=insufficient_clock,
                sleeper=insufficient_clock.sleep,
            )
        )
        passed(
            insufficient_out.read_text(encoding="utf-8").count("SNAPSHOT:") == 3
            and "3/10 distinct samples" in insufficient_err.read_text(encoding="utf-8"),
            "insufficient unique capture did not fail with partial evidence",
        )

        timeout_clock = FakeClock()

        def timeout_runner(
            command: list[str], cwd: Path, timeout: float
        ) -> ListenerResult:
            del cwd
            raise subprocess.TimeoutExpired(
                command,
                timeout,
                output=b"PARTIAL_STDOUT",
                stderr=b"PARTIAL_STDERR",
            )

        timeout_out = temp_dir / "timeout.txt"
        timeout_err = temp_dir / "timeout.stderr"
        timeout_out.write_text("OLD OUTPUT", encoding="utf-8")
        timeout_err.write_text("OLD STDERR", encoding="utf-8")
        expect_error(
            lambda: capture(
                project_dir,
                timeout_out,
                timeout_err,
                10,
                1.0,
                0.0,
                runner=timeout_runner,
                monotonic=timeout_clock,
                sleeper=timeout_clock.sleep,
            )
        )
        timeout_diagnostics = timeout_err.read_text(encoding="utf-8")
        passed(
            timeout_out.read_text(encoding="utf-8") == ""
            and "OLD" not in timeout_diagnostics
            and "PARTIAL_STDOUT" in timeout_diagnostics
            and "PARTIAL_STDERR" in timeout_diagnostics,
            "timeout did not truncate stale evidence and preserve partial streams",
        )

        nonzero_clock = FakeClock()
        nonzero_runner, _ = make_runner(
            nonzero_clock,
            ["NONZERO_STDOUT"],
            advance=0.01,
            returncode=7,
            stderr="NONZERO_STDERR",
        )
        nonzero_out = temp_dir / "nonzero.txt"
        nonzero_err = temp_dir / "nonzero.stderr"
        expect_error(
            lambda: capture(
                project_dir,
                nonzero_out,
                nonzero_err,
                10,
                1.0,
                0.0,
                runner=nonzero_runner,
                monotonic=nonzero_clock,
                sleeper=nonzero_clock.sleep,
            )
        )
        nonzero_diagnostics = nonzero_err.read_text(encoding="utf-8")
        passed(
            "NONZERO_STDOUT" in nonzero_diagnostics
            and "NONZERO_STDERR" in nonzero_diagnostics,
            "nonzero listener exit did not preserve both streams",
        )

        malformed_clock = FakeClock()
        malformed_runner, _ = make_runner(
            malformed_clock, ["MALFORMED_STDOUT"], advance=0.01
        )
        malformed_out = temp_dir / "malformed.txt"
        malformed_err = temp_dir / "malformed.stderr"
        expect_error(
            lambda: capture(
                project_dir,
                malformed_out,
                malformed_err,
                10,
                1.0,
                0.0,
                runner=malformed_runner,
                monotonic=malformed_clock,
                sleeper=malformed_clock.sleep,
            )
        )
        passed(
            malformed_out.read_text(encoding="utf-8") == ""
            and "MALFORMED_STDOUT" in malformed_err.read_text(encoding="utf-8"),
            "malformed listener output was not retained diagnostically",
        )

        boundary_clock = FakeClock()
        boundary_runner, boundary_timeouts = make_runner(
            boundary_clock, [indexed_fixture(0)], advance=1.0
        )
        boundary_out = temp_dir / "boundary.txt"
        boundary_err = temp_dir / "boundary.stderr"
        expect_error(
            lambda: capture(
                project_dir,
                boundary_out,
                boundary_err,
                10,
                1.0,
                0.0,
                runner=boundary_runner,
                monotonic=boundary_clock,
                sleeper=boundary_clock.sleep,
            )
        )
        passed(
            boundary_timeouts == [1.0]
            and boundary_out.read_text(encoding="utf-8") == ""
            and "deadline expired after" in boundary_err.read_text(encoding="utf-8"),
            "deadline boundary accepted a late listener result",
        )

        backward_clock = FakeClock()
        backward_payload = _fixture(
            timestamp="1000000",
            timestamp_sample="1040000",
            time_last_fuse="1039000",
        )
        backward_runner, _ = make_runner(
            backward_clock,
            [indexed_fixture(1), backward_payload],
            advance=0.01,
        )
        backward_out = temp_dir / "backward.txt"
        backward_err = temp_dir / "backward.stderr"
        backward_out.write_text("OLD OUTPUT", encoding="utf-8")
        backward_err.write_text("OLD STDERR", encoding="utf-8")
        expect_error(
            lambda: capture(
                project_dir,
                backward_out,
                backward_err,
                10,
                1.0,
                0.0,
                runner=backward_runner,
                monotonic=backward_clock,
                sleeper=backward_clock.sleep,
            )
        )
        backward_diagnostics = backward_err.read_text(encoding="utf-8")
        passed(
            "OLD" not in backward_out.read_text(encoding="utf-8")
            and backward_out.read_text(encoding="utf-8").count("SNAPSHOT:") == 1
            and "timestamp: 1000000" in backward_diagnostics
            and "FAIL: producer timestamp moved backwards" in backward_diagnostics,
            "backward producer sample was rejected without raw evidence",
        )

        inconsistent_clock = FakeClock()
        inconsistent_payload = _fixture(
            timestamp="1001000",
            timestamp_sample="1020000",
            time_last_fuse="1019000",
        )
        inconsistent_runner, _ = make_runner(
            inconsistent_clock,
            [indexed_fixture(0), inconsistent_payload],
            advance=0.01,
        )
        inconsistent_out = temp_dir / "inconsistent.txt"
        inconsistent_err = temp_dir / "inconsistent.stderr"
        expect_error(
            lambda: capture(
                project_dir,
                inconsistent_out,
                inconsistent_err,
                10,
                1.0,
                0.0,
                runner=inconsistent_runner,
                monotonic=inconsistent_clock,
                sleeper=inconsistent_clock.sleep,
            )
        )
        inconsistent_diagnostics = inconsistent_err.read_text(encoding="utf-8")
        passed(
            inconsistent_out.read_text(encoding="utf-8").count("SNAPSHOT:") == 1
            and "timestamp_sample: 1020000" in inconsistent_diagnostics
            and "FAIL: duplicate producer timestamp changed" in inconsistent_diagnostics,
            "same producer timestamp changed payload without raw evidence",
        )

    expect_error(
        lambda: capture(Path("."), Path("out"), Path("err"), 10, math.inf, 0.0)
    )
    expect_error(
        lambda: capture(Path("."), Path("out"), Path("err"), 10, 1.0, math.nan)
    )

    return {"self_test": "PASS", "checks": checks, "policy": "unique-live-ev-v3"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-dir", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--stderr-output", type=Path)
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--deadline", type=float, default=30.0)
    parser.add_argument("--interval", type=float, default=0.2)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return args
    if args.project_dir is None or args.output is None or args.stderr_output is None:
        parser.error("--project-dir, --output and --stderr-output are required")
    if (
        args.samples < 2
        or not math.isfinite(args.deadline)
        or args.deadline <= 0
        or not math.isfinite(args.interval)
        or args.interval < 0
    ):
        parser.error("invalid sampling bounds")
    return args


def main() -> int:
    args = parse_args()
    if args.self_test:
        print(json.dumps(self_test(), sort_keys=True))
        return 0
    try:
        result = capture(
            args.project_dir.resolve(strict=True),
            args.output,
            args.stderr_output,
            args.samples,
            args.deadline,
            args.interval,
        )
    except (OSError, SnapshotError, subprocess.SubprocessError) as error:
        print(f"live fusion capture failed: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
