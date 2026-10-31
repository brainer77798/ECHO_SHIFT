"""
Core math utilities, base entities, and collision shapes.
"""

import math
import itertools
from typing import Tuple, List, Optional

_id_counter = itertools.count(1)

def get_next_id() -> int:
    """Generate a globally unique integer ID."""
    return next(_id_counter)


class Vec2:
    """Lightweight 2D vector class compatible with headless tests and Pygame."""
    __slots__ = ("x", "y")

    def __init__(self, x: float = 0.0, y: float = 0.0):
        self.x = float(x)
        self.y = float(y)

    def __add__(self, other: "Vec2") -> "Vec2":
        return Vec2(self.x + other.x, self.y + other.y)

    def __sub__(self, other: "Vec2") -> "Vec2":
        return Vec2(self.x - other.x, self.y - other.y)

    def __mul__(self, scalar: float) -> "Vec2":
        return Vec2(self.x * scalar, self.y * scalar)

    def __rmul__(self, scalar: float) -> "Vec2":
        return Vec2(self.x * scalar, self.y * scalar)

    def __truediv__(self, scalar: float) -> "Vec2":
        if scalar == 0:
            return Vec2(0, 0)
        return Vec2(self.x / scalar, self.y / scalar)

    def __neg__(self) -> "Vec2":
        return Vec2(-self.x, -self.y)

    def length_squared(self) -> float:
        return self.x * self.x + self.y * self.y

    def length(self) -> float:
        return math.hypot(self.x, self.y)

    def distance_to(self, other: "Vec2") -> float:
        return math.hypot(self.x - other.x, self.y - other.y)

    def distance_squared_to(self, other: "Vec2") -> float:
        dx = self.x - other.x
        dy = self.y - other.y
        return dx * dx + dy * dy

    def normalize(self) -> "Vec2":
        l = self.length()
        if l > 1e-6:
            return Vec2(self.x / l, self.y / l)
        return Vec2(0.0, 0.0)

    def dot(self, other: "Vec2") -> float:
        return self.x * other.x + self.y * other.y

    def copy(self) -> "Vec2":
        return Vec2(self.x, self.y)

    def to_tuple(self) -> Tuple[float, float]:
        return (self.x, self.y)

    def to_int_tuple(self) -> Tuple[int, int]:
        return (round(self.x), round(self.y))

    def rotate(self, angle_degrees: float) -> "Vec2":
        rad = math.radians(angle_degrees)
        cos_a = math.cos(rad)
        sin_a = math.sin(rad)
        return Vec2(
            self.x * cos_a - self.y * sin_a,
            self.x * sin_a + self.y * cos_a
        )

    def __repr__(self) -> str:
        return f"Vec2({self.x:.2f}, {self.y:.2f})"


def clamp(val: float, low: float, high: float) -> float:
    return max(low, min(val, high))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * clamp(t, 0.0, 1.0)


def distance_sq_point_to_segment(pt: Vec2, p1: Vec2, p2: Vec2) -> float:
    """Calculate squared distance from point pt to line segment [p1, p2]."""
    seg_dx = p2.x - p1.x
    seg_dy = p2.y - p1.y
    seg_len_sq = seg_dx * seg_dx + seg_dy * seg_dy
    if seg_len_sq < 1e-6:
        dx = pt.x - p1.x
        dy = pt.y - p1.y
        return dx * dx + dy * dy

    t = ((pt.x - p1.x) * seg_dx + (pt.y - p1.y) * seg_dy) / seg_len_sq
    t = max(0.0, min(1.0, t))
    closest_x = p1.x + t * seg_dx
    closest_y = p1.y + t * seg_dy
    dx = pt.x - closest_x
    dy = pt.y - closest_y
    return dx * dx + dy * dy


class BoundingBox:
    """Axis-aligned bounding box."""
    __slots__ = ("x", "y", "width", "height")

    def __init__(self, x: float, y: float, width: float, height: float):
        self.x = float(x)
        self.y = float(y)
        self.width = float(width)
        self.height = float(height)

    @property
    def left(self) -> float:
        return self.x

    @property
    def right(self) -> float:
        return self.x + self.width

    @property
    def top(self) -> float:
        return self.y

    @property
    def bottom(self) -> float:
        return self.y + self.height

    @property
    def center(self) -> Vec2:
        return Vec2(self.x + self.width / 2.0, self.y + self.height / 2.0)

    def contains_point(self, pt: Vec2) -> bool:
        return (self.left <= pt.x <= self.right) and (self.top <= pt.y <= self.bottom)

    def intersects(self, other: "BoundingBox") -> bool:
        return not (
            self.right < other.left
            or self.left > other.right
            or self.bottom < other.top
            or self.top > other.bottom
        )

    def to_tuple(self) -> Tuple[float, float, float, float]:
        return (self.x, self.y, self.width, self.height)


class Entity:
    """Base class for all interactive entities in ECHO//SHIFT."""
    def __init__(self, x: float, y: float, radius: float = 16.0, entity_id: Optional[int] = None):
        self.id = entity_id if entity_id is not None else get_next_id()
        self.position = Vec2(x, y)
        self.velocity = Vec2(0, 0)
        self.radius = float(radius)
        self.active = True

    def update(self, dt: float):
        self.position.x += self.velocity.x * dt
        self.position.y += self.velocity.y * dt

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": round(self.position.x, 1),
            "y": round(self.position.y, 1),
            "vx": round(self.velocity.x, 1),
            "vy": round(self.velocity.y, 1),
            "radius": self.radius,
            "active": self.active,
        }
