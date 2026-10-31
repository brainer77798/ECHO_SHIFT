"""
Collision detection, obstacle queries, raycasts, and wall sliding resolution.
"""

import math
from typing import List, Tuple, Optional
from game.entities import Vec2, BoundingBox, clamp


def circle_intersects_circle(pos1: Vec2, r1: float, pos2: Vec2, r2: float) -> bool:
    dist_sq = pos1.distance_squared_to(pos2)
    radius_sum = r1 + r2
    return dist_sq <= (radius_sum * radius_sum)


def circle_intersects_rect(pos: Vec2, radius: float, rect: BoundingBox) -> bool:
    closest_x = clamp(pos.x, rect.left, rect.right)
    closest_y = clamp(pos.y, rect.top, rect.bottom)
    dx = pos.x - closest_x
    dy = pos.y - closest_y
    return (dx * dx + dy * dy) <= (radius * radius)


def point_in_rect(pt: Vec2, rect: BoundingBox) -> bool:
    return rect.contains_point(pt)


def resolve_circle_rect_collision(pos: Vec2, radius: float, rect: BoundingBox) -> Vec2:
    """
    Pushes a circle out of an axis-aligned bounding box to prevent overlap,
    allowing smooth sliding along walls.
    """
    closest_x = clamp(pos.x, rect.left, rect.right)
    closest_y = clamp(pos.y, rect.top, rect.bottom)
    dx = pos.x - closest_x
    dy = pos.y - closest_y
    dist_sq = dx * dx + dy * dy

    if dist_sq == 0.0:
        # Center is inside the rectangle; push along the shortest axis
        dl = abs(pos.x - rect.left)
        dr = abs(rect.right - pos.x)
        dt = abs(pos.y - rect.top)
        db = abs(rect.bottom - pos.y)
        min_dist = min(dl, dr, dt, db)
        if min_dist == dl:
            return Vec2(rect.left - radius, pos.y)
        elif min_dist == dr:
            return Vec2(rect.right + radius, pos.y)
        elif min_dist == dt:
            return Vec2(pos.x, rect.top - radius)
        else:
            return Vec2(pos.x, rect.bottom + radius)

    if dist_sq < radius * radius:
        dist = math.sqrt(dist_sq)
        push_x = (dx / dist) * (radius - dist)
        push_y = (dy / dist) * (radius - dist)
        return Vec2(pos.x + push_x, pos.y + push_y)

    return pos


def resolve_circle_obstacles(pos: Vec2, radius: float, obstacles: List[BoundingBox]) -> Vec2:
    """Resolve collision against multiple obstacles in sequence."""
    new_pos = pos.copy()
    for obs in obstacles:
        new_pos = resolve_circle_rect_collision(new_pos, radius, obs)
    return new_pos


def line_intersects_rect(p1: Vec2, p2: Vec2, rect: BoundingBox) -> bool:
    """Check if a line segment intersects an axis-aligned box (Liang-Barsky)."""
    p = [-(p2.x - p1.x), p2.x - p1.x, -(p2.y - p1.y), p2.y - p1.y]
    q = [p1.x - rect.left, rect.right - p1.x, p1.y - rect.top, rect.bottom - p1.y]

    u1 = 0.0
    u2 = 1.0

    for i in range(4):
        if p[i] == 0:
            if q[i] < 0:
                return False
        else:
            t = q[i] / p[i]
            if p[i] < 0:
                if t > u2:
                    return False
                if t > u1:
                    u1 = t
            elif p[i] > 0:
                if t < u1:
                    return False
                if t < u2:
                    u2 = t

    return u1 <= u2


def has_line_of_sight(p1: Vec2, p2: Vec2, obstacles: List[BoundingBox]) -> bool:
    for obs in obstacles:
        if line_intersects_rect(p1, p2, obs):
            return False
    return True
