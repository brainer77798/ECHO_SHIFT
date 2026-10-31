"""
Network protocol, message framing, serialization, and input validation.
"""

import json
from typing import List, Tuple, Dict, Any, Optional
from settings import PROTOCOL_VERSION, MAX_PACKET_BYTES


# Message Types
MSG_JOIN = "join"
MSG_WELCOME = "welcome"
MSG_INPUT = "input"
MSG_SNAPSHOT = "snapshot"
MSG_LEAVE = "leave"
MSG_ERROR = "error"
MSG_PING = "ping"
MSG_PONG = "pong"


def encode_message(msg: dict) -> bytes:
    """Encode a dictionary to a newline-delimited JSON byte string."""
    payload = json.dumps(msg, separators=(",", ":"))
    return (payload + "\n").encode("utf-8")


class MessageFramer:
    """Buffers incoming raw TCP bytes and splits on newline delimiters."""

    def __init__(self, max_buffer_size: int = MAX_PACKET_BYTES * 2):
        self.buffer = bytearray()
        self.max_buffer_size = max_buffer_size

    def feed(self, data: bytes) -> List[dict]:
        """Feed raw bytes and return any completely framed JSON dictionaries."""
        if len(self.buffer) + len(data) > self.max_buffer_size:
            # Drop buffer to prevent memory exhaustion from malicious/malformed stream
            self.buffer.clear()
            return []

        self.buffer.extend(data)
        messages = []

        while b"\n" in self.buffer:
            line, _, self.buffer = self.buffer.partition(b"\n")
            line = line.strip()
            if not line:
                continue

            try:
                decoded = json.loads(line.decode("utf-8"))
                if isinstance(decoded, dict):
                    messages.append(decoded)
            except (json.JSONDecodeError, UnicodeDecodeError):
                # Malformed frame; skip and continue
                continue

        return messages

    def clear(self):
        self.buffer.clear()


class InputValidator:
    """
    Validates and sanitizes client input frames to prevent cheating or crash exploits.
    Never trust the client!
    """

    @staticmethod
    def sanitize_player_name(raw_name: Any) -> str:
        if not isinstance(raw_name, str):
            return "Player"
        clean = "".join(c for c in raw_name if c.isalnum() or c in " _-")[:16].strip()
        return clean if clean else "Player"

    @staticmethod
    def validate_client_input(data: dict) -> Optional[dict]:
        """
        Extract only authorized input fields, clamping and validating them.
        Disallows any client-reported score, health, position teleportation, or enemy kills.
        """
        if not isinstance(data, dict) or data.get("type") != MSG_INPUT:
            return None

        try:
            seq = int(data.get("seq", 0))
            # Clamp movement components to [-1.0, 1.0]
            mx = max(-1.0, min(float(data.get("mx", 0.0)), 1.0))
            my = max(-1.0, min(float(data.get("my", 0.0)), 1.0))

            # Aim direction
            ax = float(data.get("ax", 1.0))
            ay = float(data.get("ay", 0.0))
            length_sq = ax * ax + ay * ay
            if length_sq > 1e-4:
                inv = 1.0 / (length_sq ** 0.5)
                ax *= inv
                ay *= inv
            else:
                ax, ay = 1.0, 0.0

            want_fire = bool(data.get("fire", False))
            want_dash = bool(data.get("dash", False))
            want_echo = bool(data.get("echo", False))

            return {
                "seq": seq,
                "mx": mx,
                "my": my,
                "ax": ax,
                "ay": ay,
                "fire": want_fire,
                "dash": want_dash,
                "echo": want_echo,
            }
        except (ValueError, TypeError):
            return None
