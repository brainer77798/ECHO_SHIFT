"""
Combat resolutions, projectile collisions, damage application, and single-award scoring.
"""

from typing import List, Dict, Tuple, Optional
from game.entities import Vec2, BoundingBox, distance_sq_point_to_segment
from game.player import Player
from game.enemies import BaseEnemy, HunterDrone, WardenBoss
from game.projectiles import Projectile, DangerZone
from game.collisions import circle_intersects_circle, circle_intersects_rect
from settings import PLAYER_RADIUS


class CombatSystem:
    @staticmethod
    def process_projectile_enemy_hits(
        projectiles: List[Projectile],
        enemies: List[BaseEnemy],
        players: Dict[int, Player],
    ) -> List[Dict]:
        """
        Check collisions between player/echo projectiles and enemies.
        Returns a list of combat events: [{'type': 'hit'/'kill', 'x': ..., 'y': ..., 'enemy': ..., 'killer': ...}]
        """
        events = []

        for proj in projectiles:
            if not proj.active or proj.is_enemy:
                continue

            for enemy in enemies:
                if not enemy.active:
                    continue

                # Continuous collision detection prevents high-speed bullet tunneling
                hit_dist_sq = (enemy.radius + proj.radius) ** 2
                if distance_sq_point_to_segment(enemy.position, proj.prev_position, proj.position) <= hit_dist_sq:
                    proj.active = False
                    hit_dir = proj.velocity.normalize() if proj.velocity.length_squared() > 0 else None
                    dmg_dealt = enemy.take_damage(proj.damage, hit_direction=hit_dir)

                    events.append({
                        "type": "enemy_hit",
                        "x": proj.position.x,
                        "y": proj.position.y,
                        "is_echo": proj.is_echo,
                        "damage": dmg_dealt,
                    })

                    # Single-award scoring
                    if not enemy.active and not enemy.has_awarded_score:
                        enemy.has_awarded_score = True
                        killer_player = players.get(proj.owner_id)
                        if killer_player:
                            killer_player.score += enemy.score_value
                            killer_player.kills += 1

                        events.append({
                            "type": "enemy_killed",
                            "x": enemy.position.x,
                            "y": enemy.position.y,
                            "score": enemy.score_value,
                            "owner_id": proj.owner_id,
                            "enemy_type": enemy.enemy_type,
                        })
                    break  # One hit per projectile

        return events

    @staticmethod
    def process_enemy_attacks_on_players(
        enemies: List[BaseEnemy],
        projectiles: List[Projectile],
        players: Dict[int, Player],
    ) -> List[Dict]:
        """
        Check enemy projectiles and contact damage against players.
        """
        events = []

        # 1. Enemy projectiles against players
        for proj in projectiles:
            if not proj.active or not proj.is_enemy:
                continue

            for player in players.values():
                if not player.active or player.is_downed:
                    continue

                hit_dist_sq = (player.radius + proj.radius) ** 2
                if distance_sq_point_to_segment(player.position, proj.prev_position, proj.position) <= hit_dist_sq:
                    proj.active = False
                    if player.take_damage(proj.damage):
                        events.append({
                            "type": "player_hit",
                            "player_id": player.id,
                            "damage": proj.damage,
                            "x": player.position.x,
                            "y": player.position.y,
                        })
                        if player.is_downed:
                            events.append({
                                "type": "player_downed",
                                "player_id": player.id,
                            })
                    break

        # 2. Contact damage from Hunter Drones
        for enemy in enemies:
            if not enemy.active or not isinstance(enemy, HunterDrone):
                continue

            if enemy.contact_cooldown > 0.0:
                continue

            for player in players.values():
                if not player.active or player.is_downed:
                    continue

                if circle_intersects_circle(enemy.position, enemy.radius, player.position, player.radius):
                    enemy.contact_cooldown = 0.8
                    if player.take_damage(12.0):
                        events.append({
                            "type": "player_hit",
                            "player_id": player.id,
                            "damage": 12.0,
                            "x": player.position.x,
                            "y": player.position.y,
                        })
                        if player.is_downed:
                            events.append({
                                "type": "player_downed",
                                "player_id": player.id,
                            })

        return events
