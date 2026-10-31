"""
Central Game World and authoritative physics/combat simulation.
"""

from typing import Dict, List, Optional, Tuple, Any
from game.entities import Vec2, BoundingBox
from game.player import Player
from game.echoes import EchoManager, Echo
from game.projectiles import Projectile, DangerZone
from game.arena import PressurePlate, Door, EnergyShard
from game.enemies import BaseEnemy, HunterDrone, Sentry, ArmoredBrute, WardenBoss
from game.combat import CombatSystem
from game.levels import LevelData, build_level
from game.collisions import circle_intersects_rect, circle_intersects_circle
from settings import SCREEN_WIDTH, SCREEN_HEIGHT


class GameWorld:
    STATE_RUNNING = "running"
    STATE_LEVEL_CLEAR = "level_clear"
    STATE_GAME_OVER = "game_over"
    STATE_VICTORY = "victory"

    def __init__(self, start_level: int = 1):
        self.sim_time = 0.0
        self.state = self.STATE_RUNNING
        self.level_index = start_level
        self.level_data: Optional[LevelData] = None

        self.players: Dict[int, Player] = {}
        self.echo_manager = EchoManager()
        self.enemies: List[BaseEnemy] = []
        self.projectiles: List[Projectile] = []
        self.danger_zones: List[DangerZone] = []

        self.plates: Dict[int, PressurePlate] = {}
        self.doors: Dict[int, Door] = {}
        self.shards: Dict[int, EnergyShard] = {}

        self.team_score = 0
        self.recent_events: List[Dict] = []
        self.transition_timer = 0.0
        self.pending_inputs: Dict[int, dict] = {}

        self.load_level(start_level)

    def load_level(self, index: int):
        self.level_index = index
        self.level_data = build_level(index)

        self.echo_manager.clear()
        self.projectiles.clear()
        self.danger_zones.clear()
        self.enemies.clear()
        self.pending_inputs.clear()

        self.plates = {p.id: p for p in self.level_data.plates}
        self.doors = {d.id: d for d in self.level_data.doors}
        self.shards = {s.id: s for s in self.level_data.shards}

        # Spawn initial enemies
        for edef in self.level_data.initial_enemies:
            etype = edef["type"]
            x, y = edef["x"], edef["y"]
            if etype == "hunter":
                self.enemies.append(HunterDrone(x, y))
            elif etype == "sentry":
                self.enemies.append(Sentry(x, y))
            elif etype == "brute":
                self.enemies.append(ArmoredBrute(x, y))
            elif etype == "warden":
                self.enemies.append(WardenBoss(x, y))

        # Position existing players at spawn points
        for idx, (p_id, player) in enumerate(self.players.items()):
            spawn = self.level_data.player_spawns[idx % len(self.level_data.player_spawns)]
            player.position = spawn.copy()
            player.health = player.max_health
            player.is_downed = False
            player.echo_cooldown_timer = 0.0
            player.dash_cooldown_timer = 0.0
            player.shot_cooldown_timer = 0.0
            player.recorder.clear()

        self.state = self.STATE_RUNNING
        self.transition_timer = 0.0

    def add_player(self, player_id: int, name: str = "Player", color_index: int = 0) -> Player:
        spawn_idx = len(self.players) % len(self.level_data.player_spawns)
        spawn_pos = self.level_data.player_spawns[spawn_idx]
        player = Player(spawn_pos.x, spawn_pos.y, player_id, name, color_index)
        self.players[player_id] = player
        return player

    def remove_player(self, player_id: int):
        if player_id in self.players:
            del self.players[player_id]
        if player_id in self.echo_manager.player_echoes:
            del self.echo_manager.player_echoes[player_id]

    def get_solid_obstacles(self) -> List[BoundingBox]:
        """Returns level boundary walls, interior pillars, and closed doors."""
        obs = []
        if self.level_data:
            # Level boundaries (4 bounding boxes around arena)
            ab = self.level_data.arena_bounds
            obs.append(BoundingBox(ab.x - 50, ab.y - 50, ab.width + 100, 50))  # Top
            obs.append(BoundingBox(ab.x - 50, ab.bottom, ab.width + 100, 50))   # Bottom
            obs.append(BoundingBox(ab.x - 50, ab.y, 50, ab.height))            # Left
            obs.append(BoundingBox(ab.right, ab.y, 50, ab.height))             # Right

            # Interior walls
            obs.extend(self.level_data.walls)

            # Closed doors
            for d in self.doors.values():
                door_box = d.current_obstacle_box
                if door_box:
                    obs.append(door_box)
        return obs

    def apply_player_input(
        self,
        player_id: int,
        move_x: float,
        move_y: float,
        aim_x: float,
        aim_y: float,
        want_fire: bool,
        want_dash: bool,
        want_echo: bool,
    ):
        self.pending_inputs[player_id] = {
            "move_x": move_x,
            "move_y": move_y,
            "aim_x": aim_x,
            "aim_y": aim_y,
            "want_fire": want_fire,
            "want_dash": want_dash,
            "want_echo": want_echo,
        }

    def update(self, dt: float):
        if self.state in (self.STATE_GAME_OVER, self.STATE_VICTORY):
            return

        self.sim_time += dt
        self.recent_events.clear()
        obstacles = self.get_solid_obstacles()

        # 0. Process player physics and input execution with delta time
        for p_id, player in list(self.players.items()):
            p_input = self.pending_inputs.get(p_id, {
                "move_x": 0.0,
                "move_y": 0.0,
                "aim_x": player.aim_direction.x,
                "aim_y": player.aim_direction.y,
                "want_fire": False,
                "want_dash": False,
                "want_echo": False,
            })

            did_fire, did_dash = player.process_inputs(
                dt=dt,
                move_x=p_input["move_x"],
                move_y=p_input["move_y"],
                aim_x=p_input["aim_x"],
                aim_y=p_input["aim_y"],
                want_fire=p_input["want_fire"],
                want_dash=p_input["want_dash"],
                obstacles=obstacles,
                sim_time=self.sim_time,
            )

            if did_fire:
                bullet_start = player.position + player.aim_direction * 22.0
                self.projectiles.append(
                    Projectile(
                        bullet_start.x,
                        bullet_start.y,
                        player.aim_direction.x,
                        player.aim_direction.y,
                        owner_id=player.id,
                        is_echo=False,
                    )
                )
                self.recent_events.append({"type": "sound", "name": "shoot", "x": player.position.x, "y": player.position.y})

            if did_dash:
                self.recent_events.append({"type": "sound", "name": "dash", "x": player.position.x, "y": player.position.y})

            if p_input.get("want_echo") and player.echo_ready:
                echo = self.echo_manager.spawn_echo(player.id, player.recorder)
                if echo:
                    player.trigger_echo_cooldown()
                    self.recent_events.append({"type": "sound", "name": "echo_spawn", "x": echo.position.x, "y": echo.position.y})
                    self.recent_events.append({"type": "fx", "name": "echo_spawn", "x": echo.position.x, "y": echo.position.y})

            # Consume single-trigger actions
            p_input["want_dash"] = False
            p_input["want_echo"] = False

        # 1. Update active echoes & gather echo projectiles
        echo_shots = self.echo_manager.update(dt)
        for s in echo_shots:
            self.projectiles.append(
                Projectile(
                    x=s["x"],
                    y=s["y"],
                    dir_x=s["dir_x"],
                    dir_y=s["dir_y"],
                    owner_id=s["owner_id"],
                    is_echo=True,
                )
            )
            self.recent_events.append({"type": "sound", "name": "echo_shoot", "x": s["x"], "y": s["y"]})

        # 2. Gather all interactive entities for pressure plates (Players + Holographic Echoes)
        all_switch_activators = list(self.players.values()) + self.echo_manager.get_all_echoes()

        # Update pressure plates
        plate_state_changed = False
        for p in self.plates.values():
            was_active = p.is_active
            p.update_occupancy(all_switch_activators)
            p.update_visuals(dt)
            if p.is_active != was_active:
                plate_state_changed = True
                self.recent_events.append({"type": "sound", "name": "switch_click", "x": p.center.x, "y": p.center.y})

        # Update doors
        shards_left = sum(1 for s in self.shards.values() if not s.collected)
        enemies_left = sum(1 for e in self.enemies if e.active)
        for d in self.doors.values():
            d.update_state(self.plates, shards_remaining=shards_left, enemies_remaining=enemies_left)
            d.update_visuals(dt)

        # 3. Collect energy shards when stepped on by a player
        for shard in self.shards.values():
            if not shard.collected:
                shard.update(dt)
                for p in self.players.values():
                    if not p.is_downed and p.position.distance_to(shard.position) <= (p.radius + shard.radius):
                        shard.collected = True
                        p.score += 250
                        self.team_score += 250
                        self.recent_events.append({"type": "sound", "name": "switch_click", "x": shard.position.x, "y": shard.position.y})
                        self.recent_events.append({"type": "fx", "name": "shard_collect", "x": shard.position.x, "y": shard.position.y})
                        break

        # 4. Target pool for enemy AI: living players + active echoes
        ai_targets = [p for p in self.players.values() if not p.is_downed] + self.echo_manager.get_all_echoes()

        # Check Boss temporal disruptor plates override in Level 3
        warden_boss = next((e for e in self.enemies if isinstance(e, WardenBoss)), None)
        if warden_boss:
            plates_held = any(p.is_active for p in self.plates.values())
            warden_boss.set_shield_override(plates_held)

        # 5. Update Enemy AI
        for enemy in self.enemies:
            if not enemy.active:
                continue

            if isinstance(enemy, WardenBoss):
                shots, summons = enemy.update_ai(dt, ai_targets, obstacles)
                for shot in shots:
                    self.projectiles.append(
                        Projectile(
                            x=shot["x"],
                            y=shot["y"],
                            dir_x=shot["dir_x"],
                            dir_y=shot["dir_y"],
                            owner_id=0,
                            is_enemy=True,
                            speed=shot.get("speed", 360.0),
                            damage=shot.get("damage", 12.0),
                            life=shot.get("life", 1.8),
                        )
                    )
                for s in summons:
                    self.enemies.append(HunterDrone(s["x"], s["y"]))
            else:
                shots = enemy.update_ai(dt, ai_targets, obstacles)
                for shot in shots:
                    self.projectiles.append(
                        Projectile(
                            x=shot["x"],
                            y=shot["y"],
                            dir_x=shot["dir_x"],
                            dir_y=shot["dir_y"],
                            owner_id=0,
                            is_enemy=True,
                            speed=shot.get("speed", 500.0),
                            damage=shot.get("damage", 18.0),
                            life=shot.get("life", 1.5),
                        )
                    )

        # 6. Update Projectiles and obstacle collisions
        for proj in self.projectiles:
            if not proj.active:
                continue
            proj.update(dt)

            # Check projectile collision with walls / closed doors
            for obs in obstacles:
                if circle_intersects_rect(proj.position, proj.radius, obs):
                    proj.active = False
                    break

        # 7. Combat resolutions
        combat_events = CombatSystem.process_projectile_enemy_hits(
            self.projectiles,
            self.enemies,
            self.players,
        )
        for ev in combat_events:
            self.recent_events.append(ev)
            if ev["type"] == "enemy_hit":
                self.recent_events.append({"type": "sound", "name": "hit", "x": ev["x"], "y": ev["y"]})
            elif ev["type"] == "enemy_killed":
                self.team_score += ev["score"]
                self.recent_events.append({"type": "sound", "name": "explosion", "x": ev["x"], "y": ev["y"]})
                self.recent_events.append({"type": "fx", "name": "explosion", "x": ev["x"], "y": ev["y"]})

        player_combat_events = CombatSystem.process_enemy_attacks_on_players(
            self.enemies,
            self.projectiles,
            self.players,
        )
        for ev in player_combat_events:
            self.recent_events.append(ev)
            if ev["type"] == "player_hit":
                self.recent_events.append({"type": "sound", "name": "hit", "x": ev["x"], "y": ev["y"]})

        # 8. Clean up inactive projectiles and defeated enemies
        self.projectiles = [p for p in self.projectiles if p.active]
        self.enemies = [e for e in self.enemies if e.active]

        # 9. Co-op Revive & Timed Respawn logic
        living_players = [p for p in self.players.values() if not p.is_downed]
        downed_players = [p for p in self.players.values() if p.is_downed]

        for dp in downed_players:
            # Check if any living teammate is nearby to revive
            revived_by_teammate = False
            for lp in living_players:
                if lp.position.distance_to(dp.position) <= 60.0:
                    dp.revive_progress += dt * 0.5  # 2.0s to revive
                    revived_by_teammate = True
                    if dp.revive_progress >= 1.0:
                        dp.revive()
                        self.recent_events.append({"type": "fx", "name": "revive", "x": dp.position.x, "y": dp.position.y})
                    break

            if not revived_by_teammate:
                dp.revive_progress = max(0.0, dp.revive_progress - dt * 0.2)
                # Timed respawn fallback in co-op
                dp.respawn_timer -= dt
                if dp.respawn_timer <= 0.0:
                    dp.revive()

        # Check Game Over: all players downed
        if self.players and all(p.is_downed for p in self.players.values()):
            self.state = self.STATE_GAME_OVER

        # 10. Check Level Progression / Exit Door / Boss Defeat
        if self.level_data:
            if self.level_data.is_boss_level:
                # Victory when Warden is defeated
                warden_alive = any(isinstance(e, WardenBoss) and e.active for e in self.enemies)
                if not warden_alive and not any(isinstance(e, WardenBoss) for e in self.enemies):
                    self.state = self.STATE_VICTORY
            else:
                # Non-boss levels: check if any player reached the unlocked exit door
                exit_door = next((d for d in self.doors.values() if d.is_exit), None)
                if exit_door and exit_door.is_open:
                    for p in self.players.values():
                        if not p.is_downed and circle_intersects_rect(p.position, p.radius, exit_door.box):
                            if self.level_index < 3:
                                self.load_level(self.level_index + 1)
                            else:
                                self.state = self.STATE_VICTORY
                            break

    def get_snapshot(self) -> dict:
        """Serializes current state into a compact dictionary for LAN network transmission or HUD."""
        return {
            "tick": int(self.sim_time * 30),
            "sim_time": round(self.sim_time, 2),
            "state": self.state,
            "level": self.level_index,
            "team_score": self.team_score,
            "players": [p.to_dict() for p in self.players.values()],
            "echoes": [e.to_dict() for e in self.echo_manager.get_all_echoes()],
            "enemies": [e.to_dict() for e in self.enemies],
            "projectiles": [p.to_dict() for p in self.projectiles],
            "plates": [p.to_dict() for p in self.plates.values()],
            "doors": [d.to_dict() for d in self.doors.values()],
            "shards": [s.to_dict() for s in self.shards.values()],
            "events": list(self.recent_events),
        }
