#!/usr/bin/env python3
"""Thin fixed or RViz-selected planner client and MAVROS setpoint executor.

All estimation, mapping and search are upstream components.  This file only
connects the planner response to a rate-limited PX4 OFFBOARD position stream.
"""

from __future__ import annotations

import argparse
import json
import math
import signal
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

import rclpy
import yaml
from geometry_msgs.msg import Point, PoseStamped
from mavros_msgs.msg import ExtendedState, State
from mavros_msgs.srv import CommandBool, CommandTOL, SetMode
from mrs_modules_msgs.srv import Path as PlannerPath
from nav_msgs.msg import Odometry, Path as NavPath
from rclpy.node import Node
from rclpy.parameter import Parameter
from rclpy.qos import (
    DurabilityPolicy,
    HistoryPolicy,
    QoSProfile,
    ReliabilityPolicy,
    qos_profile_sensor_data,
)
from visualization_msgs.msg import Marker, MarkerArray


STATE_TOPIC = "/mavros/state"
EXTENDED_STATE_TOPIC = "/mavros/extended_state"
ODOM_TOPIC = "/mavros/local_position/odom"
SETPOINT_TOPIC = "/mavros/setpoint_position/local"
# MAVROS publishes State/ExtendedState at roughly 0.55-1 Hz under the full
# mapping load.  Allow one missed or delayed heartbeat without weakening the
# independent 0.5 s odometry watchdog that guards flight-control feedback.
SLOW_TELEMETRY_TIMEOUT_S = 5.0
ODOMETRY_TIMEOUT_S = 0.5


class MissionError(RuntimeError):
    pass


@dataclass(frozen=True)
class XYZ:
    x: float
    y: float
    z: float

    def distance(self, other: "XYZ") -> float:
        return math.dist((self.x, self.y, self.z), (other.x, other.y, other.z))

    def as_list(self) -> list[float]:
        return [self.x, self.y, self.z]


@dataclass(frozen=True)
class DemoConfig:
    frame_id: str
    start: XYZ
    goal: XYZ
    obstacle_xy: tuple[float, float]
    obstacle_radius_m: float
    minimum_clearance_m: float
    minimum_cross_track_m: float
    takeoff_height_m: float
    cruise_speed_mps: float
    setpoint_rate_hz: float
    waypoint_tolerance_m: float
    goal_hold_s: float
    map_warmup_s: float
    planner_attempts: int
    planner_retry_interval_s: float
    mission_timeout_s: float
    planner_service: str
    interactive_goal_topic: str
    interactive_goal_min_distance_m: float
    interactive_goal_max_distance_m: float
    interactive_goal_timeout_s: float


def finite_xyz(values: Any, name: str) -> XYZ:
    if not isinstance(values, list) or len(values) != 3:
        raise MissionError(f"{name} must contain three numbers")
    parsed = tuple(float(value) for value in values)
    if not all(math.isfinite(value) for value in parsed):
        raise MissionError(f"{name} contains a non-finite value")
    return XYZ(*parsed)


def load_config(path: Path) -> DemoConfig:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise MissionError("demo config is not a mapping")
    obstacle = raw.get("expected_obstacle_center_xy")
    if not isinstance(obstacle, list) or len(obstacle) != 2:
        raise MissionError("expected_obstacle_center_xy must contain two numbers")
    obstacle_xy = (float(obstacle[0]), float(obstacle[1]))
    numeric = {
        key: float(raw[key])
        for key in (
            "expected_obstacle_radius_m",
            "minimum_demo_clearance_m",
            "minimum_cross_track_m",
            "takeoff_height_m",
            "cruise_speed_mps",
            "setpoint_rate_hz",
            "waypoint_tolerance_m",
            "goal_hold_s",
            "map_warmup_s",
            "planner_retry_interval_s",
            "mission_timeout_s",
            "interactive_goal_min_distance_m",
            "interactive_goal_max_distance_m",
            "interactive_goal_timeout_s",
        )
    }
    if not all(math.isfinite(value) and value > 0.0 for value in numeric.values()):
        raise MissionError("all numeric demo limits must be finite and positive")
    planner_attempts = raw.get("planner_attempts")
    if (
        isinstance(planner_attempts, bool)
        or not isinstance(planner_attempts, int)
        or planner_attempts < 1
    ):
        raise MissionError("planner_attempts must be a positive integer")
    frame_id = str(raw.get("frame_id", ""))
    service = str(raw.get("planner_service", ""))
    goal_topic = str(raw.get("interactive_goal_topic", ""))
    if frame_id != "map" or not service.startswith("/") or not goal_topic.startswith("/"):
        raise MissionError(
            "demo requires frame_id=map plus absolute planner and interactive topics"
        )
    if (
        numeric["interactive_goal_min_distance_m"]
        >= numeric["interactive_goal_max_distance_m"]
    ):
        raise MissionError("interactive goal minimum distance must be below maximum")
    start = finite_xyz(raw.get("start"), "start")
    goal = finite_xyz(raw.get("goal"), "goal")
    if abs(start.z - numeric["takeoff_height_m"]) > 1e-6:
        raise MissionError("start height must equal takeoff_height_m")
    return DemoConfig(
        frame_id=frame_id,
        start=start,
        goal=goal,
        obstacle_xy=obstacle_xy,
        obstacle_radius_m=numeric["expected_obstacle_radius_m"],
        minimum_clearance_m=numeric["minimum_demo_clearance_m"],
        minimum_cross_track_m=numeric["minimum_cross_track_m"],
        takeoff_height_m=numeric["takeoff_height_m"],
        cruise_speed_mps=numeric["cruise_speed_mps"],
        setpoint_rate_hz=numeric["setpoint_rate_hz"],
        waypoint_tolerance_m=numeric["waypoint_tolerance_m"],
        goal_hold_s=numeric["goal_hold_s"],
        map_warmup_s=numeric["map_warmup_s"],
        planner_attempts=planner_attempts,
        planner_retry_interval_s=numeric["planner_retry_interval_s"],
        mission_timeout_s=numeric["mission_timeout_s"],
        planner_service=service,
        interactive_goal_topic=goal_topic,
        interactive_goal_min_distance_m=numeric["interactive_goal_min_distance_m"],
        interactive_goal_max_distance_m=numeric["interactive_goal_max_distance_m"],
        interactive_goal_timeout_s=numeric["interactive_goal_timeout_s"],
    )


def segment_point_distance_xy(a: XYZ, b: XYZ, point: tuple[float, float]) -> float:
    dx = b.x - a.x
    dy = b.y - a.y
    denominator = dx * dx + dy * dy
    if denominator <= 1e-12:
        return math.hypot(point[0] - a.x, point[1] - a.y)
    t = ((point[0] - a.x) * dx + (point[1] - a.y) * dy) / denominator
    t = min(1.0, max(0.0, t))
    return math.hypot(point[0] - (a.x + t * dx), point[1] - (a.y + t * dy))


def path_length(points: list[XYZ]) -> float:
    return sum(a.distance(b) for a, b in zip(points, points[1:]))


def cross_track_xy(point: XYZ, start: XYZ, goal: XYZ) -> float:
    return segment_point_distance_xy(start, goal, (point.x, point.y))


def normalize_angle(angle: float) -> float:
    return math.atan2(math.sin(angle), math.cos(angle))


def quaternion_yaw(x: float, y: float, z: float, w: float) -> float:
    values = (float(x), float(y), float(z), float(w))
    if not all(math.isfinite(value) for value in values):
        raise MissionError("goal orientation contains a non-finite value")
    norm = math.sqrt(sum(value * value for value in values))
    if norm < 1e-6:
        raise MissionError("goal orientation quaternion has zero length")
    qx, qy, qz, qw = (value / norm for value in values)
    return normalize_angle(
        math.atan2(
            2.0 * (qw * qz + qx * qy),
            1.0 - 2.0 * (qy * qy + qz * qz),
        )
    )


def validate_path(
    config: DemoConfig,
    raw_points: list[XYZ],
    *,
    start: XYZ | None = None,
    goal: XYZ | None = None,
    require_visible_detour: bool = True,
) -> dict[str, float]:
    start = start or config.start
    goal = goal or config.goal
    if len(raw_points) < 2:
        raise MissionError("planner returned fewer than two points")
    if raw_points[-1].distance(goal) > 0.45:
        raise MissionError("planner path does not end at the requested goal")
    points = list(raw_points)
    if points[0].distance(start) > 1e-6:
        points.insert(0, start)
    if any(not 1.45 <= point.z <= 3.05 for point in points):
        raise MissionError("planner path leaves the demo altitude envelope")
    length = path_length(points)
    direct = start.distance(goal)
    max_cross_track = max(cross_track_xy(point, start, goal) for point in points)
    obstacle_distance = min(
        segment_point_distance_xy(a, b, config.obstacle_xy)
        for a, b in zip(points, points[1:])
    )
    required = config.obstacle_radius_m + config.minimum_clearance_m
    if require_visible_detour:
        if length <= direct + 0.10:
            raise MissionError("planner returned an effectively straight path")
        if max_cross_track < config.minimum_cross_track_m:
            raise MissionError("planner path has no visible obstacle detour")
    if obstacle_distance < required:
        raise MissionError(
            f"path clearance {obstacle_distance:.3f}m is below required {required:.3f}m"
        )
    return {
        "path_length_m": length,
        "direct_distance_m": direct,
        "max_cross_track_m": max_cross_track,
        "minimum_obstacle_center_distance_m": obstacle_distance,
        "required_obstacle_center_distance_m": required,
    }


class ABMission(Node):
    def __init__(self, config: DemoConfig, *, interactive: bool = False) -> None:
        super().__init__(
            "ab_mission",
            parameter_overrides=[Parameter("use_sim_time", value=True)],
            automatically_declare_parameters_from_overrides=True,
        )
        self.config = config
        self.interactive = interactive
        self.state: State | None = None
        self.extended: ExtendedState | None = None
        self.position: XYZ | None = None
        self.vehicle_yaw: float | None = None
        self.last_state_s = 0.0
        self.last_extended_s = 0.0
        self.last_odom_s = 0.0
        self.last_odom_stamp_ns: int | None = None
        self.last_odom_advance_s = 0.0
        self.target: XYZ | None = None
        self.target_yaw = 0.0
        self.mission_yaw = 0.0
        self.publish_count = 0
        self.shutdown_requested = False
        self.events: list[dict[str, Any]] = []
        self.planned_points: list[XYZ] = []
        self.executed_samples: list[dict[str, float]] = []
        self.selected_goal: XYZ | None = None
        self.selected_goal_yaw: float | None = None
        self.active_start: XYZ | None = None

        self.create_subscription(State, STATE_TOPIC, self.on_state, 10)
        self.create_subscription(ExtendedState, EXTENDED_STATE_TOPIC, self.on_extended, 10)
        self.create_subscription(Odometry, ODOM_TOPIC, self.on_odom, qos_profile_sensor_data)
        self.setpoint_pub = self.create_publisher(
            PoseStamped, SETPOINT_TOPIC, qos_profile_sensor_data
        )
        latched = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )
        self.path_pub = self.create_publisher(NavPath, "/demo/planned_path", latched)
        self.marker_pub = self.create_publisher(MarkerArray, "/demo/mission_markers", latched)
        if self.interactive:
            self.create_subscription(
                PoseStamped,
                config.interactive_goal_topic,
                self.on_interactive_goal,
                5,
            )
        self.arm_client = self.create_client(CommandBool, "/mavros/cmd/arming")
        self.mode_client = self.create_client(SetMode, "/mavros/set_mode")
        self.land_client = self.create_client(CommandTOL, "/mavros/cmd/land")
        self.planner_client = self.create_client(PlannerPath, config.planner_service)

    def event(self, name: str, **detail: Any) -> None:
        entry = {"event": name, "monotonic_s": round(time.monotonic(), 6), **detail}
        self.events.append(entry)
        self.get_logger().info(f"{name}: {detail}")

    def on_state(self, message: State) -> None:
        self.state = message
        self.last_state_s = time.monotonic()

    def on_extended(self, message: ExtendedState) -> None:
        self.extended = message
        self.last_extended_s = time.monotonic()

    def on_interactive_goal(self, message: PoseStamped) -> None:
        if self.selected_goal is not None:
            return
        if self.active_start is None:
            self.event("interactive_goal_rejected", reason="mission start is not ready")
            return
        if message.header.frame_id != self.config.frame_id:
            self.event(
                "interactive_goal_rejected",
                reason="goal frame must be map",
                frame_id=message.header.frame_id,
            )
            return
        x = float(message.pose.position.x)
        y = float(message.pose.position.y)
        if not all(math.isfinite(value) for value in (x, y)):
            self.event("interactive_goal_rejected", reason="goal XY is not finite")
            return
        goal = XYZ(x, y, self.config.takeoff_height_m)
        distance = math.hypot(
            goal.x - self.active_start.x,
            goal.y - self.active_start.y,
        )
        if not (
            self.config.interactive_goal_min_distance_m
            <= distance
            <= self.config.interactive_goal_max_distance_m
        ):
            self.event(
                "interactive_goal_rejected",
                reason="goal distance is outside the configured range",
                distance_m=distance,
                minimum_m=self.config.interactive_goal_min_distance_m,
                maximum_m=self.config.interactive_goal_max_distance_m,
            )
            return
        required = self.config.obstacle_radius_m + self.config.minimum_clearance_m
        obstacle_distance = math.hypot(
            goal.x - self.config.obstacle_xy[0],
            goal.y - self.config.obstacle_xy[1],
        )
        if obstacle_distance < required:
            self.event(
                "interactive_goal_rejected",
                reason="goal lies inside the obstacle clearance envelope",
                obstacle_center_distance_m=obstacle_distance,
                required_m=required,
            )
            return
        orientation = message.pose.orientation
        try:
            goal_yaw = quaternion_yaw(
                orientation.x,
                orientation.y,
                orientation.z,
                orientation.w,
            )
        except MissionError as error:
            self.event("interactive_goal_rejected", reason=str(error))
            return
        self.selected_goal = goal
        self.selected_goal_yaw = goal_yaw
        self.publish_markers(
            goal,
            start=self.active_start,
            goal_label="RViz goal",
        )
        self.event(
            "interactive_goal_selected",
            topic=self.config.interactive_goal_topic,
            goal=goal.as_list(),
            goal_yaw_rad=goal_yaw,
        )

    def on_odom(self, message: Odometry) -> None:
        if (
            message.header.frame_id != self.config.frame_id
            or message.child_frame_id != "base_link"
        ):
            return
        stamp = message.header.stamp
        stamp_ns = int(stamp.sec) * 1_000_000_000 + int(stamp.nanosec)
        if stamp_ns <= 0:
            return
        if self.last_odom_stamp_ns is not None and stamp_ns < self.last_odom_stamp_ns:
            return
        point = message.pose.pose.position
        values = (point.x, point.y, point.z)
        if all(math.isfinite(value) for value in values):
            now = time.monotonic()
            if self.last_odom_stamp_ns is None or stamp_ns > self.last_odom_stamp_ns:
                self.last_odom_advance_s = now
            self.last_odom_stamp_ns = stamp_ns
            self.position = XYZ(*map(float, values))
            orientation = message.pose.pose.orientation
            try:
                self.vehicle_yaw = quaternion_yaw(
                    orientation.x,
                    orientation.y,
                    orientation.z,
                    orientation.w,
                )
            except MissionError:
                pass
            self.last_odom_s = now
            if not self.executed_samples or now - self.executed_samples[-1]["t"] >= 0.1:
                sample = {
                    "t": now,
                    "x": point.x,
                    "y": point.y,
                    "z": point.z,
                    "target_yaw": self.target_yaw,
                }
                if self.vehicle_yaw is not None:
                    sample["yaw"] = self.vehicle_yaw
                self.executed_samples.append(sample)

    def spin_once(self, publish: bool = True) -> None:
        rclpy.spin_once(self, timeout_sec=0.01)
        if publish and self.target is not None:
            message = PoseStamped()
            message.header.stamp = self.get_clock().now().to_msg()
            message.header.frame_id = self.config.frame_id
            message.pose.position.x = self.target.x
            message.pose.position.y = self.target.y
            message.pose.position.z = self.target.z
            message.pose.orientation.z = math.sin(self.target_yaw / 2.0)
            message.pose.orientation.w = math.cos(self.target_yaw / 2.0)
            self.setpoint_pub.publish(message)
            self.publish_count += 1

    def run_for(self, duration_s: float, *, check_flight: bool = False) -> None:
        deadline = time.monotonic() + duration_s
        period = 1.0 / self.config.setpoint_rate_hz
        next_tick = time.monotonic()
        while time.monotonic() < deadline:
            if self.shutdown_requested:
                raise MissionError("shutdown requested")
            self.spin_once()
            if check_flight:
                self.flight_watchdog()
            next_tick += period
            time.sleep(max(0.0, next_tick - time.monotonic()))

    def wait_until(self, predicate: Callable[[], bool], timeout_s: float, name: str) -> None:
        deadline = time.monotonic() + timeout_s
        stable_since: float | None = None
        while time.monotonic() < deadline:
            self.spin_once()
            if predicate():
                stable_since = stable_since or time.monotonic()
                if time.monotonic() - stable_since >= 0.5:
                    return
            else:
                stable_since = None
            time.sleep(0.04)
        raise MissionError(f"timeout waiting for {name}")

    def wait_inputs(self) -> None:
        self.wait_until(
            lambda: bool(
                self.state
                and self.extended
                and self.position
                and self.state.connected
                and time.monotonic() - self.last_state_s < SLOW_TELEMETRY_TIMEOUT_S
                and time.monotonic() - self.last_extended_s
                < SLOW_TELEMETRY_TIMEOUT_S
                and time.monotonic() - self.last_odom_s < ODOMETRY_TIMEOUT_S
                and time.monotonic() - self.last_odom_advance_s
                < ODOMETRY_TIMEOUT_S
            ),
            25.0,
            "fresh MAVROS state and PX4 odometry",
        )

    def flight_watchdog(self) -> None:
        now = time.monotonic()
        state_age = now - self.last_state_s if self.last_state_s > 0.0 else math.inf
        odom_age = now - self.last_odom_s if self.last_odom_s > 0.0 else math.inf
        odom_advance_age = (
            now - self.last_odom_advance_s
            if self.last_odom_advance_s > 0.0
            else math.inf
        )
        healthy = bool(
            self.state
            and self.position
            and self.state.connected
            and self.state.armed
            and self.state.mode == "OFFBOARD"
            and state_age < SLOW_TELEMETRY_TIMEOUT_S
            and odom_age < ODOMETRY_TIMEOUT_S
            and odom_advance_age < ODOMETRY_TIMEOUT_S
        )
        if not healthy:
            detail = {
                "connected": bool(self.state and self.state.connected),
                "armed": bool(self.state and self.state.armed),
                "mode": self.state.mode if self.state else None,
                "has_position": self.position is not None,
                "state_age_s": round(state_age, 3),
                "odom_age_s": round(odom_age, 3),
                "odom_advance_age_s": round(odom_advance_age, 3),
            }
            raise MissionError(
                "PX4 OFFBOARD/state/odometry watchdog failed: "
                + json.dumps(detail, sort_keys=True)
            )

    def call(self, client: Any, request: Any, timeout_s: float, name: str) -> Any:
        deadline = time.monotonic() + timeout_s
        while not client.service_is_ready():
            if time.monotonic() >= deadline:
                raise MissionError(f"service unavailable: {name}")
            self.spin_once()
        future = client.call_async(request)
        while not future.done():
            if time.monotonic() >= deadline:
                raise MissionError(f"service timeout: {name}")
            self.spin_once()
        response = future.result()
        if response is None:
            raise MissionError(f"empty service response: {name}")
        return response

    def set_mode(self, mode: str, timeout_s: float = 8.0) -> None:
        request = SetMode.Request()
        request.base_mode = 0
        request.custom_mode = mode
        response = self.call(self.mode_client, request, timeout_s, f"set_mode {mode}")
        if not response.mode_sent:
            raise MissionError(f"PX4 rejected mode request {mode}")
        self.wait_until(lambda: bool(self.state and self.state.mode == mode), timeout_s, mode)
        self.event("mode_changed", mode=mode)

    def arm(self) -> None:
        request = CommandBool.Request()
        request.value = True
        response = self.call(self.arm_client, request, 8.0, "arming")
        if not response.success:
            raise MissionError(f"PX4 rejected arming, result={int(response.result)}")
        self.wait_until(lambda: bool(self.state and self.state.armed), 8.0, "armed")
        self.event("armed")

    def wait_for_interactive_goal(self) -> XYZ:
        self.event(
            "waiting_for_interactive_goal",
            topic=self.config.interactive_goal_topic,
            timeout_s=self.config.interactive_goal_timeout_s,
        )
        deadline = time.monotonic() + self.config.interactive_goal_timeout_s
        while self.selected_goal is None:
            if self.shutdown_requested:
                raise MissionError("shutdown requested while waiting for RViz goal")
            if time.monotonic() >= deadline:
                self.event(
                    "interactive_goal_wait_continues",
                    waited_s=self.config.interactive_goal_timeout_s,
                )
                deadline = time.monotonic() + self.config.interactive_goal_timeout_s
            self.spin_once(publish=False)
            time.sleep(0.04)
        return self.selected_goal

    def request_path(
        self,
        goal: XYZ | None = None,
        *,
        start: XYZ | None = None,
    ) -> tuple[list[XYZ], str]:
        start = start or self.config.start
        goal = goal or self.config.goal
        request = PlannerPath.Request()
        request.header.frame_id = self.config.frame_id
        request.header.stamp = self.get_clock().now().to_msg()
        request.start = Point(x=start.x, y=start.y, z=start.z)
        request.end = Point(x=goal.x, y=goal.y, z=goal.z)
        response = self.call(self.planner_client, request, 12.0, "goal planner")
        message = str(response.message)
        # Upstream leaves the response header at its default value on its
        # intentional No-path return.  Report that failure truthfully before
        # applying the frame contract required for an accepted path.
        if not response.success or not message.startswith("Found complete path"):
            raise MissionError(f"planner failed: success={response.success} message={message!r}")
        if response.header.frame_id != self.config.frame_id:
            raise MissionError(
                "planner response frame does not match configured map frame: "
                f"{response.header.frame_id!r}"
            )
        points = [XYZ(float(p.x), float(p.y), float(p.z)) for p in response.path]
        return points, message

    def request_validated_path(
        self,
        goal: XYZ | None = None,
        *,
        start: XYZ | None = None,
        require_visible_detour: bool = True,
    ) -> tuple[list[XYZ], str, dict[str, float]]:
        """Wait boundedly for a complete, contract-safe path as the live map settles."""
        start = start or self.config.start
        goal = goal or self.config.goal
        last_error: MissionError | None = None
        for attempt in range(1, self.config.planner_attempts + 1):
            try:
                raw_points, planner_message = self.request_path(goal, start=start)
                # Preserve even a geometrically rejected complete response in
                # the failure evidence instead of hiding what the planner sent.
                self.planned_points = list(raw_points)
                metrics = validate_path(
                    self.config,
                    raw_points,
                    start=start,
                    goal=goal,
                    require_visible_detour=require_visible_detour,
                )
                return raw_points, planner_message, metrics
            except MissionError as error:
                last_error = error
                self.event(
                    "planner_attempt_rejected",
                    attempt=attempt,
                    max_attempts=self.config.planner_attempts,
                    error=str(error),
                )
                if attempt == self.config.planner_attempts:
                    break
                self.run_for(self.config.planner_retry_interval_s, check_flight=True)
        assert last_error is not None
        raise MissionError(
            f"planner did not produce a safe complete path after "
            f"{self.config.planner_attempts} attempts: {last_error}"
        )

    def publish_markers(
        self,
        goal: XYZ,
        *,
        start: XYZ | None = None,
        goal_label: str,
    ) -> None:
        start = start or self.config.start
        now = self.get_clock().now().to_msg()
        markers = MarkerArray()
        for marker_id, (name, point, color) in enumerate(
            (
                ("Start" if self.interactive else "A", start, (0.1, 1.0, 0.2)),
                (goal_label, goal, (1.0, 0.2, 0.1)),
            )
        ):
            marker = Marker()
            marker.header.frame_id = self.config.frame_id
            marker.header.stamp = now
            marker.ns = "ab_points"
            marker.id = marker_id
            marker.type = Marker.SPHERE
            marker.action = Marker.ADD
            marker.pose.position.x = point.x
            marker.pose.position.y = point.y
            marker.pose.position.z = point.z
            marker.pose.orientation.w = 1.0
            marker.scale.x = marker.scale.y = marker.scale.z = 0.45
            marker.color.r, marker.color.g, marker.color.b = color
            marker.color.a = 1.0
            markers.markers.append(marker)
        self.marker_pub.publish(markers)

    def publish_plan(
        self,
        points: list[XYZ],
        goal: XYZ | None = None,
        *,
        start: XYZ | None = None,
    ) -> None:
        start = start or self.config.start
        goal = goal or self.config.goal
        now = self.get_clock().now().to_msg()
        path = NavPath()
        path.header.frame_id = self.config.frame_id
        path.header.stamp = now
        for point in points:
            pose = PoseStamped()
            pose.header = path.header
            pose.pose.position.x = point.x
            pose.pose.position.y = point.y
            pose.pose.position.z = point.z
            pose.pose.orientation.w = 1.0
            path.poses.append(pose)
        self.path_pub.publish(path)
        self.publish_markers(
            goal,
            start=start,
            goal_label="RViz goal" if self.interactive else "B",
        )
        self.event("plan_visualized", points=len(points))

    def move_to(
        self,
        waypoint: XYZ,
        label: str,
        *,
        target_yaw: float | None = None,
    ) -> None:
        if self.target is None:
            raise MissionError("no active setpoint target")
        start = self.target
        distance = start.distance(waypoint)
        start_yaw = self.target_yaw
        desired_yaw = normalize_angle(
            self.mission_yaw if target_yaw is None else target_yaw
        )
        yaw_delta = normalize_angle(desired_yaw - start_yaw)
        duration = max(
            0.5,
            distance / self.config.cruise_speed_mps,
            abs(yaw_delta) / math.radians(45.0),
        )
        steps = max(1, math.ceil(duration * self.config.setpoint_rate_hz))
        for step in range(1, steps + 1):
            ratio = step / steps
            self.target = XYZ(
                start.x + (waypoint.x - start.x) * ratio,
                start.y + (waypoint.y - start.y) * ratio,
                start.z + (waypoint.z - start.z) * ratio,
            )
            self.target_yaw = normalize_angle(start_yaw + yaw_delta * ratio)
            self.run_for(1.0 / self.config.setpoint_rate_hz, check_flight=True)
        self.wait_until(
            lambda: bool(
                self.position
                and self.position.distance(waypoint) <= self.config.waypoint_tolerance_m
                and self.vehicle_yaw is not None
                and abs(normalize_angle(desired_yaw - self.vehicle_yaw))
                <= math.radians(10.0)
            ),
            max(5.0, distance / self.config.cruise_speed_mps + 3.0),
            label,
        )
        self.event(
            label,
            waypoint=waypoint.as_list(),
            target_yaw_rad=desired_yaw,
        )

    def land(self) -> None:
        if not self.state or not self.state.armed:
            return
        try:
            self.set_mode("AUTO.LAND", 8.0)
        except Exception as first_error:
            self.event("auto_land_mode_failed", error=str(first_error))
            request = CommandTOL.Request()
            request.min_pitch = 0.0
            request.yaw = math.nan
            request.latitude = math.nan
            request.longitude = math.nan
            request.altitude = math.nan
            response = self.call(self.land_client, request, 8.0, "land")
            if not response.success:
                raise MissionError(f"land command rejected, result={int(response.result)}")
        self.target = None
        self.wait_until(
            lambda: bool(
                self.state
                and self.extended
                and not self.state.armed
                and self.extended.landed_state == ExtendedState.LANDED_STATE_ON_GROUND
            ),
            45.0,
            "landed and disarmed",
        )
        self.event("landed_disarmed")

    def require_safe_start(self, *, require_configured_xy: bool = True) -> XYZ:
        self.wait_inputs()
        if not self.state or not self.extended or not self.position:
            raise MissionError("inputs disappeared")
        if self.state.armed or self.extended.landed_state != ExtendedState.LANDED_STATE_ON_GROUND:
            raise MissionError("mission must start disarmed and on ground")
        if require_configured_xy and math.hypot(
            self.position.x - self.config.start.x,
            self.position.y - self.config.start.y,
        ) > 0.8:
            raise MissionError("vehicle is not at the configured A XY origin")
        return XYZ(self.position.x, self.position.y, self.config.takeoff_height_m)

    def run_plan_only(self) -> dict[str, Any]:
        """Request and visualize a path without publishing flight setpoints."""
        self.event("plan_only_start")
        self.require_safe_start()
        raw_points, planner_message = self.request_path()
        self.planned_points = list(raw_points)
        metrics = validate_path(self.config, raw_points)
        points = list(raw_points)
        if points[0].distance(self.config.start) > 1e-6:
            points.insert(0, self.config.start)
        self.planned_points = points
        self.publish_plan(points)
        self.run_for(1.0)
        self.event("planner_path_accepted", message=planner_message, **metrics)
        self.event("plan_only_complete", points=len(points))
        return {
            "verdict": "PASS",
            "mode": "plan_only",
            "planner": "mrs_octomap_planner::MinimalOctomapPlanner",
            "planner_message": planner_message,
            "start": self.config.start.as_list(),
            "goal": self.config.goal.as_list(),
            "planned_path": [point.as_list() for point in points],
            "metrics": metrics,
            "events": self.events,
        }

    def run(self) -> dict[str, Any]:
        self.events = []
        self.planned_points = []
        self.executed_samples = []
        self.selected_goal = None
        self.selected_goal_yaw = None
        self.active_start = None
        publish_count_start = self.publish_count
        self.event("interactive_mission_start" if self.interactive else "mission_start")
        actual_start = self.require_safe_start(
            require_configured_xy=not self.interactive
        )
        self.active_start = actual_start if self.interactive else self.config.start
        goal = self.wait_for_interactive_goal() if self.interactive else self.config.goal
        if self.interactive:
            if self.selected_goal_yaw is None:
                raise MissionError("interactive goal has no valid yaw")
            self.mission_yaw = self.selected_goal_yaw
        else:
            self.mission_yaw = math.atan2(
                goal.y - self.active_start.y,
                goal.x - self.active_start.x,
            )
        self.event("mission_heading_selected", yaw_rad=self.mission_yaw)
        mission_started = time.monotonic()

        # Pre-stream the landed pose, climb vertically without changing yaw,
        # then rotate once at a stable altitude.  This keeps takeoff thrust and
        # the estimator's handover to DLIO yaw out of the same transient.
        self.target = self.position
        if self.vehicle_yaw is not None:
            self.target_yaw = self.vehicle_yaw
        takeoff_yaw = self.target_yaw
        self.run_for(2.0)
        self.set_mode("OFFBOARD")
        self.arm()
        self.move_to(
            self.active_start,
            "takeoff_at_current_start" if self.interactive else "takeoff_at_A",
            target_yaw=takeoff_yaw,
        )
        self.move_to(self.active_start, "mission_heading_at_takeoff_altitude")
        self.run_for(self.config.map_warmup_s, check_flight=True)
        self.event("map_warmup_complete", seconds=self.config.map_warmup_s)

        raw_points, planner_message, metrics = self.request_validated_path(
            goal,
            start=self.active_start,
            require_visible_detour=not self.interactive,
        )
        points = list(raw_points)
        if points[0].distance(self.active_start) > 1e-6:
            points.insert(0, self.active_start)
        self.planned_points = points
        self.publish_plan(points, goal, start=self.active_start)
        self.event("planner_path_accepted", message=planner_message, **metrics)

        for index, point in enumerate(points[1:], start=1):
            if time.monotonic() - mission_started > self.config.mission_timeout_s:
                raise MissionError("mission timeout")
            self.move_to(point, f"waypoint_{index}")
        self.run_for(self.config.goal_hold_s, check_flight=True)
        if not self.position or self.position.distance(goal) > 0.4:
            raise MissionError("vehicle did not reach the requested goal")
        goal_error = self.position.distance(goal)
        self.event(
            "interactive_goal_reached" if self.interactive else "goal_B_reached",
            error_m=goal_error,
            goal=goal.as_list(),
        )
        self.land()
        return {
            "verdict": "PASS",
            "mode": "interactive_rviz_goal" if self.interactive else "fixed_ab",
            "planner": "mrs_octomap_planner::MinimalOctomapPlanner",
            "planner_message": planner_message,
            "start": self.active_start.as_list(),
            "goal": goal.as_list(),
            "goal_yaw_rad": self.mission_yaw,
            "planned_path": [point.as_list() for point in points],
            "metrics": {**metrics, "goal_error_m": goal_error},
            "publish_count": self.publish_count - publish_count_start,
            "events": self.events,
            "executed_samples": self.executed_samples,
        }


def self_test() -> int:
    config = DemoConfig(
        frame_id="map",
        start=XYZ(0.0, 0.0, 2.2),
        goal=XYZ(7.0, 7.0, 2.2),
        obstacle_xy=(3.5, 3.5),
        obstacle_radius_m=0.65,
        minimum_clearance_m=0.70,
        minimum_cross_track_m=0.55,
        takeoff_height_m=2.2,
        cruise_speed_mps=0.65,
        setpoint_rate_hz=20.0,
        waypoint_tolerance_m=0.3,
        goal_hold_s=3.0,
        map_warmup_s=12.0,
        planner_attempts=5,
        planner_retry_interval_s=4.0,
        mission_timeout_s=150.0,
        planner_service="/demo/minimal_planner/get_path",
        interactive_goal_topic="/demo/goal_pose",
        interactive_goal_min_distance_m=1.0,
        interactive_goal_max_distance_m=12.0,
        interactive_goal_timeout_s=300.0,
    )
    detour = [config.start, XYZ(2.0, 0.5, 2.2), XYZ(5.0, 2.0, 2.2), config.goal]
    metrics = validate_path(config, detour)
    rejected = False
    try:
        validate_path(config, [config.start, config.goal])
    except MissionError:
        rejected = True
    if not rejected or metrics["max_cross_track_m"] < config.minimum_cross_track_m:
        raise SystemExit("self-test failed")
    interactive_goal = XYZ(3.0, 0.0, 2.2)
    interactive_metrics = validate_path(
        config,
        [config.start, interactive_goal],
        goal=interactive_goal,
        require_visible_detour=False,
    )
    if interactive_metrics["path_length_m"] != 3.0:
        raise SystemExit("interactive self-test failed")
    retry_start = XYZ(5.0, 0.0, 2.2)
    retry_goal = XYZ(7.0, 0.0, 2.2)
    retry_metrics = validate_path(
        config,
        [retry_start, retry_goal],
        start=retry_start,
        goal=retry_goal,
        require_visible_detour=False,
    )
    if retry_metrics["path_length_m"] != 2.0:
        raise SystemExit("interactive retry-start self-test failed")
    yaw_90 = quaternion_yaw(0.0, 0.0, math.sin(math.pi / 4.0), math.cos(math.pi / 4.0))
    shortest_turn = normalize_angle(math.radians(-170.0) - math.radians(170.0))
    if not math.isclose(yaw_90, math.pi / 2.0, abs_tol=1e-9) or not math.isclose(
        shortest_turn,
        math.radians(20.0),
        abs_tol=1e-9,
    ):
        raise SystemExit("interactive yaw self-test failed")
    print(
        json.dumps(
            {
                "self_test": "PASS",
                "fixed_metrics": metrics,
                "interactive_metrics": interactive_metrics,
                "interactive_retry_metrics": retry_metrics,
                "interactive_yaw_rad": yaw_90,
                "shortest_turn_rad": shortest_turn,
            },
            sort_keys=True,
        )
    )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path)
    parser.add_argument("--result", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--interactive", action="store_true")
    return parser.parse_args()


def write_mission_result(path: Path, result: dict[str, Any], index: int | None = None) -> None:
    payload = json.dumps(result, indent=2, sort_keys=True) + "\n"
    path.write_text(payload, encoding="utf-8")
    if index is not None:
        indexed = path.with_name(f"{path.stem}-{index:03d}{path.suffix}")
        indexed.write_text(payload, encoding="utf-8")


def failed_mission_result(
    node: ABMission,
    config: DemoConfig,
    error: Exception,
    landing_error: Exception | None,
) -> dict[str, Any]:
    start = node.active_start or config.start
    result: dict[str, Any] = {
        "verdict": "FAIL",
        "error": str(error),
        "start": start.as_list(),
        "goal": (
            node.selected_goal.as_list()
            if node.selected_goal is not None
            else config.goal.as_list()
        ),
        "goal_yaw_rad": node.selected_goal_yaw,
        "events": list(node.events),
        "planned_path": [point.as_list() for point in node.planned_points],
        "executed_samples": list(node.executed_samples),
    }
    if landing_error is not None:
        result["landing_error"] = str(landing_error)
    return result


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test()
    if args.config is None or args.result is None:
        raise SystemExit("--config and --result are required")
    if args.plan_only and args.interactive:
        raise SystemExit("--plan-only and --interactive are mutually exclusive")
    config = load_config(args.config.resolve(strict=True))
    args.result.parent.mkdir(parents=True, exist_ok=True)
    node: ABMission | None = None
    rclpy.init()
    try:
        node = ABMission(config, interactive=args.interactive)

        def stop_requested(_signum: int, _frame: Any) -> None:
            if node is not None:
                node.shutdown_requested = True

        signal.signal(signal.SIGINT, stop_requested)
        signal.signal(signal.SIGTERM, stop_requested)
        if args.interactive:
            mission_index = 0
            return_code = 0
            while not node.shutdown_requested:
                try:
                    result = node.run()
                    landing_error = None
                except Exception as error:
                    if (
                        node.shutdown_requested
                        and node.selected_goal is None
                        and not bool(node.state and node.state.armed)
                    ):
                        break
                    node.event("mission_failed", error=str(error))
                    landing_error = None
                    try:
                        node.land()
                    except Exception as caught_landing_error:
                        landing_error = caught_landing_error
                    result = failed_mission_result(
                        node,
                        config,
                        error,
                        landing_error,
                    )

                mission_index += 1
                result["mission_index"] = mission_index
                write_mission_result(args.result, result, mission_index)
                node.get_logger().info(
                    f"mission_{mission_index:03d}_saved: "
                    f"verdict={result['verdict']} result={args.result}"
                )

                if landing_error is not None:
                    return_code = 1
                    break
                if node.shutdown_requested:
                    break
                try:
                    node.require_safe_start(require_configured_xy=False)
                except Exception as retry_error:
                    node.get_logger().error(
                        f"cannot wait for another goal safely: {retry_error}"
                    )
                    return_code = 1
                    break
                node.get_logger().info(
                    "ready_for_next_interactive_goal: choose '2D Goal Pose' again; "
                    "Ctrl+C stops the persistent session"
                )
            return return_code

        try:
            result = node.run_plan_only() if args.plan_only else node.run()
            return_code = 0
        except Exception as error:
            node.event("mission_failed", error=str(error))
            landing_error = None
            try:
                node.land()
            except Exception as caught_landing_error:
                landing_error = caught_landing_error
            result = failed_mission_result(node, config, error, landing_error)
            return_code = 1
        write_mission_result(args.result, result)
        return return_code
    finally:
        if node is not None:
            node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    sys.exit(main())
