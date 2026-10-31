"""
Arena geometry, pressure plates, doors, energy shards, and interactive objects.
"""

from typing import List, Dict, Tuple, Optional, Set
from game.entities import Vec2, BoundingBox, get_next_id, Entity


class PressurePlate:
    """
    A floor switch that triggers when stepped on by a player OR a holographic echo.
    """

    def __init__(
        self,
        x: float,
        y: float,
        width: float = 54.0,
        height: float = 54.0,
        plate_id: Optional[int] = None,
        label: str = "",
    ):
        self.id = plate_id if plate_id is not None else get_next_id()
        self.box = BoundingBox(x, y, width, height)
        self.is_active = False
        self.occupant_count = 0
        self.label = label
        self.activation_ratio = 0.0  # 0.0 to 1.0 for visual depression animation

    @property
    def center(self) -> Vec2:
        return self.box.center

    def update_occupancy(self, entities: List[Entity]):
        """
        Check if any active player or echo is standing on the plate.
        """
        count = 0
        for ent in entities:
            if not ent.active:
                continue
            # Treat entity center or edge circle intersecting plate
            closest_x = max(self.box.left, min(ent.position.x, self.box.right))
            closest_y = max(self.box.top, min(ent.position.y, self.box.bottom))
            dx = ent.position.x - closest_x
            dy = ent.position.y - closest_y
            if (dx * dx + dy * dy) <= (ent.radius * ent.radius):
                count += 1

        self.occupant_count = count
        self.is_active = count > 0

    def update_visuals(self, dt: float):
        target = 1.0 if self.is_active else 0.0
        speed = 8.0 * dt
        if self.activation_ratio < target:
            self.activation_ratio = min(target, self.activation_ratio + speed)
        elif self.activation_ratio > target:
            self.activation_ratio = max(target, self.activation_ratio - speed)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": self.box.x,
            "y": self.box.y,
            "w": self.box.width,
            "h": self.box.height,
            "active": self.is_active,
            "label": self.label,
        }


class Door:
    """
    A security barrier that opens when its linked pressure plates or conditions are met.
    """

    def __init__(
        self,
        x: float,
        y: float,
        width: float,
        height: float,
        linked_plate_ids: Optional[List[int]] = None,
        require_all_plates: bool = True,
        door_id: Optional[int] = None,
        is_exit: bool = False,
    ):
        self.id = door_id if door_id is not None else get_next_id()
        self.box = BoundingBox(x, y, width, height)
        self.linked_plate_ids = linked_plate_ids or []
        self.require_all_plates = require_all_plates
        self.is_open = False
        self.is_exit = is_exit
        self.open_progress = 0.0  # 0.0 = closed, 1.0 = fully open

    def update_state(self, plates: Dict[int, PressurePlate], shards_remaining: int = 0, enemies_remaining: int = 0):
        if self.linked_plate_ids:
            if self.require_all_plates:
                self.is_open = all(plates.get(pid) and plates[pid].is_active for pid in self.linked_plate_ids)
            else:
                self.is_open = any(plates.get(pid) and plates[pid].is_active for pid in self.linked_plate_ids)
        elif self.is_exit:
            self.is_open = (shards_remaining == 0 and enemies_remaining == 0)

    def update_visuals(self, dt: float):
        target = 1.0 if self.is_open else 0.0
        speed = 4.0 * dt
        if self.open_progress < target:
            self.open_progress = min(target, self.open_progress + speed)
        elif self.open_progress > target:
            self.open_progress = max(target, self.open_progress - speed)

    @property
    def current_obstacle_box(self) -> Optional[BoundingBox]:
        """Returns the collision box if the door is blocking; None if open."""
        if self.open_progress > 0.8:
            return None
        return self.box

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": self.box.x,
            "y": self.box.y,
            "w": self.box.width,
            "h": self.box.height,
            "open": self.is_open,
            "progress": round(self.open_progress, 2),
            "exit": self.is_exit,
        }


class EnergyShard:
    """A collectible temporal energy shard."""

    def __init__(self, x: float, y: float, shard_id: Optional[int] = None):
        self.id = shard_id if shard_id is not None else get_next_id()
        self.position = Vec2(x, y)
        self.radius = 12.0
        self.collected = False
        self.bob_timer = 0.0

    def update(self, dt: float):
        self.bob_timer += dt

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": round(self.position.x, 1),
            "y": round(self.position.y, 1),
            "collected": self.collected,
        }
