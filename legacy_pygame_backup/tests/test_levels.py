"""
Unit tests for campaign levels, doors, pressure plates, and objectives.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.game_world import GameWorld
from game.arena import PressurePlate
from game.echoes import ActionRecorder
from game.enemies import WardenBoss


class TestLevels(unittest.TestCase):

    def test_level_1_door_opens_with_plate(self):
        """Verify Level 1 bulkhead door unlocks when pressure plate is triggered."""
        world = GameWorld(start_level=1)
        player = world.add_player(1, "Player 1")

        plate = list(world.plates.values())[0]
        bulkhead = world.doors[201]

        # Initially door is closed
        bulkhead.update_state(world.plates)
        self.assertFalse(bulkhead.is_open)

        # Move player onto the plate
        player.position = plate.center.copy()
        world.update(0.1)

        self.assertTrue(plate.is_active)
        self.assertTrue(bulkhead.is_open)

    def test_echo_holds_pressure_plate_unlocking_door(self):
        """
        Critical Game Hook:
        Verify an echo standing on a pressure plate keeps the door open while the player walks away!
        """
        world = GameWorld(start_level=1)
        player = world.add_player(1, "Player 1")
        plate = list(world.plates.values())[0]
        bulkhead = world.doors[201]

        # Record walking onto the plate and standing there
        recorder = ActionRecorder()
        recorder.record(0.0, 100, 100, 1, 0, False)
        recorder.record(0.5, plate.center.x, plate.center.y, 1, 0, False)
        recorder.record(1.0, plate.center.x, plate.center.y, 1, 0, False)

        echo = world.echo_manager.spawn_echo(player.id, recorder, hold_time=3.0)
        self.assertIsNotNone(echo)

        # Move real player far away from the switch
        player.position.x = 800
        player.position.y = 500

        # Advance world: Echo replays to the plate
        world.update(1.1)

        # Echo has finished replay and is holding the plate position!
        self.assertEqual(echo.state, "holding")
        self.assertTrue(plate.is_active)
        self.assertTrue(bulkhead.is_open)

    def test_level_progression_to_victory(self):
        """Verify transitions across levels and victory state on defeating the Warden."""
        world = GameWorld(start_level=3)
        player = world.add_player(1, "Tester")

        # Find Warden boss in level 3
        boss = next(e for e in world.enemies if isinstance(e, WardenBoss))
        self.assertIsNotNone(boss)

        # Defeat the boss
        boss.take_damage(9999.0)
        world.update(0.1)

        self.assertEqual(world.state, GameWorld.STATE_VICTORY)


if __name__ == "__main__":
    unittest.main()
