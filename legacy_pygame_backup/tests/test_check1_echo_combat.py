"""
Verification Suite - Check 1:
Echoes actually replay your recorded attacks and can destroy enemies.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.entities import Vec2
from game.game_world import GameWorld
from game.enemies import HunterDrone
from settings import RECORDING_SECONDS


class TestCheck1EchoCombat(unittest.TestCase):

    def test_echo_replays_attacks_and_destroys_enemy(self):
        """
        Verify that an Echo:
        1. Accurately records player aiming and firing actions.
        2. Replays the recorded attacks chronologically in the recorded direction.
        3. Fires real projectiles that deal damage to an enemy.
        4. Successfully destroys the enemy.
        5. Awards score and kill credit to the player.
        """
        world = GameWorld(start_level=1)
        player = world.add_player(player_id=1, name="Operative_1")

        # Clear existing initial level enemies to isolate our test target
        world.enemies.clear()

        # 1. Player at (100, 300) records aiming right and firing shots (no enemies yet)
        player.position = Vec2(100.0, 300.0)
        t = 0.0
        dt = 0.05
        while t < 1.0:
            world.apply_player_input(
                player_id=1,
                move_x=0.0,
                move_y=0.0,
                aim_x=1.0,  # Aiming directly right
                aim_y=0.0,
                want_fire=(abs(t - 0.2) < 0.03 or abs(t - 0.5) < 0.03),
                want_dash=False,
                want_echo=False,
            )
            world.update(dt)
            t += dt

        # Move live player far away to (100, 600) so only the Echo can interact
        player.position = Vec2(100.0, 600.0)
        world.projectiles.clear()  # Clear initial player bullets

        # Now spawn target drone directly in the Echo's line of fire (260, 300)
        drone = HunterDrone(x=260.0, y=300.0)
        drone.health = 1.0
        world.enemies.append(drone)

        initial_score = player.score
        initial_kills = player.kills

        # 2. Player projects an Echo of the recorded action
        world.apply_player_input(
            player_id=1,
            move_x=0.0,
            move_y=0.0,
            aim_x=0.0,
            aim_y=1.0,  # Live player is aiming down, NOT right!
            want_fire=False,
            want_dash=False,
            want_echo=True,  # Spawn Echo!
        )
        world.update(dt)

        # Verify Echo spawned
        echoes = world.echo_manager.get_echoes_for_player(1)
        self.assertEqual(len(echoes), 1)
        echo = echoes[0]
        self.assertEqual(echo.owner_id, 1)

        # 3. Step simulation while Echo replays its recorded sequence
        enemy_destroyed = False
        sim_steps = 0
        while sim_steps < 60 and not enemy_destroyed:
            world.update(0.04)
            sim_steps += 1
            if drone not in world.enemies:
                enemy_destroyed = True

        # 4. Verify the Echo's replayed shots destroyed the drone!
        self.assertTrue(enemy_destroyed, "Drone was not destroyed by the Echo's replayed projectiles!")
        self.assertFalse(drone.active, "Drone should be marked inactive after destruction.")

        # 5. Verify the player was credited with the kill and score
        self.assertGreater(player.score, initial_score, "Player did not receive score from Echo kill!")
        self.assertEqual(player.kills, initial_kills + 1, "Player kill count was not incremented by Echo kill!")

    def test_echo_destroys_full_health_enemy_with_multiple_shots(self):
        """Verify an Echo firing multiple replayed shots can eliminate a full-health enemy."""
        world = GameWorld(start_level=1)
        player = world.add_player(player_id=1, name="Operative_1")
        world.enemies.clear()

        # Player records continuous rapid fire across 1.0s (fires ~5-6 shots at 0.18s cooldown)
        player.position = Vec2(150.0, 300.0)
        dt = 0.05
        t = 0.0
        while t < 1.0:
            world.apply_player_input(
                player_id=1,
                move_x=0.0,
                move_y=0.0,
                aim_x=1.0,
                aim_y=0.0,
                want_fire=True,
                want_dash=False,
                want_echo=False,
            )
            world.update(dt)
            t += dt

        # Move player away and clear old projectiles
        player.position = Vec2(150.0, 600.0)
        world.projectiles.clear()

        # Place a fresh full-health Drone (health = 2.0) in line of fire
        drone = HunterDrone(x=280.0, y=300.0)
        drone.health = 2.0
        world.enemies.append(drone)

        # Spawn Echo
        world.apply_player_input(1, 0, 0, 0, 1, False, False, want_echo=True)
        world.update(dt)

        # Step simulation to allow Echo shots to hit and destroy
        for _ in range(50):
            world.update(0.04)
            if drone not in world.enemies:
                break

        self.assertNotIn(drone, world.enemies, "Full-health drone should be destroyed by multiple Echo shots.")


if __name__ == "__main__":
    unittest.main()
