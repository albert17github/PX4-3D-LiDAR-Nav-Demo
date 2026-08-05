#!/usr/bin/env python3
"""Require fresh, jointly stable MAVROS connected/disarmed/landed samples."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import time

import rclpy
from mavros_msgs.msg import ExtendedState, State
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data


class Samples:
    def __init__(self) -> None:
        self.connected: bool | None = None
        self.armed: bool | None = None
        self.landed_state: int | None = None
        self.state_at: float | None = None
        self.extended_at: float | None = None
        self.state_count = 0
        self.extended_count = 0
        self.stable_since: float | None = None
        self.stable_counts = (0, 0)

    def update_state(self, connected: bool, armed: bool, now: float) -> None:
        self.connected, self.armed, self.state_at = connected, armed, now
        self.state_count += 1

    def update_extended(self, landed_state: int, now: float) -> None:
        self.landed_state, self.extended_at = landed_state, now
        self.extended_count += 1

    def ready(self, now: float) -> bool:
        fresh = (
            self.state_at is not None
            and self.extended_at is not None
            and now - self.state_at <= 2.0
            and now - self.extended_at <= 2.0
        )
        safe = (
            self.connected is True
            and self.armed is False
            and self.landed_state == ExtendedState.LANDED_STATE_ON_GROUND
        )
        if not (fresh and safe):
            self.stable_since = None
            return False
        if self.stable_since is None:
            self.stable_since = now
            self.stable_counts = (self.state_count, self.extended_count)
            return False
        return (
            now - self.stable_since >= 0.75
            and self.state_count > self.stable_counts[0]
            and self.extended_count > self.stable_counts[1]
        )

    def result(self, passed: bool) -> dict[str, object]:
        return {
            "result": "PASS" if passed else "FAIL",
            "connected": self.connected,
            "armed": self.armed,
            "landed_state": self.landed_state,
            "state_samples": self.state_count,
            "extended_state_samples": self.extended_count,
        }


class Probe(Node):
    def __init__(self, samples: Samples) -> None:
        super().__init__("demo_ground_state_probe")
        self.samples = samples
        self.create_subscription(
            State, "/mavros/state", self.on_state, qos_profile_sensor_data
        )
        self.create_subscription(
            ExtendedState,
            "/mavros/extended_state",
            self.on_extended,
            qos_profile_sensor_data,
        )

    def on_state(self, message: State) -> None:
        self.samples.update_state(message.connected, message.armed, time.monotonic())

    def on_extended(self, message: ExtendedState) -> None:
        self.samples.update_extended(message.landed_state, time.monotonic())


def self_test() -> None:
    samples = Samples()
    samples.update_state(True, False, 1.0)
    samples.update_extended(ExtendedState.LANDED_STATE_ON_GROUND, 1.0)
    assert not samples.ready(1.0)
    samples.update_state(True, False, 1.4)
    samples.update_extended(ExtendedState.LANDED_STATE_ON_GROUND, 1.4)
    assert samples.ready(1.8)
    samples.update_state(True, True, 2.0)
    assert not samples.ready(2.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--deadline", type=float, default=7.0)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print('{"self_test":"PASS"}')
        return 0
    if args.output is None or args.deadline <= 0:
        parser.error("--output and a positive --deadline are required")

    rclpy.init()
    samples = Samples()
    node = Probe(samples)
    deadline = time.monotonic() + args.deadline
    passed = False
    try:
        while rclpy.ok() and time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.1)
            if samples.ready(time.monotonic()):
                passed = True
                break
    finally:
        node.destroy_node()
        rclpy.shutdown()
    result = samples.result(passed)
    args.output.write_text(json.dumps(result, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
