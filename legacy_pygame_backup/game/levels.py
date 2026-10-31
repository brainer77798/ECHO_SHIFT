"""
Campaign Level Definitions: The Training Vault, The Security Grid, and The Broken Core.
"""

from typing import List, Dict, Optional
from game.entities import Vec2, BoundingBox
from game.arena import PressurePlate, Door, EnergyShard
from game.enemies import HunterDrone, Sentry, ArmoredBrute, WardenBoss
from settings import SCREEN_WIDTH, SCREEN_HEIGHT


class LevelData:
    def __init__(
        self,
        index: int,
        name: str,
        subtitle: str,
        objective_text: str,
        arena_bounds: BoundingBox,
        walls: List[BoundingBox],
        plates: List[PressurePlate],
        doors: List[Door],
        shards: List[EnergyShard],
        initial_enemies: List[dict],
        player_spawns: List[Vec2],
        is_boss_level: bool = False,
    ):
        self.index = index
        self.name = name
        self.subtitle = subtitle
        self.objective_text = objective_text
        self.arena_bounds = arena_bounds
        self.walls = walls
        self.plates = plates
        self.doors = doors
        self.shards = shards
        self.initial_enemies = initial_enemies
        self.player_spawns = player_spawns
        self.is_boss_level = is_boss_level


def build_level(level_index: int) -> LevelData:
    """Builds and returns the structured LevelData for level 1, 2, or 3."""
    w = SCREEN_WIDTH
    h = SCREEN_HEIGHT

    # Outer arena boundary
    arena_bounds = BoundingBox(45, 80, w - 90, h - 130)

    if level_index == 1:
        # LEVEL 1: THE TRAINING VAULT
        # Teaches moving, shooting, and using an echo to hold a pressure plate to unlock the exit door.
        # Dividing wall with a security bulkhead (door) in the middle.
        mid_x = w // 2 - 15
        top_wall = BoundingBox(mid_x, 80, 30, 200)
        bot_wall = BoundingBox(mid_x, 380, 30, h - 130 - 300)

        # Bulkhead door in the opening between walls
        door = Door(x=mid_x - 5, y=280, width=40, height=100, linked_plate_ids=[101], door_id=201)

        # Pressure plate on the left side of the room
        plate = PressurePlate(x=220, y=300, width=54, height=54, plate_id=101, label="GATE LOCK")

        # Exit portal on the far right
        exit_door = Door(x=w - 110, y=h // 2 - 40, width=40, height=80, door_id=202, is_exit=True)

        # Enemies on right side of room
        enemies = [
            {"type": "hunter", "x": 800, "y": 250},
            {"type": "hunter", "x": 950, "y": 420},
            {"type": "hunter", "x": 1050, "y": 220},
        ]

        player_spawns = [
            Vec2(120, 260),
            Vec2(120, 320),
            Vec2(120, 380),
            Vec2(120, 440),
        ]

        return LevelData(
            index=1,
            name="LEVEL 1: THE TRAINING VAULT",
            subtitle="TEMPORAL REPLICATION INITIATIVE",
            objective_text="Record past actions with [E] to hold the pressure plate and unlock the bulkhead.",
            arena_bounds=arena_bounds,
            walls=[top_wall, bot_wall],
            plates=[plate],
            doors=[door, exit_door],
            shards=[],
            initial_enemies=enemies,
            player_spawns=player_spawns,
            is_boss_level=False,
        )

    elif level_index == 2:
        # LEVEL 2: THE SECURITY GRID
        # Introduces Sentries and Armored Brute, dual switches, and 3 energy shards.
        # Layout: central pillars and partitions creating tactical cover.
        pillar1 = BoundingBox(350, 200, 70, 120)
        pillar2 = BoundingBox(350, 420, 70, 120)
        pillar3 = BoundingBox(820, 200, 70, 120)
        pillar4 = BoundingBox(820, 420, 70, 120)

        # Security barrier across right transit corridor
        door = Door(x=700, y=280, width=30, height=180, linked_plate_ids=[102, 103], require_all_plates=True, door_id=203)

        plate1 = PressurePlate(x=240, y=160, width=50, height=50, plate_id=102, label="NODE A")
        plate2 = PressurePlate(x=240, y=520, width=50, height=50, plate_id=103, label="NODE B")

        # 3 Shards to collect
        shards = [
            EnergyShard(x=590, y=360, shard_id=301),
            EnergyShard(x=240, y=360, shard_id=302),
            EnergyShard(x=1020, y=360, shard_id=303),
        ]

        exit_door = Door(x=w - 110, y=h // 2 - 40, width=40, height=80, door_id=204, is_exit=True)

        enemies = [
            {"type": "hunter", "x": 600, "y": 200},
            {"type": "hunter", "x": 600, "y": 520},
            {"type": "sentry", "x": 980, "y": 180},
            {"type": "sentry", "x": 980, "y": 540},
            {"type": "brute", "x": 1050, "y": 360},
        ]

        player_spawns = [
            Vec2(120, 300),
            Vec2(120, 360),
            Vec2(120, 420),
            Vec2(160, 360),
        ]

        return LevelData(
            index=2,
            name="LEVEL 2: THE SECURITY GRID",
            subtitle="AUTOMATED DEFENSE CORRIDOR",
            objective_text="Trigger dual nodes with Echoes, collect 3 Energy Shards, and eliminate security.",
            arena_bounds=arena_bounds,
            walls=[pillar1, pillar2, pillar3, pillar4],
            plates=[plate1, plate2],
            doors=[door, exit_door],
            shards=shards,
            initial_enemies=enemies,
            player_spawns=player_spawns,
            is_boss_level=False,
        )

    else:
        # LEVEL 3: THE BROKEN CORE - Boss Level
        # Open circular/arena style with 4 corner reactor consoles.
        # Two temporal disruptor plates: holding either disrupts The Warden's Phase 2 temporal shield!
        corner_tl = BoundingBox(180, 140, 60, 60)
        corner_tr = BoundingBox(w - 240, 140, 60, 60)
        corner_bl = BoundingBox(180, h - 220, 60, 60)
        corner_br = BoundingBox(w - 240, h - 220, 60, 60)

        plate1 = PressurePlate(x=320, y=340, width=60, height=60, plate_id=104, label="DISRUPTOR 1")
        plate2 = PressurePlate(x=w - 380, y=340, width=60, height=60, plate_id=105, label="DISRUPTOR 2")

        enemies = [
            {"type": "warden", "x": w // 2, "y": h // 2},
        ]

        player_spawns = [
            Vec2(w // 2 - 120, h - 140),
            Vec2(w // 2 - 40, h - 140),
            Vec2(w // 2 + 40, h - 140),
            Vec2(w // 2 + 120, h - 140),
        ]

        return LevelData(
            index=3,
            name="LEVEL 3: THE BROKEN CORE",
            subtitle="TEMPORAL CONTAINMENT FACILITY",
            objective_text="DESTROY THE WARDEN. During Phase 2, hold the Temporal Disruptor plates with Echoes to breach its shield!",
            arena_bounds=arena_bounds,
            walls=[corner_tl, corner_tr, corner_bl, corner_br],
            plates=[plate1, plate2],
            doors=[],
            shards=[],
            initial_enemies=enemies,
            player_spawns=player_spawns,
            is_boss_level=True,
        )
