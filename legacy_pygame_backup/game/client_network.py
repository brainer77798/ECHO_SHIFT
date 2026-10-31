"""
Client network manager: socket connection, background thread, snapshot buffering, and input dispatch.
"""

import socket
import threading
import time
from typing import Optional, Dict, Any, List
from game.network_protocol import (
    MSG_JOIN,
    MSG_WELCOME,
    MSG_INPUT,
    MSG_SNAPSHOT,
    MSG_LEAVE,
    MSG_ERROR,
    encode_message,
    MessageFramer,
)
from settings import DEFAULT_PORT, PROTOCOL_VERSION


class NetworkClient:
    STATUS_DISCONNECTED = "disconnected"
    STATUS_CONNECTING = "connecting"
    STATUS_CONNECTED = "connected"
    STATUS_FAILED = "failed"

    def __init__(self):
        self.status = self.STATUS_DISCONNECTED
        self.error_message = ""
        self.sock: Optional[socket.socket] = None
        self.player_id: Optional[int] = None
        self.color_index = 0
        self.assigned_level = 1

        self.latest_snapshot: Optional[dict] = None
        self.snapshot_lock = threading.Lock()
        self.send_lock = threading.Lock()
        self.input_seq = 0

        self.pending_events: List[dict] = []
        self.events_lock = threading.Lock()

        self.reader_thread: Optional[threading.Thread] = None
        self.running = False

    def connect(self, host: str, port: int = DEFAULT_PORT, player_name: str = "Player") -> bool:
        self.status = self.STATUS_CONNECTING
        self.error_message = ""

        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(4.0)
            self.sock.connect((host, port))
            self.sock.settimeout(None)

            # Send Join message
            join_msg = encode_message({
                "type": MSG_JOIN,
                "name": player_name,
                "protocol": PROTOCOL_VERSION,
            })
            self.sock.sendall(join_msg)

            # Read initial welcome response
            framer = MessageFramer()
            welcome_received = False
            start_t = time.time()

            while time.time() - start_t < 4.0:
                chunk = self.sock.recv(2048)
                if not chunk:
                    break
                messages = framer.feed(chunk)
                for m in messages:
                    if m.get("type") == MSG_WELCOME:
                        self.player_id = m.get("player_id")
                        self.color_index = m.get("color_index", 0)
                        self.assigned_level = m.get("level", 1)
                        welcome_received = True
                        break
                    elif m.get("type") == MSG_ERROR:
                        self.error_message = m.get("message", "Server error.")
                        self.status = self.STATUS_FAILED
                        self.sock.close()
                        return False
                if welcome_received:
                    break

            if not welcome_received:
                self.error_message = "No welcome handshake response from server."
                self.status = self.STATUS_FAILED
                self.sock.close()
                return False

            self.status = self.STATUS_CONNECTED
            self.running = True
            self.reader_thread = threading.Thread(target=self._reader_loop, daemon=True, name="ClientReader")
            self.reader_thread.start()
            return True

        except (socket.error, OSError) as e:
            self.status = self.STATUS_FAILED
            self.error_message = f"Connection failed: {e}"
            if self.sock:
                try:
                    self.sock.close()
                except Exception:
                    pass
            return False

    def _reader_loop(self):
        framer = MessageFramer()
        try:
            while self.running:
                chunk = self.sock.recv(4096)
                if not chunk:
                    break
                messages = framer.feed(chunk)
                for msg in messages:
                    mtype = msg.get("type")
                    if mtype == MSG_SNAPSHOT:
                        data = msg.get("data")
                        with self.snapshot_lock:
                            self.latest_snapshot = data

                        # Extract audio/fx events
                        events = data.get("events", [])
                        if events:
                            with self.events_lock:
                                self.pending_events.extend(events)

                    elif mtype == MSG_ERROR:
                        self.error_message = msg.get("message", "")
        except (socket.error, ConnectionResetError):
            pass
        finally:
            self.status = self.STATUS_DISCONNECTED
            self.running = False

    def send_input(
        self,
        mx: float,
        my: float,
        ax: float,
        ay: float,
        want_fire: bool,
        want_dash: bool,
        want_echo: bool,
    ):
        if self.status != self.STATUS_CONNECTED or not self.sock:
            return

        self.input_seq += 1
        payload = {
            "type": MSG_INPUT,
            "seq": self.input_seq,
            "mx": round(mx, 2),
            "my": round(my, 2),
            "ax": round(ax, 2),
            "ay": round(ay, 2),
            "fire": want_fire,
            "dash": want_dash,
            "echo": want_echo,
        }
        data = encode_message(payload)
        with self.send_lock:
            try:
                self.sock.sendall(data)
            except (socket.error, BrokenPipeError):
                self.status = self.STATUS_DISCONNECTED

    def get_snapshot(self) -> Optional[dict]:
        with self.snapshot_lock:
            return self.latest_snapshot

    def pop_events(self) -> List[dict]:
        with self.events_lock:
            evs = list(self.pending_events)
            self.pending_events.clear()
            return evs

    def disconnect(self):
        self.running = False
        if self.sock:
            try:
                self.sock.sendall(encode_message({"type": MSG_LEAVE}))
            except Exception:
                pass
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except Exception:
                pass
            try:
                self.sock.close()
            except Exception:
                pass
        self.status = self.STATUS_DISCONNECTED
