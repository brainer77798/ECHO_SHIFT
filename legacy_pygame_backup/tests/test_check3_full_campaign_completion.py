"""
Verification Suite - Check 3:
The game can be completed from the opening menu through the final boss without crashing.
"""

import os
import sys
import unittest

# Ensure headless dummy drivers are set before importing pygame
os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from main import EchoShiftGame
from game.game_world import GameWorld
from game.enemies import WardenBoss
from game.entities import Vec2


class TestCheck3FullCampaignCompletion(unittest.TestCase):

    def test_complete_campaign_from_menu_to_warden_defeat(self):
        """
        End-to-End Campaign Verification:
        1. Launches on Main Menu.
        2. Starts Solo campaign in Level 1 (The Training Vault).
        3. Uses Echo on pressure plate to unlock bulkhead, eliminates encounter, exits to Level 2.
        4. In Level 2 (The Security Grid), unlocks dual-node barrier with Echo, collects all 3 shards,
           defeats defense bots, and exits to Level 3.
        5. In Level 3 (The Broken Core), engages The Warden through Phase 1, breaches temporal shield
           in Phase 2 using Echo disruptor plate override, survives Phase 3 overdrive, and destroys the boss.
        6. Successfully displays Victory screen and cleanly returns to Main Menu with zero crashes.
        """
        game = EchoShiftGame()
        self.assertEqual(game.state, EchoShiftGame.STATE_MENU)
        game.draw()

        # ==================================================
        # LEVEL 1: THE TRAINING VAULT
        # ==================================================
        game.start_solo_game()
        self.assertEqual(game.state, EchoShiftGame.STATE_SOLO)
        self.assertEqual(game.solo_world.level_index, 1)

        world = game.solo_world
        player = world.players[game.solo_player_id]

        # Verify bulkhead is locked initially
        bulkhead = world.doors[201]
        self.assertFalse(bulkhead.is_open)

        # Record walking onto Plate 101 and standing there
        plate101 = world.plates[101]
        player.position = plate101.center.copy()
        for _ in range(15):
            world.update(0.05)

        # Project Echo to hold Plate 101
        world.apply_player_input(player.id, 0, 0, 1, 0, False, False, want_echo=True)
        world.update(0.05)

        # Move player away to the bulkhead
        player.position = Vec2(bulkhead.box.center.x + 30, bulkhead.box.center.y)
        world.update(0.3)  # Allow door to animate open
        self.assertTrue(bulkhead.is_open, "Bulkhead should be opened by Echo on Plate 101.")

        # Clear combat encounter on right side of Level 1
        for enemy in list(world.enemies):
            enemy.take_damage(999.0)
        world.update(0.1)

        # Exit door unlocks when enemies are cleared
        exit_door_l1 = world.doors[202]
        self.assertTrue(exit_door_l1.is_open, "Exit door should open once Level 1 encounter is cleared.")

        # Walk into exit door -> transitions to Level 2!
        player.position = exit_door_l1.box.center.copy()
        world.update(0.05)
        self.assertEqual(world.level_index, 2, "Game should have transitioned to Level 2.")
        game.draw()

        # ==================================================
        # LEVEL 2: THE SECURITY GRID
        # ==================================================
        self.assertEqual(world.level_index, 2)
        plate102 = world.plates[102]
        plate103 = world.plates[103]
        barrier = world.doors[203]

        # Use Echo to hold Node A (Plate 102) while Player stands on Node B (Plate 103)
        player.position = plate102.center.copy()
        for _ in range(15):
            world.update(0.05)
        world.apply_player_input(player.id, 0, 0, 1, 0, False, False, want_echo=True)
        world.update(0.05)

        # Move player to Node B (Plate 103)
        player.position = plate103.center.copy()
        world.update(0.3)
        self.assertTrue(barrier.is_open, "Dual-node barrier should open with Echo on Plate 102 and Player on 103.")

        # Collect all 3 Energy Shards
        for shard in world.shards.values():
            player.position = shard.position.copy()
            world.update(0.05)
        self.assertTrue(all(s.collected for s in world.shards.values()), "All 3 energy shards must be collected.")

        # Eliminate Level 2 defense automatons
        for enemy in list(world.enemies):
            enemy.take_damage(999.0)
        world.update(0.1)

        # Exit door opens
        exit_door_l2 = world.doors[204]
        self.assertTrue(exit_door_l2.is_open, "Exit door should open once shards and enemies in Level 2 are cleared.")

        # Walk into exit door -> transitions to Level 3!
        player.position = exit_door_l2.box.center.copy()
        world.update(0.05)
        self.assertEqual(world.level_index, 3, "Game should have transitioned to Level 3 (Boss Chamber).")
        game.draw()

        # ==================================================
        # LEVEL 3: THE BROKEN CORE - THE WARDEN BOSS
        # ==================================================
        self.assertEqual(world.level_index, 3)
        warden = next((e for e in world.enemies if isinstance(e, WardenBoss)), None)
        self.assertIsNotNone(warden, "The Warden boss must be present in Level 3.")
        self.assertEqual(warden.phase, 1)

        # Phase 1: Damage boss down to Phase 2 threshold
        warden.take_damage(35.0)
        world.update(0.05)
        self.assertEqual(warden.phase, 2, "Warden should transition to Phase 2.")
        self.assertTrue(warden.shield_active, "Warden shield must be active in Phase 2.")

        # Confirm temporal shield blocks attacks
        dmg = warden.take_damage(10.0)
        self.assertEqual(dmg, 0.0, "Attacks must be blocked while temporal shield is active.")

        # Hold Temporal Disruptor plate (Plate 104) with an Echo
        plate104 = world.plates[104]
        player.position = plate104.center.copy()
        for _ in range(15):
            world.update(0.05)
        world.apply_player_input(player.id, 0, 0, 1, 0, False, False, want_echo=True)
        world.update(0.05)
        self.assertTrue(warden.shield_plates_active, "Temporal shield must be disrupted while plate is held.")

        # Damage boss down to Phase 3 overdrive threshold
        warden.take_damage(25.0)
        world.update(0.05)
        self.assertEqual(warden.phase, 3, "Warden should transition to Phase 3 Overdrive.")
        self.assertFalse(warden.shield_active, "Shield must be permanently dropped in Phase 3.")

        # Final blow: Destroy The Warden!
        warden.take_damage(999.0)
        world.update(0.1)

        # Verify simulation victory
        self.assertEqual(world.state, GameWorld.STATE_VICTORY, "World must transition to STATE_VICTORY upon boss defeat.")

        # Step game loop to update GUI state
        game.update(0.05)
        self.assertEqual(game.state, EchoShiftGame.STATE_VICTORY, "GUI should transition to STATE_VICTORY overlay.")

        # Render Victory Screen without crashing
        game.draw()

        # Return cleanly to Main Menu
        game.return_to_main_menu()
        self.assertEqual(game.state, EchoShiftGame.STATE_MENU, "Game should return cleanly to STATE_MENU.")
        game.draw()


if __name__ == "__main__":
    unittest.main()
