"""
Projectiles and area hazards.
"""

from typing import Optional, Tuple
from game.entities import Entity, Vec2, get_next_id
from settings import (
    SHOT_SPEED,
    SHOT_RADIUS,
    PLAYER_SHOT_DAMAGE,
    ECHO_DAMAGE_MULTIPLIER,
    PLAYER_COLOR,
    ECHO_COLOR,
    ENEMY_COLOR,
)


class Projectile(Entity):
    def __init__(
        self,
        x: float,
        y: float,
        dir_x: float,
        dir_y: float,
        owner_id: int,
        is_echo: bool = False,
        is_enemy: bool = False,
        damage: Optional[float] = None,
        speed: float = SHOT_SPEED,
        life: float = 1.2,
        radius: float = SHOT_RADIUS,
        projectile_id: Optional[int] = None,
    ):
        super().__init__(x, y, radius, projectile_id)
        self.prev_position = Vec2(x, y)
        direction = Vec2(dir_x, dir_y).normalize()
        self.velocity = direction * speed
        self.owner_id = owner_id
        self.is_echo = is_echo
        self.is_enemy = is_enemy
        self.life = life
        self.max_life = life

        if damage is not None:
            self.damage = damage
        elif is_enemy:
            self.damage = 10.0
        elif is_echo:
            self.damage = PLAYER_SHOT_DAMAGE * ECHO_DAMAGE_MULTIPLIER
        else:
            self.damage = PLAYER_SHOT_DAMAGE

        if is_enemy:
            self.color = ENEMY_COLOR
        elif is_echo:
            self.color = ECHO_COLOR
        else:
            self.color = PLAYER_COLOR

    def update(self, dt: float):
        self.prev_position.x = self.position.x
        self.prev_position.y = self.position.y
        super().update(dt)
        self.life -= dt
        if self.life <= 0:
            self.active = False

    def to_dict(self) -> dict:
        d = super().to_dict()
        d.update({
            "owner": self.owner_id,
            "is_echo": self.is_echo,
            "is_enemy": self.is_enemy,
            "damage": self.damage,
            "life": round(self.life, 2),
        })
        return d


class DangerZone:
    """An area telegraph used by Sentries and Bosses before striking."""
    def __init__(
        self,
        x: float,
        y: float,
        radius: float,
        charge_time: float,
        active_time: float,
        damage: float = 25.0,
        zone_id: Optional[int] = None,
    ):
        self.id = zone_id if zone_id is not None else get_next_id()
        self.position = Vec2(x, y)
        self.radius = radius
        self.charge_time = charge_time
        self.active_time = active_time
        self.elapsed = 0.0
        self.damage = damage
        self.has_triggered = False
        self.active = True

    @property
    def is_warning(self) -> bool:
        return self.elapsed < self.charge_time

    @property
    def is_damaging(self) -> bool:
        return self.charge_time <= self.elapsed < (self.charge_time + self.active_time)

    def update(self, dt: float):
        self.elapsed += dt
        if self.elapsed >= (self.charge_time + self.active_time):
            self.active = False

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "x": round(self.position.x, 1),
            "y": round(self.position.y, 1),
            "radius": round(self.radius, 1),
            "charge_time": self.charge_time,
            "elapsed": round(self.elapsed, 2),
            "is_damaging": self.is_damaging,
            "active": self.active,
        }
