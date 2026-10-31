"""
Automated unit tests for the Echo System.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.echoes import ActionRecorder, Echo, EchoManager, PlayerActionSample
from settings import RECORDING_SECONDS, MAX_ECHOES_PER_PLAYER, ECHO_POST_REPLAY_HOLD_TIME


class TestEchoSystem(unittest.TestCase):

    def test_recorder_duration_and_bounding(self):
        """Verify action recording remains bounded in memory to ~5 seconds."""
        recorder = ActionRecorder(max_duration=RECORDING_SECONDS)

        # Simulate 10 seconds of recording at 25Hz (dt=0.04s)
        t = 0.0
        while t <= 10.0:
            recorder.record(
                sim_time=t,
                x=100.0 + t * 10,
                y=100.0,
                aim_x=1.0,
                aim_y=0.0,
                fired=(abs(t - 8.0) < 0.02),
            )
            t += 0.04

        self.assertTrue(recorder.has_enough_history())
        duration = recorder.get_duration()
        self.assertLessEqual(duration, RECORDING_SECONDS + 0.1)
        self.assertGreaterEqual(duration, RECORDING_SECONDS - 0.1)

        # Verify samples are strictly ascending in time
        for i in range(1, len(recorder.samples)):
            self.assertGreater(recorder.samples[i].t, recorder.samples[i - 1].t)

    def test_has_enough_history(self):
        """Verify echo cannot be created without sufficient history (>=0.5s)."""
        recorder = ActionRecorder()
        self.assertFalse(recorder.has_enough_history())

        recorder.record(0.0, 100, 100, 1, 0, False)
        recorder.record(0.2, 110, 100, 1, 0, False)
        self.assertFalse(recorder.has_enough_history(min_duration=0.5))

        recorder.record(0.6, 120, 100, 1, 0, False)
        self.assertTrue(recorder.has_enough_history(min_duration=0.5))

    def test_echo_replay_route_and_interpolation(self):
        """Verify that playback faithfully reproduces the recorded trajectory."""
        samples = [
            PlayerActionSample(t=0.0, x=100.0, y=100.0, aim_x=1.0, aim_y=0.0, fired=False),
            PlayerActionSample(t=1.0, x=200.0, y=100.0, aim_x=1.0, aim_y=0.0, fired=False),
            PlayerActionSample(t=2.0, x=200.0, y=300.0, aim_x=0.0, aim_y=1.0, fired=False),
        ]
        echo = Echo(owner_id=1, samples=samples, hold_time=2.0)

        # At t = 0.0: initial position
        self.assertEqual(echo.position.x, 100.0)
        self.assertEqual(echo.position.y, 100.0)

        # Advance to t = 0.5: should be midpoint (150, 100)
        echo.update(0.5)
        self.assertAlmostEqual(echo.position.x, 150.0, places=1)
        self.assertAlmostEqual(echo.position.y, 100.0, places=1)

        # Advance to t = 1.5: should be (200, 200)
        echo.update(1.0)
        self.assertAlmostEqual(echo.position.x, 200.0, places=1)
        self.assertAlmostEqual(echo.position.y, 200.0, places=1)

        # Advance past t = 2.0: should reach end (200, 300) and switch to HOLDING
        echo.update(0.6)
        self.assertEqual(echo.state, Echo.STATE_HOLDING)
        self.assertAlmostEqual(echo.position.x, 200.0, places=1)
        self.assertAlmostEqual(echo.position.y, 300.0, places=1)

    def test_echo_firing_events_reproduced(self):
        """Verify recorded shots are emitted exactly once at the recorded time."""
        samples = [
            PlayerActionSample(t=0.0, x=50.0, y=50.0, aim_x=1.0, aim_y=0.0, fired=False),
            PlayerActionSample(t=1.0, x=60.0, y=50.0, aim_x=0.0, aim_y=-1.0, fired=True),
            PlayerActionSample(t=2.0, x=70.0, y=50.0, aim_x=1.0, aim_y=0.0, fired=False),
        ]
        echo = Echo(owner_id=1, samples=samples, hold_time=1.0)

        # Update before firing time (t = 0.5) -> no shots
        shots = echo.update(0.5)
        self.assertEqual(len(shots), 0)

        # Update crossing t = 1.0 -> exactly 1 shot
        shots = echo.update(0.6)
        self.assertEqual(len(shots), 1)
        self.assertAlmostEqual(shots[0]["dir_y"], -1.0, places=2)

        # Update further -> no duplicate shots
        shots = echo.update(0.5)
        self.assertEqual(len(shots), 0)

    def test_echo_limit_per_player(self):
        """Verify that each player has at most 2 active echoes and oldest is replaced."""
        manager = EchoManager(max_per_player=MAX_ECHOES_PER_PLAYER)

        def make_recorder(offset):
            r = ActionRecorder()
            r.record(0.0, offset, 0, 1, 0, False)
            r.record(1.0, offset + 10, 0, 1, 0, False)
            return r

        e1 = manager.spawn_echo(player_id=1, recorder=make_recorder(100))
        self.assertIsNotNone(e1)
        self.assertEqual(len(manager.get_echoes_for_player(1)), 1)

        e2 = manager.spawn_echo(player_id=1, recorder=make_recorder(200))
        self.assertIsNotNone(e2)
        self.assertEqual(len(manager.get_echoes_for_player(1)), 2)

        # Spawning a 3rd should replace e1
        e3 = manager.spawn_echo(player_id=1, recorder=make_recorder(300))
        self.assertIsNotNone(e3)
        self.assertEqual(len(manager.get_echoes_for_player(1)), 2)
        self.assertFalse(e1.active)
        self.assertIn(e2, manager.get_echoes_for_player(1))
        self.assertIn(e3, manager.get_echoes_for_player(1))

    def test_echo_post_replay_hold_and_expiration(self):
        """Verify that echo holds its position then expires and deactivates."""
        samples = [
            PlayerActionSample(t=0.0, x=10, y=10, aim_x=1, aim_y=0, fired=False),
            PlayerActionSample(t=0.5, x=20, y=10, aim_x=1, aim_y=0, fired=False),
        ]
        echo = Echo(owner_id=1, samples=samples, hold_time=1.5)

        # Replay finishes at t=0.5s
        echo.update(0.6)
        self.assertEqual(echo.state, Echo.STATE_HOLDING)
        self.assertTrue(echo.active)

        # Advance hold time partway
        echo.update(1.0)
        self.assertEqual(echo.state, Echo.STATE_HOLDING)
        self.assertTrue(echo.active)

        # Advance remaining hold time
        echo.update(0.6)
        self.assertEqual(echo.state, Echo.STATE_EXPIRED)
        self.assertFalse(echo.active)

    def test_independent_echoes_for_multiple_players(self):
        """Verify multiplayer echo independence."""
        manager = EchoManager(max_per_player=2)

        r1 = ActionRecorder()
        r1.record(0.0, 0, 0, 1, 0, False)
        r1.record(1.0, 10, 0, 1, 0, False)

        r2 = ActionRecorder()
        r2.record(0.0, 50, 50, 0, 1, False)
        r2.record(1.0, 50, 60, 0, 1, False)

        p1_echo = manager.spawn_echo(player_id=1, recorder=r1)
        p2_echo = manager.spawn_echo(player_id=2, recorder=r2)

        self.assertEqual(len(manager.get_echoes_for_player(1)), 1)
        self.assertEqual(len(manager.get_echoes_for_player(2)), 1)
        self.assertEqual(len(manager.get_all_echoes()), 2)
        self.assertEqual(p1_echo.owner_id, 1)
        self.assertEqual(p2_echo.owner_id, 2)


if __name__ == "__main__":
    unittest.main()
