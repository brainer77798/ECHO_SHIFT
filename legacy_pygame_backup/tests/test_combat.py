"""
Unit tests for combat, damage formulas, echo projectiles, and boss shield mechanics.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.entities import Vec2
from game.player import Player
from game.projectiles import Projectile
from game.enemies import HunterDrone, Sentry, ArmoredBrute, WardenBoss
from game.combat import CombatSystem
from settings import PLAYER_SHOT_DAMAGE, ECHO_DAMAGE_MULTIPLIER


class TestCombat(unittest.TestCase):

    def test_echo_damage_scaling(self):
        """Verify echo projectiles deal approximately 50-65% damage of player shots."""
        player_shot = Projectile(100, 100, 1, 0, owner_id=1, is_echo=False)
        echo_shot = Projectile(100, 100, 1, 0, owner_id=1, is_echo=True)

        self.assertEqual(player_shot.damage, PLAYER_SHOT_DAMAGE)
        expected_echo_dmg = PLAYER_SHOT_DAMAGE * ECHO_DAMAGE_MULTIPLIER
        self.assertAlmostEqual(echo_shot.damage, expected_echo_dmg, places=2)
        self.assertGreaterEqual(echo_shot.damage, 0.50 * PLAYER_SHOT_DAMAGE)
        self.assertLessEqual(echo_shot.damage, 0.65 * PLAYER_SHOT_DAMAGE)

    def test_armored_brute_directional_shield(self):
        """Verify frontal attacks to brute are reduced, while flanking/rear attacks deal full damage."""
        brute = ArmoredBrute(200, 200)
        brute.facing = Vec2(1, 0)  # Facing right (+x)

        # Shot incoming from right moving left (-x) strikes the front shield
        front_shot_dir = Vec2(-1, 0)
        taken_front = brute.take_damage(10.0, hit_direction=front_shot_dir)
        self.assertLess(taken_front, 5.0)  # Heavy reduction

        # Shot incoming from left moving right (+x) strikes the exposed back
        rear_shot_dir = Vec2(1, 0)
        taken_rear = brute.take_damage(5.0, hit_direction=rear_shot_dir)
        self.assertEqual(taken_rear, 5.0)  # Full damage

    def test_warden_boss_phases_and_shield(self):
        """Verify The Warden's Phase 2 temporal shield and disruptor plate vulnerability."""
        warden = WardenBoss(300, 300)
        self.assertEqual(warden.phase, 1)

        # Damage down to phase 2 threshold (<= 60% HP)
        warden.take_damage(35.0)
        self.assertEqual(warden.phase, 2)
        self.assertTrue(warden.shield_active)

        # Attack while shield plates are not held -> takes 0 damage
        warden.set_shield_override(plates_held=False)
        dmg = warden.take_damage(10.0)
        self.assertEqual(dmg, 0.0)

        # Disruptor plates held by echo or player -> temporal shield disrupted!
        warden.set_shield_override(plates_held=True)
        dmg = warden.take_damage(10.0)
        self.assertEqual(dmg, 10.0)


if __name__ == "__main__":
    unittest.main()
