"""
Visual effects, particle systems, glow passes, and sci-fi rendering helpers.
"""

import math
import random
from typing import List, Tuple
import pygame
from settings import (
    PLAYER_COLOR,
    ECHO_COLOR,
    ENEMY_COLOR,
    WHITE,
    MUTED,
)


class Particle:
    __slots__ = ("x", "y", "vx", "vy", "color", "radius", "life", "max_life")

    def __init__(self, x: float, y: float, vx: float, vy: float, color: tuple, radius: float, life: float):
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
        self.color = color
        self.radius = radius
        self.life = life
        self.max_life = life

    def update(self, dt: float) -> bool:
        self.x += self.vx * dt
        self.y += self.vy * dt
        self.life -= dt
        return self.life > 0.0


class ParticleSystem:
    def __init__(self):
        self.particles: List[Particle] = []

    def emit_sparks(self, x: float, y: float, color: tuple, count: int = 10, speed: float = 120.0):
        for _ in range(count):
            ang = random.uniform(0, 2 * math.pi)
            spd = random.uniform(speed * 0.4, speed)
            vx = math.cos(ang) * spd
            vy = math.sin(ang) * spd
            life = random.uniform(0.15, 0.35)
            self.particles.append(Particle(x, y, vx, vy, color, radius=random.uniform(2.0, 3.5), life=life))

    def emit_explosion(self, x: float, y: float, count: int = 25):
        for _ in range(count):
            ang = random.uniform(0, 2 * math.pi)
            spd = random.uniform(40.0, 220.0)
            col = random.choice([ENEMY_COLOR, (255, 160, 60), WHITE])
            self.particles.append(
                Particle(
                    x,
                    y,
                    math.cos(ang) * spd,
                    math.sin(ang) * spd,
                    col,
                    radius=random.uniform(2.5, 5.0),
                    life=random.uniform(0.25, 0.55),
                )
            )

    def emit_warp_spiral(self, x: float, y: float, color: tuple = ECHO_COLOR, count: int = 16):
        for i in range(count):
            ang = (i / count) * 2 * math.pi
            spd = 90.0
            self.particles.append(
                Particle(
                    x,
                    y,
                    math.cos(ang) * spd,
                    math.sin(ang) * spd,
                    color,
                    radius=2.5,
                    life=0.30,
                )
            )

    def update(self, dt: float):
        self.particles = [p for p in self.particles if p.update(dt)]

    def draw(self, surface: pygame.Surface):
        for p in self.particles:
            ratio = max(0.0, p.life / p.max_life)
            r = max(1, int(p.radius * ratio))
            pygame.draw.circle(surface, p.color, (round(p.x), round(p.y)), r)


def draw_glow(surface: pygame.Surface, center: tuple, color: tuple, radius: float, layers: int = 2):
    """Draw lightweight layered glow without heavy performance overhead."""
    cx, cy = int(center[0]), int(center[1])
    rad = int(radius)
    for i in range(layers, 0, -1):
        mult = 0.25 / i
        glow_col = tuple(min(255, int(c * mult)) for c in color)
        pygame.draw.circle(surface, glow_col, (cx, cy), rad + i * 4)


def draw_hologram_echo(
    surface: pygame.Surface,
    pos: tuple,
    facing: tuple,
    alpha: float = 1.0,
    radius: float = 16.0,
    is_holding: bool = False,
    owner_color: tuple = None,
):
    """
    Renders the temporal Echo as an electric violet hologram with scanline ripples
    and pointer indicating aim.
    """
    cx, cy = int(pos[0]), int(pos[1])
    r = int(radius)

    # Outer temporal pulse ring
    pulse_col = tuple(int(c * alpha * 0.4) for c in ECHO_COLOR)
    pygame.draw.circle(surface, pulse_col, (cx, cy), r + 6, 1)

    # Hologram body
    body_col = tuple(int(c * alpha * 0.8) for c in ECHO_COLOR)
    pygame.draw.circle(surface, (25, 15, 50), (cx, cy), r)
    pygame.draw.circle(surface, body_col, (cx, cy), r, 2)

    # Owner identity accent core
    if owner_color:
        accent_col = tuple(int(c * alpha * 0.7) for c in owner_color)
        pygame.draw.circle(surface, accent_col, (cx, cy), 6, 1)

    # Scanlines across hologram
    for y_off in range(-r + 4, r, 5):
        span = int(math.sqrt(max(0, r * r - y_off * y_off)))
        line_col = tuple(int(c * alpha * 0.6) for c in ECHO_COLOR)
        pygame.draw.line(surface, line_col, (cx - span + 2, cy + y_off), (cx + span - 2, cy + y_off), 1)

    # Aim pointer
    fx, fy = facing[0], facing[1]
    tip_x = cx + fx * (r + 10)
    tip_y = cy + fy * (r + 10)
    pointer_col = owner_color if owner_color else (200, 180, 255)
    pygame.draw.line(surface, pointer_col, (cx, cy), (round(tip_x), round(tip_y)), 2)

    # Status indicator if holding a position
    if is_holding:
        pygame.draw.circle(surface, (230, 200, 255), (cx, cy), 3)
