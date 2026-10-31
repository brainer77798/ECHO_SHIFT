"""
Headless runtime test for the Pygame loop, menus, solo play, and rendering pipelines.
"""

import os
import sys
import unittest

# Configure headless SDL dummy drivers before importing pygame
os.environ["SDL_VIDEODRIVER"] = "dummy"
os.environ["SDL_AUDIODRIVER"] = "dummy"

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import pygame
from main import EchoShiftGame


class TestHeadlessGameLoop(unittest.TestCase):

    def test_full_game_lifecycle_headless(self):
        """
        Verify the graphical game client initializes, renders menus,
        executes solo gameplay with the echo mechanic, and cleans up cleanly.
        """
        game = EchoShiftGame()
        self.assertEqual(game.state, EchoShiftGame.STATE_MENU)

        # 1. Simulate Main Menu rendering
        game.draw()

        # 2. Start Solo Mode
        game.start_solo_game()
        self.assertEqual(game.state, EchoShiftGame.STATE_SOLO)
        self.assertIsNotNone(game.solo_world)

        # 3. Simulate 60 frames of active gameplay (approx 1 second)
        dt = 1.0 / 60.0
        for frame in range(60):
            # Advance simulation time
            game.solo_world.apply_player_input(
                player_id=game.solo_player_id,
                move_x=1.0,
                move_y=0.0,
                aim_x=1.0,
                aim_y=0.0,
                want_fire=(frame % 10 == 0),
                want_dash=(frame == 20),
                want_echo=(frame == 40),
            )
            game.solo_world.update(dt)
            game.draw()

        # Also test game.update() call
        game.update(dt)

        player = game.solo_world.players[game.solo_player_id]
        self.assertGreater(player.position.x, 120.0)  # Has moved right
        self.assertGreater(len(game.solo_world.projectiles), 0)  # Has fired projectiles

        # 4. Test Pause Menu
        game.switch_state(EchoShiftGame.STATE_PAUSED)
        game.draw()
        game.resume_game()
        self.assertEqual(game.state, EchoShiftGame.STATE_SOLO)

        # 5. Return to Main Menu and Quit
        game.return_to_main_menu()
        self.assertEqual(game.state, EchoShiftGame.STATE_MENU)
        self.assertIsNone(game.solo_world)


if __name__ == "__main__":
    unittest.main()
