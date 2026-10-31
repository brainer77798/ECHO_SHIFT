"""
Player character logic, inputs, physics, dashing, weapons, and co-op states.
"""

from typing import Optional, Tuple, List
from game.entities import Entity, Vec2, BoundingBox, clamp, get_next_id
from game.echoes import ActionRecorder
from game.collisions import resolve_circle_obstacles
from settings import (
    PLAYER_RADIUS,
    PLAYER_SPEED,
    PLAYER_MAX_HEALTH,
    SHOT_COOLDOWN,
    DASH_DISTANCE,
    DASH_COOLDOWN,
    DASH_DURATION,
    ECHO_COOLDOWN,
    PLAYER_COLORS,
)


class Player(Entity):
    def __init__(
        self,
        x: float,
        y: float,
        player_id: int,
        name: str = "Player",
        color_index: int = 0,
    ):
        super().__init__(x, y, radius=PLAYER_RADIUS, entity_id=player_id)
        self.name = name
        self.color_index = color_index % len(PLAYER_COLORS)
        self.color = PLAYER_COLORS[self.color_index]

        self.health = PLAYER_MAX_HEALTH
        self.max_health = PLAYER_MAX_HEALTH
        self.score = 0
        self.kills = 0

        # Timers
        self.shot_cooldown_timer = 0.0
        self.dash_cooldown_timer = 0.0
        self.dash_timer = 0.0
        self.dash_direction = Vec2(1, 0)
        self.echo_cooldown_timer = 0.0
        self.invulnerable_timer = 0.0

        # Aim
        self.aim_direction = Vec2(1, 0)

        # Action recording for the Echo mechanic
        self.recorder = ActionRecorder()

        # Co-op Downed / Revive state
        self.is_downed = False
        self.revive_progress = 0.0  # 0.0 to 1.0
        self.respawn_timer = 0.0

    @property
    def is_dashing(self) -> bool:
        return self.dash_timer > 0.0

    @property
    def echo_ready(self) -> bool:
        return self.echo_cooldown_timer <= 0.0 and self.recorder.has_enough_history()

    def process_inputs(
        self,
        dt: float,
        move_x: float,
        move_y: float,
        aim_x: float,
        aim_y: float,
        want_fire: bool,
        want_dash: bool,
        obstacles: List[BoundingBox],
        sim_time: float,
    ) -> Tuple[bool, bool]:
        """
        Updates player state according to inputs and obstacles.
        Returns (did_fire, did_dash).
        """
        if self.is_downed:
            self.recorder.clear()
            return False, False

        # Decrement cooldown timers
        self.shot_cooldown_timer = max(0.0, self.shot_cooldown_timer - dt)
        self.dash_cooldown_timer = max(0.0, self.dash_cooldown_timer - dt)
        self.echo_cooldown_timer = max(0.0, self.echo_cooldown_timer - dt)
        self.invulnerable_timer = max(0.0, self.invulnerable_timer - dt)

        # Update Aim Direction
        aim = Vec2(aim_x, aim_y)
        if aim.length_squared() > 1e-4:
            self.aim_direction = aim.normalize()

        # Dash execution or normal movement
        did_dash = False
        if want_dash and self.dash_cooldown_timer <= 0.0 and not self.is_dashing:
            move_input = Vec2(move_x, move_y)
            if move_input.length_squared() > 1e-4:
                self.dash_direction = move_input.normalize()
            else:
                self.dash_direction = self.aim_direction.copy()

            self.dash_timer = DASH_DURATION
            self.dash_cooldown_timer = DASH_COOLDOWN
            self.invulnerable_timer = max(self.invulnerable_timer, DASH_DURATION)
            did_dash = True

        if self.is_dashing:
            self.dash_timer -= dt
            dash_speed = DASH_DISTANCE / DASH_DURATION
            self.velocity = self.dash_direction * dash_speed
            self.position += self.velocity * dt
        else:
            move_input = Vec2(move_x, move_y)
            if move_input.length_squared() > 1e-4:
                move_input = move_input.normalize()
                self.velocity = move_input * PLAYER_SPEED
                self.position += self.velocity * dt
            else:
                self.velocity = Vec2(0, 0)

        # Resolve collisions against walls & obstacles
        self.position = resolve_circle_obstacles(self.position, self.radius, obstacles)

        # Firing weapon
        did_fire = False
        if want_fire and self.shot_cooldown_timer <= 0.0:
            self.shot_cooldown_timer = SHOT_COOLDOWN
            did_fire = True

        # Continuously record actions into the 5-second action buffer
        self.recorder.record(
            sim_time=sim_time,
            x=self.position.x,
            y=self.position.y,
            aim_x=self.aim_direction.x,
            aim_y=self.aim_direction.y,
            fired=did_fire,
            dashing=self.is_dashing,
        )

        return did_fire, did_dash

    def take_damage(self, amount: float) -> bool:
        """Apply damage unless invulnerable. Returns True if damage was dealt."""
        if self.invulnerable_timer > 0.0 or self.is_downed:
            return False

        self.health = max(0, self.health - int(amount))
        self.invulnerable_timer = 0.35  # Brief immunity flash

        if self.health <= 0:
            self.is_downed = True
            self.respawn_timer = 8.0  # Co-op timed respawn or revive window
        return True

    def revive(self):
        self.is_downed = False
        self.health = int(self.max_health * 0.5)
        self.invulnerable_timer = 1.5
        self.revive_progress = 0.0

    def trigger_echo_cooldown(self):
        self.echo_cooldown_timer = ECHO_COOLDOWN

    def to_dict(self) -> dict:
        d = super().to_dict()
        d.update({
            "name": self.name,
            "color_index": self.color_index,
            "health": self.health,
            "max_health": self.max_health,
            "score": self.score,
            "aim_x": round(self.aim_direction.x, 2),
            "aim_y": round(self.aim_direction.y, 2),
            "is_dashing": self.is_dashing,
            "dash_cd": round(self.dash_cooldown_timer, 2),
            "echo_cd": round(self.echo_cooldown_timer, 2),
            "echo_ready": self.echo_ready,
            "is_downed": self.is_downed,
            "revive_p": round(self.revive_progress, 2),
            "invuln": self.invulnerable_timer > 0.0,
        })
        return d
