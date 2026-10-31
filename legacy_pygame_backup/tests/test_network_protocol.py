"""
Unit and integration tests for network protocol, framing, validation, and multi-client synchronization.
"""

import os
import sys
import time
import socket
import unittest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from game.network_protocol import (
    encode_message,
    MessageFramer,
    InputValidator,
    MSG_INPUT,
    MSG_JOIN,
)
from game.server_world import GameServer
from game.client_network import NetworkClient


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestNetworkProtocol(unittest.TestCase):

    def test_message_framer_fragmented_and_multiple(self):
        """Verify TCP stream framing with partial chunks and combined messages."""
        framer = MessageFramer()

        msg1 = {"type": "test1", "val": 42}
        msg2 = {"type": "test2", "val": 99}

        data1 = encode_message(msg1)
        data2 = encode_message(msg2)

        # Feed first half of msg1
        mid = len(data1) // 2
        res1 = framer.feed(data1[:mid])
        self.assertEqual(len(res1), 0)

        # Feed second half of msg1 + all of msg2 in single chunk
        res2 = framer.feed(data1[mid:] + data2)
        self.assertEqual(len(res2), 2)
        self.assertEqual(res2[0]["val"], 42)
        self.assertEqual(res2[1]["val"], 99)

    def test_message_framer_malformed_recovery(self):
        """Verify recovery from corrupted JSON lines."""
        framer = MessageFramer()
        corrupted = b"this is not json\n"
        valid = encode_message({"type": "good", "ok": True})

        res = framer.feed(corrupted + valid)
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["ok"], True)

    def test_input_validator(self):
        """Verify movement clamping and rejection of spoofed scores or kills."""
        raw_cheat_packet = {
            "type": MSG_INPUT,
            "seq": 5,
            "mx": 9999.0,  # Speed hack attempt
            "my": -10.0,
            "ax": 1.0,
            "ay": 0.0,
            "fire": True,
            "dash": False,
            "score": 999999,  # Cheat score injection attempt
            "kill_boss": True,
        }

        sanitized = InputValidator.validate_client_input(raw_cheat_packet)
        self.assertIsNotNone(sanitized)
        # Movement clamped to [-1.0, 1.0]
        self.assertEqual(sanitized["mx"], 1.0)
        self.assertEqual(sanitized["my"], -1.0)
        # Cheat fields completely ignored
        self.assertNotIn("score", sanitized)
        self.assertNotIn("kill_boss", sanitized)

        # Name sanitization
        clean_name = InputValidator.sanitize_player_name("<Script>Admin_1234567890123456789")
        self.assertLessEqual(len(clean_name), 16)
        self.assertNotIn("<", clean_name)
        self.assertNotIn(">", clean_name)

    def test_headless_server_and_two_clients_sync(self):
        """
        Headless integration test: starts server and connects 2 independent clients,
        verifying two-way synchronization of player and enemy states.
        """
        test_port = find_free_port()
        server = GameServer(host="127.0.0.1", port=test_port, level=1)
        server.start(background=True)

        client1 = NetworkClient()
        client2 = NetworkClient()

        try:
            # Client 1 connects
            connected1 = client1.connect("127.0.0.1", test_port, player_name="ClientAlpha")
            self.assertTrue(connected1)
            self.assertEqual(client1.status, NetworkClient.STATUS_CONNECTED)
            self.assertEqual(client1.player_id, 1)

            # Client 2 connects
            connected2 = client2.connect("127.0.0.1", test_port, player_name="ClientBeta")
            self.assertTrue(connected2)
            self.assertEqual(client2.status, NetworkClient.STATUS_CONNECTED)
            self.assertEqual(client2.player_id, 2)
            self.assertNotEqual(client1.color_index, client2.color_index)

            # Client 1 sends input
            client1.send_input(mx=1.0, my=0.0, ax=1.0, ay=0.0, want_fire=False, want_dash=False, want_echo=False)

            # Wait briefly for server ticks and snapshots to propagate
            start_wait = time.time()
            snap1 = None
            snap2 = None
            while time.time() - start_wait < 2.0:
                snap1 = client1.get_snapshot()
                snap2 = client2.get_snapshot()
                if snap1 and snap2 and len(snap1.get("players", [])) == 2:
                    break
                time.sleep(0.05)

            self.assertIsNotNone(snap1)
            self.assertIsNotNone(snap2)
            # Both clients see both players
            self.assertEqual(len(snap1["players"]), 2)
            self.assertEqual(len(snap2["players"]), 2)
            # Shared enemies exist
            self.assertGreater(len(snap1["enemies"]), 0)

        finally:
            client1.disconnect()
            client2.disconnect()
            server.stop()


if __name__ == "__main__":
    unittest.main()
