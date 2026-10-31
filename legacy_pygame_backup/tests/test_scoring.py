"""
Unit tests for scoring awards and duplicate prevention.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.entities import Vec2
from game.player import Player
from game.enemies import HunterDrone
from game.projectiles import Projectile
from game.combat import CombatSystem


class TestScoring(unittest.TestCase):

    def test_single_award_scoring(self):
        """Verify an enemy cannot award points more than once upon destruction."""
        player = Player(100, 100, player_id=1)
        players = {1: player}
        enemy = HunterDrone(150, 100)
        enemy.health = 1.0

        # Projectile 1 strikes and defeats the enemy
        p1 = Projectile(150, 100, 1, 0, owner_id=1, damage=2.0)
        # Projectile 2 arrives on same/subsequent frame
        p2 = Projectile(150, 100, 1, 0, owner_id=1, damage=2.0)

        events1 = CombatSystem.process_projectile_enemy_hits([p1], [enemy], players)
        self.assertEqual(player.score, enemy.score_value)
        self.assertEqual(player.kills, 1)

        # Processing again with second projectile must NOT award points again
        events2 = CombatSystem.process_projectile_enemy_hits([p2], [enemy], players)
        self.assertEqual(player.score, enemy.score_value)
        self.assertEqual(player.kills, 1)


if __name__ == "__main__":
    unittest.main()
