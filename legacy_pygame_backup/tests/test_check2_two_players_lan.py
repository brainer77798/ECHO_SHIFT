"""
Verification Suite - Check 2:
Two separate players can join the same LAN game, move independently, and create their own echoes.
"""

import os
import sys
import time
import socket
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.server_world import GameServer
from game.client_network import NetworkClient


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestCheck2TwoPlayersLAN(unittest.TestCase):

    def test_two_players_lan_independent_movement_and_echoes(self):
        """
        Verify that in a genuine local network session:
        1. Two separate human clients connect to the authoritative server.
        2. Both receive independent player IDs and distinct color assignments.
        3. Both clients move independently in different directions without desync.
        4. Both clients independently create their own Echoes.
        5. The server broadcasts authoritative snapshots with both players and both Echoes to all clients.
        """
        port = find_free_port()
        server = GameServer(host="127.0.0.1", port=port, level=1)
        server.start(background=True)

        client1 = NetworkClient()
        client2 = NetworkClient()

        try:
            # 1. Connect Client 1 and Client 2
            ok1 = client1.connect("127.0.0.1", port, player_name="PlayerAlpha")
            self.assertTrue(ok1, "Client 1 failed to connect to LAN server.")
            self.assertEqual(client1.player_id, 1)
            self.assertEqual(client1.color_index, 0)

            ok2 = client2.connect("127.0.0.1", port, player_name="PlayerBeta")
            self.assertTrue(ok2, "Client 2 failed to connect to LAN server.")
            self.assertEqual(client2.player_id, 2)
            self.assertEqual(client2.color_index, 1)

            # Wait for both players to appear in snapshots
            start_wait = time.time()
            snap1 = None
            snap2 = None
            while time.time() - start_wait < 2.0:
                snap1 = client1.get_snapshot()
                snap2 = client2.get_snapshot()
                if snap1 and snap2 and len(snap1.get("players", [])) == 2 and len(snap2.get("players", [])) == 2:
                    break
                time.sleep(0.04)

            self.assertIsNotNone(snap1)
            self.assertEqual(len(snap1["players"]), 2)
            self.assertEqual(len(snap2["players"]), 2)

            p1_start = next(p for p in snap1["players"] if p["id"] == 1)
            p2_start = next(p for p in snap1["players"] if p["id"] == 2)
            p1_init_x, p1_init_y = p1_start["x"], p1_start["y"]
            p2_init_x, p2_init_y = p2_start["x"], p2_start["y"]

            # 2. Independent movement:
            # Client 1 moves Right (mx = 1.0, my = 0.0)
            # Client 2 moves Down  (mx = 0.0, my = 1.0)
            # Send inputs continuously for ~0.8s to accumulate history for Echo creation
            move_start = time.time()
            while time.time() - move_start < 0.8:
                client1.send_input(mx=1.0, my=0.0, ax=1.0, ay=0.0, want_fire=False, want_dash=False, want_echo=False)
                client2.send_input(mx=0.0, my=1.0, ax=0.0, ay=1.0, want_fire=False, want_dash=False, want_echo=False)
                time.sleep(0.033)

            # Check snapshot after independent movement
            time.sleep(0.1)
            snap = client1.get_snapshot()
            p1_curr = next(p for p in snap["players"] if p["id"] == 1)
            p2_curr = next(p for p in snap["players"] if p["id"] == 2)

            # Client 1 moved Right: x increased, y approximately unchanged
            self.assertGreater(p1_curr["x"], p1_init_x + 30.0, "Player 1 should have moved significantly right.")
            self.assertAlmostEqual(p1_curr["y"], p1_init_y, delta=5.0, msg="Player 1 Y position should not change.")

            # Client 2 moved Down: y increased, x approximately unchanged
            self.assertGreater(p2_curr["y"], p2_init_y + 30.0, "Player 2 should have moved significantly down.")
            self.assertAlmostEqual(p2_curr["x"], p2_init_x, delta=5.0, msg="Player 2 X position should not change.")

            # 3. Both clients independently create their own Echoes
            # Client 1 creates an echo
            client1.send_input(mx=0.0, my=0.0, ax=1.0, ay=0.0, want_fire=False, want_dash=False, want_echo=True)
            time.sleep(0.08)

            # Client 2 creates an echo
            client2.send_input(mx=0.0, my=0.0, ax=0.0, ay=1.0, want_fire=False, want_dash=False, want_echo=True)
            time.sleep(0.08)

            # Wait for server snapshot containing both Echoes
            echoes_verified = False
            check_start = time.time()
            final_snap1 = None
            final_snap2 = None

            while time.time() - check_start < 2.0:
                final_snap1 = client1.get_snapshot()
                final_snap2 = client2.get_snapshot()
                if final_snap1 and final_snap2:
                    echoes = final_snap1.get("echoes", [])
                    owners = {e["owner"] for e in echoes}
                    if 1 in owners and 2 in owners:
                        echoes_verified = True
                        break
                time.sleep(0.04)

            self.assertTrue(echoes_verified, "Both Player 1 and Player 2 Echoes must exist simultaneously in the snapshot.")

            # Verify both clients see the exact same set of echoes
            self.assertEqual(len(final_snap1["echoes"]), len(final_snap2["echoes"]))
            owners1 = [e["owner"] for e in final_snap1["echoes"]]
            self.assertIn(1, owners1, "Player 1 echo missing from snapshot.")
            self.assertIn(2, owners1, "Player 2 echo missing from snapshot.")

        finally:
            client1.disconnect()
            client2.disconnect()
            server.stop()


if __name__ == "__main__":
    unittest.main()
