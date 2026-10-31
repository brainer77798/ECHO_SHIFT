"""
Enemy archetypes: Hunter Drone, Sentry, Armored Brute, and The Warden (Boss).
"""

import math
import random
from typing import List, Tuple, Optional, Dict
from game.entities import Entity, Vec2, BoundingBox, clamp, get_next_id
from game.collisions import resolve_circle_obstacles, has_line_of_sight
from game.projectiles import Projectile, DangerZone
from settings import ENEMY_COLOR


class BaseEnemy(Entity):
    def __init__(
        self,
        x: float,
        y: float,
        radius: float,
        health: float,
        speed: float,
        score_value: int,
        enemy_type: str,
        enemy_id: Optional[int] = None,
    ):
        super().__init__(x, y, radius, enemy_id)
        self.health = float(health)
        self.max_health = float(health)
        self.speed = float(speed)
        self.score_value = score_value
        self.enemy_type = enemy_type
        self.hit_flash = 0.0
        self.facing = Vec2(1, 0)
        self.has_awarded_score = False

    def take_damage(self, amount: float, hit_direction: Optional[Vec2] = None) -> float:
        """Apply damage and return actual damage taken."""
        actual_dmg = amount
        self.health = max(0.0, self.health - actual_dmg)
        self.hit_flash = 0.1
        if self.health <= 0:
            self.active = False
        return actual_dmg

    def find_nearest_target(self, targets: List[Entity]) -> Optional[Entity]:
        """Find the closest active player or holographic echo."""
        best_dist_sq = float("inf")
        best_target = None
        for t in targets:
            if not t.active:
                continue
            d_sq = self.position.distance_squared_to(t.position)
            if d_sq < best_dist_sq:
                best_dist_sq = d_sq
                best_target = t
        return best_target

    def to_dict(self) -> dict:
        d = super().to_dict()
        d.update({
            "type": self.enemy_type,
            "health": round(self.health, 1),
            "max_health": round(self.max_health, 1),
            "facing_x": round(self.facing.x, 2),
            "facing_y": round(self.facing.y, 2),
            "hit_flash": self.hit_flash > 0,
        })
        return d


class HunterDrone(BaseEnemy):
    """Fast melee drone that pursues players or echoes and deals contact damage."""

    def __init__(self, x: float, y: float, enemy_id: Optional[int] = None):
        super().__init__(
            x=x,
            y=y,
            radius=16.0,
            health=3.0,
            speed=90.0,
            score_value=100,
            enemy_type="hunter",
            enemy_id=enemy_id,
        )
        self.contact_cooldown = 0.0

    def update_ai(
        self,
        dt: float,
        targets: List[Entity],
        obstacles: List[BoundingBox],
    ) -> List[Dict]:
        self.hit_flash = max(0.0, self.hit_flash - dt)
        self.contact_cooldown = max(0.0, self.contact_cooldown - dt)

        target = self.find_nearest_target(targets)
        if target:
            diff = target.position - self.position
            dist = diff.length()
            if dist > 2.0:
                self.facing = diff.normalize()
                self.position += self.facing * self.speed * dt

        self.position = resolve_circle_obstacles(self.position, self.radius, obstacles)
        return []


class Sentry(BaseEnemy):
    """Stationary or slow ranged turret that telegraphs an aimed sniper shot before firing."""

    def __init__(self, x: float, y: float, enemy_id: Optional[int] = None):
        super().__init__(
            x=x,
            y=y,
            radius=20.0,
            health=5.0,
            speed=0.0,
            score_value=175,
            enemy_type="sentry",
            enemy_id=enemy_id,
        )
        self.fire_cooldown = 2.4
        self.charge_timer = 0.0
        self.is_charging = False
        self.laser_target = Vec2(0, 0)

    def update_ai(
        self,
        dt: float,
        targets: List[Entity],
        obstacles: List[BoundingBox],
    ) -> List[Dict]:
        self.hit_flash = max(0.0, self.hit_flash - dt)
        spawned_projectiles = []

        target = self.find_nearest_target(targets)

        if not self.is_charging:
            self.fire_cooldown -= dt
            if target and self.fire_cooldown <= 0.0:
                # Check line of sight
                if has_line_of_sight(self.position, target.position, obstacles):
                    self.is_charging = True
                    self.charge_timer = 0.8  # 0.8s telegraph warning
                    self.laser_target = target.position.copy()
                    diff = (target.position - self.position)
                    if diff.length_squared() > 1e-4:
                        self.facing = diff.normalize()
        else:
            self.charge_timer -= dt
            # Track target slightly while charging
            if target:
                diff = (target.position - self.position)
                if diff.length_squared() > 1e-4:
                    self.facing = diff.normalize()
                    self.laser_target = self.position + self.facing * 500.0

            if self.charge_timer <= 0.0:
                self.is_charging = False
                self.fire_cooldown = 2.2
                # Emit high-speed sentry projectile
                spawned_projectiles.append({
                    "x": self.position.x + self.facing.x * 24.0,
                    "y": self.position.y + self.facing.y * 24.0,
                    "dir_x": self.facing.x,
                    "dir_y": self.facing.y,
                    "speed": 520.0,
                    "damage": 18.0,
                    "is_enemy": True,
                    "life": 1.5,
                })

        return spawned_projectiles

    def to_dict(self) -> dict:
        d = super().to_dict()
        d.update({
            "is_charging": self.is_charging,
            "laser_x": round(self.laser_target.x, 1),
            "laser_y": round(self.laser_target.y, 1),
        })
        return d


class ArmoredBrute(BaseEnemy):
    """
    Heavy security automaton with a frontal shield plate.
    Frontal shots deal 80% reduced damage. Must be flanked or attacked from the rear.
    """

    def __init__(self, x: float, y: float, enemy_id: Optional[int] = None):
        super().__init__(
            x=x,
            y=y,
            radius=26.0,
            health=14.0,
            speed=55.0,
            score_value=300,
            enemy_type="brute",
            enemy_id=enemy_id,
        )
        self.shield_active = True
        self.attack_cooldown = 2.0

    def take_damage(self, amount: float, hit_direction: Optional[Vec2] = None) -> float:
        """Check if projectile struck the front shield."""
        if hit_direction is not None and self.shield_active:
            # Angle between brute facing and incoming shot vector
            # If shot comes from opposite of facing (front), dot product is negative
            dot = self.facing.dot(hit_direction)
            if dot < -0.3:  # Struck from the front shield
                amount *= 0.2  # 80% damage reduction
                self.hit_flash = 0.05
                return super().take_damage(amount, hit_direction)

        return super().take_damage(amount, hit_direction)

    def update_ai(
        self,
        dt: float,
        targets: List[Entity],
        obstacles: List[BoundingBox],
    ) -> List[Dict]:
        self.hit_flash = max(0.0, self.hit_flash - dt)
        self.attack_cooldown = max(0.0, self.attack_cooldown - dt)

        target = self.find_nearest_target(targets)
        spawned = []
        if target:
            diff = target.position - self.position
            dist = diff.length()
            if dist > 2.0:
                self.facing = diff.normalize()
                self.position += self.facing * self.speed * dt

            # Heavy shockwave slam if close
            if dist < 65.0 and self.attack_cooldown <= 0.0:
                self.attack_cooldown = 2.5
                for ang in (-30, 0, 30):
                    dir_vec = self.facing.rotate(ang)
                    spawned.append({
                        "x": self.position.x + dir_vec.x * 30.0,
                        "y": self.position.y + dir_vec.y * 30.0,
                        "dir_x": dir_vec.x,
                        "dir_y": dir_vec.y,
                        "speed": 340.0,
                        "damage": 15.0,
                        "is_enemy": True,
                        "life": 1.2,
                    })

        self.position = resolve_circle_obstacles(self.position, self.radius, obstacles)
        return spawned


class WardenBoss(BaseEnemy):
    """
    THE WARDEN - Temporal Reactor Intelligence.
    Phase 1: Aimed energy barrages and summoning hunter drones.
    Phase 2: Temporal Shield activated; vulnerable only when temporal pressure plates are held!
    Phase 3: Overdrive spiral attack, exposed core, higher speed.
    """

    def __init__(self, x: float, y: float, enemy_id: Optional[int] = None):
        super().__init__(
            x=x,
            y=y,
            radius=48.0,
            health=75.0,
            speed=35.0,
            score_value=1500,
            enemy_type="warden",
            enemy_id=enemy_id,
        )
        self.phase = 1
        self.shield_active = False
        self.attack_timer = 1.5
        self.summon_timer = 6.0
        self.spiral_angle = 0.0
        self.shield_plates_active = False

    def take_damage(self, amount: float, hit_direction: Optional[Vec2] = None) -> float:
        if self.shield_active and not self.shield_plates_active:
            self.hit_flash = 0.03
            return 0.0  # Invulnerable until temporal shield is disrupted by pressure plates!

        dmg = super().take_damage(amount, hit_direction)

        # Phase transitions
        hp_ratio = self.health / self.max_health
        if hp_ratio > 0.60:
            self.phase = 1
            self.shield_active = False
        elif hp_ratio > 0.30:
            self.phase = 2
            self.shield_active = True
        else:
            self.phase = 3
            self.shield_active = False

        return dmg

    def set_shield_override(self, plates_held: bool):
        """Called when players/echoes stand on the temporal reactor plates."""
        self.shield_plates_active = plates_held

    def update_ai(
        self,
        dt: float,
        targets: List[Entity],
        obstacles: List[BoundingBox],
    ) -> Tuple[List[Dict], List[Dict]]:
        """
        Returns (spawned_projectiles, spawned_reinforcements).
        """
        self.hit_flash = max(0.0, self.hit_flash - dt)
        spawned_shots = []
        spawned_summons = []

        target = self.find_nearest_target(targets)
        if target:
            diff = target.position - self.position
            if diff.length_squared() > 1e-4:
                self.facing = diff.normalize()
                # Slow boss repositioning
                self.position += self.facing * self.speed * dt

        self.attack_timer -= dt
        self.summon_timer -= dt

        # Phase 1: Periodic 3-way aimed bursts
        if self.phase == 1:
            if self.attack_timer <= 0.0 and target:
                self.attack_timer = 1.4
                for spread in (-20, 0, 20):
                    dir_vec = self.facing.rotate(spread)
                    spawned_shots.append({
                        "x": self.position.x + dir_vec.x * 52.0,
                        "y": self.position.y + dir_vec.y * 52.0,
                        "dir_x": dir_vec.x,
                        "dir_y": dir_vec.y,
                        "speed": 360.0,
                        "damage": 12.0,
                        "is_enemy": True,
                        "life": 1.8,
                    })

            if self.summon_timer <= 0.0:
                self.summon_timer = 7.0
                # Spawn 1 drone flanker
                spawned_summons.append({
                    "type": "hunter",
                    "x": self.position.x + random.choice([-100, 100]),
                    "y": self.position.y + random.choice([-100, 100]),
                })

        # Phase 2: Shielded barrage + drone summons
        elif self.phase == 2:
            if self.attack_timer <= 0.0 and target:
                self.attack_timer = 1.1
                for spread in (-35, -15, 0, 15, 35):
                    dir_vec = self.facing.rotate(spread)
                    spawned_shots.append({
                        "x": self.position.x + dir_vec.x * 52.0,
                        "y": self.position.y + dir_vec.y * 52.0,
                        "dir_x": dir_vec.x,
                        "dir_y": dir_vec.y,
                        "speed": 380.0,
                        "damage": 10.0,
                        "is_enemy": True,
                        "life": 2.0,
                    })

            if self.summon_timer <= 0.0:
                self.summon_timer = 5.5
                spawned_summons.append({
                    "type": "hunter",
                    "x": self.position.x - 120,
                    "y": self.position.y,
                })

        # Phase 3: Overdrive spiral + high intensity
        elif self.phase == 3:
            self.speed = 50.0
            self.spiral_angle = (self.spiral_angle + 120.0 * dt) % 360.0

            if self.attack_timer <= 0.0:
                self.attack_timer = 0.28
                for arm in range(4):
                    ang = self.spiral_angle + (arm * 90.0)
                    dir_vec = Vec2(1, 0).rotate(ang)
                    spawned_shots.append({
                        "x": self.position.x + dir_vec.x * 50.0,
                        "y": self.position.y + dir_vec.y * 50.0,
                        "dir_x": dir_vec.x,
                        "dir_y": dir_vec.y,
                        "speed": 320.0,
                        "damage": 8.0,
                        "is_enemy": True,
                        "life": 2.2,
                    })

        self.position = resolve_circle_obstacles(self.position, self.radius, obstacles)
        return spawned_shots, spawned_summons

    def to_dict(self) -> dict:
        d = super().to_dict()
        d.update({
            "phase": self.phase,
            "shield": self.shield_active,
            "shield_down": self.shield_plates_active,
        })
        return d
