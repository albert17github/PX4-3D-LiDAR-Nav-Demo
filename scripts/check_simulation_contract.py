#!/usr/bin/env python3
"""Verify that the benchmark geometry matches its Gazebo world definition."""

from __future__ import annotations

import argparse
import json
import math
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

import yaml


class ContractError(RuntimeError):
    pass


def finite_list(raw: Any, name: str, length: int) -> tuple[float, ...]:
    if not isinstance(raw, list) or len(raw) != length:
        raise ContractError(f"{name} must contain {length} numbers")
    values = tuple(float(value) for value in raw)
    if not all(math.isfinite(value) for value in values):
        raise ContractError(f"{name} contains a non-finite value")
    return values


def pose_values(element: ET.Element, name: str) -> tuple[float, ...]:
    pose = element.find("pose")
    if pose is None or not pose.text:
        raise ContractError(f"{name} has no pose")
    try:
        values = tuple(float(value) for value in pose.text.split())
    except ValueError as error:
        raise ContractError(f"{name} pose is not numeric") from error
    if len(values) != 6 or not all(math.isfinite(value) for value in values):
        raise ContractError(f"{name} pose must contain six finite numbers")
    return values


def named_model(world: ET.Element, name: str) -> ET.Element:
    for model in world.findall("model"):
        if model.get("name") == name:
            return model
    raise ContractError(f"world model is missing: {name}")


def named_include(world: ET.Element, name: str) -> ET.Element:
    for include in world.findall("include"):
        child = include.find("name")
        if child is not None and (child.text or "").strip() == name:
            return include
    raise ContractError(f"world include is missing: {name}")


def world_xy_to_map_xy(
    world_xy: tuple[float, float], origin_xy_yaw: tuple[float, float, float]
) -> tuple[float, float]:
    dx = world_xy[0] - origin_xy_yaw[0]
    dy = world_xy[1] - origin_xy_yaw[1]
    cosine = math.cos(origin_xy_yaw[2])
    sine = math.sin(origin_xy_yaw[2])
    return cosine * dx + sine * dy, -sine * dx + cosine * dy


def verify(config_path: Path, world_path: Path) -> dict[str, Any]:
    raw = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ContractError("demo config is not a mapping")
    origin = finite_list(
        raw.get("simulation_map_origin_world_xy_yaw_rad"),
        "simulation_map_origin_world_xy_yaw_rad",
        3,
    )
    obstacle_world = finite_list(
        raw.get("expected_obstacle_center_world_xy"),
        "expected_obstacle_center_world_xy",
        2,
    )
    radius = float(raw.get("expected_obstacle_radius_m", math.nan))
    vehicle_name = str(raw.get("simulation_vehicle_model_name", ""))
    obstacle_name = str(raw.get("expected_obstacle_model_name", ""))
    if not vehicle_name or not obstacle_name or not math.isfinite(radius):
        raise ContractError("simulation model names and obstacle radius are required")

    document = ET.parse(world_path)
    world = document.getroot().find("world")
    if world is None:
        raise ContractError("SDF has no world element")
    vehicle_pose = pose_values(named_include(world, vehicle_name), vehicle_name)
    obstacle = named_model(world, obstacle_name)
    obstacle_pose = pose_values(obstacle, obstacle_name)
    radius_element = obstacle.find("./link/collision/geometry/cylinder/radius")
    if radius_element is None or not radius_element.text:
        raise ContractError(f"{obstacle_name} has no cylinder radius")
    world_radius = float(radius_element.text)

    expected_origin = (vehicle_pose[0], vehicle_pose[1], vehicle_pose[5])
    expected_obstacle = (obstacle_pose[0], obstacle_pose[1])
    if any(
        not math.isclose(actual, expected, abs_tol=1e-9, rel_tol=0.0)
        for actual, expected in zip(origin, expected_origin)
    ):
        raise ContractError(
            f"configured map origin {origin!r} does not match world {expected_origin!r}"
        )
    if any(
        not math.isclose(actual, expected, abs_tol=1e-9, rel_tol=0.0)
        for actual, expected in zip(obstacle_world, expected_obstacle)
    ):
        raise ContractError(
            "configured obstacle center "
            f"{obstacle_world!r} does not match world {expected_obstacle!r}"
        )
    if not math.isclose(radius, world_radius, abs_tol=1e-9, rel_tol=0.0):
        raise ContractError(
            f"configured obstacle radius {radius} does not match world {world_radius}"
        )

    obstacle_map = world_xy_to_map_xy(
        (obstacle_world[0], obstacle_world[1]),
        (origin[0], origin[1], origin[2]),
    )
    return {
        "verdict": "PASS",
        "vehicle_model": vehicle_name,
        "vehicle_world_xy_yaw_rad": list(origin),
        "obstacle_model": obstacle_name,
        "obstacle_world_xy": list(obstacle_world),
        "obstacle_map_xy": list(obstacle_map),
        "obstacle_radius_m": radius,
    }


def self_test() -> None:
    point = world_xy_to_map_xy(
        (-6.845569474049038, -1.186758871534423),
        (-8.0, -6.0, 0.55),
    )
    if not (
        math.isclose(point[0], 3.5, abs_tol=1e-9)
        and math.isclose(point[1], 3.5, abs_tol=1e-9)
    ):
        raise ContractError("world-to-map transform self-test failed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path)
    parser.add_argument("--world", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        print(json.dumps({"self_test": "PASS"}, sort_keys=True))
        return 0
    if args.config is None or args.world is None:
        parser.error("--config and --world are required without --self-test")
    print(
        json.dumps(
            verify(args.config.resolve(strict=True), args.world.resolve(strict=True)),
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ContractError, ET.ParseError, OSError, ValueError) as error:
        raise SystemExit(f"simulation contract verification failed: {error}") from error
