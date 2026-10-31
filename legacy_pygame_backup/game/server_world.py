"""
Authoritative LAN Co-op Server and synchronization loop.
"""

import socket
import threading
import time
import queue
from typing import Dict, Optional, List
from game.game_world import GameWorld
from game.network_protocol import (
    MSG_JOIN,
    MSG_WELCOME,
    MSG_INPUT,
    MSG_SNAPSHOT,
    MSG_LEAVE,
    MSG_ERROR,
    encode_message,
    MessageFramer,
    InputValidator,
)
from settings import DEFAULT_PORT, NETWORK_TICK_RATE, MAX_CLIENTS, PROTOCOL_VERSION


class ClientConnection:
    def __init__(self, sock: socket.socket, addr: tuple, player_id: int):
        self.sock = sock
        self.addr = addr
        self.player_id = player_id
        self.player_name = f"Player_{player_id}"
        self.color_index = (player_id - 1) % 4
        self.in_queue = queue.Queue(maxsize=128)
        self.write_lock = threading.Lock()
        self.active = True
        self.last_seq = 0

    def send(self, msg: dict):
        if not self.active:
            return
        data = encode_message(msg)
        with self.write_lock:
            try:
                self.sock.sendall(data)
            except (socket.error, BrokenPipeError, ConnectionResetError):
                self.active = False

    def close(self):
        self.active = False
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass


class GameServer:
    """Authoritative server running the game simulation and synchronizing up to 4 clients."""

    def __init__(self, host: str = "0.0.0.0", port: int = DEFAULT_PORT, level: int = 1):
        self.host = host
        self.port = port
        self.world = GameWorld(start_level=level)

        self.server_sock: Optional[socket.socket] = None
        self.clients: Dict[int, ClientConnection] = {}
        self.clients_lock = threading.Lock()
        self.next_player_id = 1

        self.running = False
        self.listen_thread: Optional[threading.Thread] = None
        self.tick_thread: Optional[threading.Thread] = None

    def start(self, background: bool = True):
        self.server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_sock.bind((self.host, self.port))
        self.server_sock.listen(MAX_CLIENTS)
        self.running = True

        self.listen_thread = threading.Thread(target=self._listen_loop, daemon=True, name="ServerListen")
        self.listen_thread.start()

        if background:
            self.tick_thread = threading.Thread(target=self._simulation_tick_loop, daemon=True, name="ServerTick")
            self.tick_thread.start()
        else:
            self._simulation_tick_loop()

    def _listen_loop(self):
        while self.running:
            try:
                sock, addr = self.server_sock.accept()
                with self.clients_lock:
                    if len(self.clients) >= MAX_CLIENTS:
                        # Full
                        err = encode_message({"type": MSG_ERROR, "message": "Server is full (max 4 players)."})
                        try:
                            sock.sendall(err)
                            sock.close()
                        except Exception:
                            pass
                        continue

                    p_id = self.next_player_id
                    self.next_player_id += 1
                    client = ClientConnection(sock, addr, p_id)
                    self.clients[p_id] = client

                # Start dedicated reader thread for client
                t = threading.Thread(target=self._client_reader_loop, args=(client,), daemon=True)
                t.start()

            except (socket.error, OSError):
                break

    def _client_reader_loop(self, client: ClientConnection):
        framer = MessageFramer()
        try:
            while self.running and client.active:
                chunk = client.sock.recv(4096)
                if not chunk:
                    break
                messages = framer.feed(chunk)
                for msg in messages:
                    mtype = msg.get("type")
                    if mtype == MSG_JOIN:
                        name = InputValidator.sanitize_player_name(msg.get("name"))
                        client.player_name = name
                        # Add player to GameWorld
                        self.world.add_player(client.player_id, name, client.color_index)
                        client.send({
                            "type": MSG_WELCOME,
                            "player_id": client.player_id,
                            "color_index": client.color_index,
                            "level": self.world.level_index,
                        })
                    elif mtype == MSG_INPUT:
                        valid_input = InputValidator.validate_client_input(msg)
                        if valid_input:
                            try:
                                client.in_queue.put_nowait(valid_input)
                            except queue.Full:
                                pass
                    elif mtype == MSG_LEAVE:
                        client.active = False
                        break
        except (socket.error, ConnectionResetError):
            pass
        finally:
            self._disconnect_client(client.player_id)

    def _disconnect_client(self, player_id: int):
        with self.clients_lock:
            client = self.clients.pop(player_id, None)
        if client:
            client.close()
            self.world.remove_player(player_id)

    def _simulation_tick_loop(self):
        tick_interval = 1.0 / NETWORK_TICK_RATE
        last_time = time.perf_counter()

        while self.running:
            now = time.perf_counter()
            dt = now - last_time
            last_time = now
            dt = min(dt, 0.05)  # Cap large lag spikes

            # 1. Process inputs from all connected clients
            with self.clients_lock:
                active_connections = list(self.clients.values())

            for client in active_connections:
                latest_input = None
                while not client.in_queue.empty():
                    latest_input = client.in_queue.get_nowait()

                if latest_input:
                    client.last_seq = latest_input["seq"]
                    self.world.apply_player_input(
                        player_id=client.player_id,
                        move_x=latest_input["mx"],
                        move_y=latest_input["my"],
                        aim_x=latest_input["ax"],
                        aim_y=latest_input["ay"],
                        want_fire=latest_input["fire"],
                        want_dash=latest_input["dash"],
                        want_echo=latest_input["echo"],
                    )

            # 2. Advance authoritative simulation
            self.world.update(dt)

            # 3. Snapshot broadcast
            snapshot = self.world.get_snapshot()
            msg = {"type": MSG_SNAPSHOT, "data": snapshot}
            for client in active_connections:
                client.send(msg)

            # Fixed tick sleep
            elapsed = time.perf_counter() - now
            sleep_time = tick_interval - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    def stop(self):
        self.running = False
        if self.server_sock:
            try:
                self.server_sock.close()
            except Exception:
                pass

        with self.clients_lock:
            for c in self.clients.values():
                c.close()
            self.clients.clear()
