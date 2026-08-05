#!/usr/bin/env python3
"""Measure finite odometry data and unique header-stamp cadence."""

import argparse
import json
import math
import statistics
import time

import rclpy
from nav_msgs.msg import Odometry
from rclpy.node import Node


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    index = min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1)
    return ordered[max(0, index)]


class OdomProbe(Node):
    def __init__(self, topic: str) -> None:
        super().__init__("odom_stream_probe")
        self.messages = 0
        self.nonfinite_messages = 0
        self.stamps_ns: list[int] = []
        self.receive_times: list[float] = []
        self.positions: list[tuple[float, float, float]] = []
        self.parent_frames: set[str] = set()
        self.child_frames: set[str] = set()
        self.create_subscription(Odometry, topic, self.callback, 50)

    def callback(self, message: Odometry) -> None:
        self.messages += 1
        self.receive_times.append(time.monotonic())
        self.stamps_ns.append(
            message.header.stamp.sec * 1_000_000_000
            + message.header.stamp.nanosec
        )
        self.parent_frames.add(message.header.frame_id)
        self.child_frames.add(message.child_frame_id)

        pose = message.pose.pose
        twist = message.twist.twist
        self.positions.append(
            (pose.position.x, pose.position.y, pose.position.z)
        )
        values = (
            pose.position.x,
            pose.position.y,
            pose.position.z,
            pose.orientation.x,
            pose.orientation.y,
            pose.orientation.z,
            pose.orientation.w,
            twist.linear.x,
            twist.linear.y,
            twist.linear.z,
            twist.angular.x,
            twist.angular.y,
            twist.angular.z,
            *message.pose.covariance,
            *message.twist.covariance,
        )
        if not all(math.isfinite(value) for value in values):
            self.nonfinite_messages += 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic")
    parser.add_argument("--duration", type=float, default=7.0)
    parser.add_argument("--min-unique-rate", type=float, default=30.0)
    parser.add_argument("--max-gap", type=float, default=0.10)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        assert percentile([], 0.99) == 0.0
        assert percentile([1.0, 2.0, 3.0], 0.5) == 2.0
        print(json.dumps({"self_test": "PASS"}, sort_keys=True))
        return 0
    if not args.topic:
        parser.error("--topic is required unless --self-test is used")
    if args.duration <= 0 or args.min_unique_rate <= 0 or args.max_gap <= 0:
        parser.error("duration, min-unique-rate and max-gap must be positive")

    rclpy.init()
    node = OdomProbe(args.topic)
    deadline = time.monotonic() + args.duration
    try:
        while rclpy.ok() and time.monotonic() < deadline:
            rclpy.spin_once(node, timeout_sec=0.1)
    finally:
        node.destroy_node()
        rclpy.shutdown()

    unique_stamps = sorted({stamp for stamp in node.stamps_ns if stamp > 0})
    stamp_gaps = [
        (later - earlier) / 1_000_000_000
        for earlier, later in zip(unique_stamps, unique_stamps[1:])
    ]
    receive_gaps = [
        later - earlier
        for earlier, later in zip(node.receive_times, node.receive_times[1:])
    ]
    unique_rate = 0.0
    if len(unique_stamps) >= 2 and unique_stamps[-1] > unique_stamps[0]:
        unique_rate = (len(unique_stamps) - 1) / (
            (unique_stamps[-1] - unique_stamps[0]) / 1_000_000_000
        )
    receive_rate = 0.0
    if receive_gaps:
        receive_rate = 1.0 / statistics.median(receive_gaps)

    endpoint_displacement = 0.0
    max_displacement = 0.0
    axis_span = [0.0, 0.0, 0.0]
    if node.positions:
        first_position = node.positions[0]
        endpoint_displacement = math.dist(first_position, node.positions[-1])
        max_displacement = max(
            math.dist(first_position, position) for position in node.positions
        )
        axis_span = [
            max(position[index] for position in node.positions)
            - min(position[index] for position in node.positions)
            for index in range(3)
        ]

    result = {
        "topic": args.topic,
        "messages": node.messages,
        "unique_header_stamps": len(unique_stamps),
        "duplicate_fraction": (
            1.0 - len(unique_stamps) / node.messages if node.messages else 1.0
        ),
        "unique_stamp_rate_hz": unique_rate,
        "receive_rate_hz": receive_rate,
        "endpoint_displacement_m": endpoint_displacement,
        "max_displacement_from_first_m": max_displacement,
        "axis_span_m": axis_span,
        "stamp_gap_median_s": statistics.median(stamp_gaps) if stamp_gaps else 0.0,
        "stamp_gap_p99_s": percentile(stamp_gaps, 0.99),
        "stamp_gap_max_s": max(stamp_gaps, default=0.0),
        "nonfinite_messages": node.nonfinite_messages,
        "parent_frames": sorted(node.parent_frames),
        "child_frames": sorted(node.child_frames),
    }
    print(json.dumps(result, sort_keys=True))

    valid = (
        node.messages >= 2
        and len(unique_stamps) >= 2
        and node.nonfinite_messages == 0
        and node.parent_frames == {"odom"}
        and node.child_frames == {"base_link"}
        and unique_rate >= args.min_unique_rate
        and max(stamp_gaps, default=float("inf")) <= args.max_gap
    )
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
