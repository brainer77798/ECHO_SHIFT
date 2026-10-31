"""
ECHO//SHIFT - Master Game Application and Presentation Layer
"""

import math
import os
import random
import socket
import sys
from typing import Optional, List, Dict, Tuple
import pygame

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from settings import (
    GAME_TITLE,
    VERSION,
    SCREEN_WIDTH,
    SCREEN_HEIGHT,
    TARGET_FPS,
    BACKGROUND,
    GRID_COLOR,
    BORDER_COLOR,
    PLAYER_COLOR,
    PLAYER_COLORS,
    ECHO_COLOR,
    ENEMY_COLOR,
    WHITE,
    MUTED,
    DARK_OVERLAY,
    DEFAULT_PORT,
)
from game.entities import Vec2, BoundingBox
from game.game_world import GameWorld
from game.server_world import GameServer
from game.client_network import NetworkClient
from game.audio import audio
from game.effects import ParticleSystem, draw_glow, draw_hologram_echo
from game.ui import Button, TextInput, HUD


def get_local_ips():
    ips = []
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    if not ips:
        ips.append("127.0.0.1")
    return ips


class EchoShiftGame:
    # Game States
    STATE_MENU = "menu"
    STATE_JOIN = "join"
    STATE_CONTROLS = "controls"
    STATE_SOLO = "solo"
    STATE_LAN = "lan"
    STATE_PAUSED = "paused"
    STATE_GAME_OVER = "game_over"
    STATE_VICTORY = "victory"

    def __init__(self):
        pygame.init()
        self.screen = pygame.display.set_mode((SCREEN_WIDTH, SCREEN_HEIGHT))
        pygame.display.set_caption(f"{GAME_TITLE} v{VERSION}")
        self.clock = pygame.time.Clock()

        self.state = self.STATE_MENU
        self.prev_state = self.STATE_MENU
        self.running = True

        # Systems
        self.particles = ParticleSystem()
        self.hud = HUD()

        # Solo Simulation
        self.solo_world: Optional[GameWorld] = None
        self.solo_player_id = 1

        # Multiplayer Networking
        self.hosted_server: Optional[GameServer] = None
        self.client_network: Optional[NetworkClient] = None
        self.is_hosting = False

        # Fonts
        self.font_logo = pygame.font.Font(None, 68)
        self.font_title = pygame.font.Font(None, 36)
        self.font_body = pygame.font.Font(None, 24)
        self.font_small = pygame.font.Font(None, 20)

        # UI Elements
        self._init_ui()

        # Visual Grid Animation
        self.grid_scroll = 0.0

    def _init_ui(self):
        cx = SCREEN_WIDTH // 2
        bw, bh = 280, 48

        # Main Menu Buttons
        self.menu_buttons = [
            Button("SINGLE PLAYER", cx - bw // 2, 280, bw, bh, action=self.start_solo_game),
            Button("HOST LAN CO-OP", cx - bw // 2, 340, bw, bh, action=self.host_lan_game),
            Button("JOIN LAN GAME", cx - bw // 2, 400, bw, bh, action=lambda: self.switch_state(self.STATE_JOIN)),
            Button("CONTROLS & HOW TO PLAY", cx - bw // 2, 460, bw, bh, action=lambda: self.switch_state(self.STATE_CONTROLS)),
            Button("QUIT", cx - bw // 2, 520, bw, bh, action=self.quit_game, color=ENEMY_COLOR),
        ]

        # Join Menu Controls
        self.ip_input = TextInput(cx - 140, 280, 280, 38, default_text="127.0.0.1", label="SERVER IP ADDRESS")
        self.port_input = TextInput(cx - 140, 350, 280, 38, default_text=str(DEFAULT_PORT), label="SERVER PORT")
        self.name_input = TextInput(cx - 140, 420, 280, 38, default_text="Agent_1", label="PLAYER CODENAME")

        self.join_buttons = [
            Button("CONNECT & JOIN", cx - 140, 490, 280, 44, action=self.connect_to_lan_game),
            Button("BACK TO MENU", cx - 140, 546, 280, 40, action=lambda: self.switch_state(self.STATE_MENU), color=MUTED),
        ]

        # Controls Menu
        self.controls_back_btn = Button("BACK TO MENU", cx - 100, 580, 200, 44, action=lambda: self.switch_state(self.STATE_MENU))

        # Pause Menu
        self.pause_buttons = [
            Button("RESUME", cx - bw // 2, 270, bw, bh, action=self.resume_game),
            Button("RESTART LEVEL", cx - bw // 2, 335, bw, bh, action=self.restart_current_level),
            Button("RETURN TO MAIN MENU", cx - bw // 2, 400, bw, bh, action=self.return_to_main_menu, color=MUTED),
        ]

        # Game Over / Victory Buttons
        self.end_buttons = [
            Button("RETRY MISSION", cx - bw // 2, 440, bw, bh, action=self.restart_current_level),
            Button("RETURN TO MENU", cx - bw // 2, 505, bw, bh, action=self.return_to_main_menu, color=MUTED),
        ]

    def switch_state(self, new_state: str):
        self.prev_state = self.state
        self.state = new_state

    def start_solo_game(self):
        self.solo_world = GameWorld(start_level=1)
        self.solo_player_id = 1
        self.solo_world.add_player(self.solo_player_id, "Solo_Operative", color_index=0)
        self.switch_state(self.STATE_SOLO)

    def host_lan_game(self):
        # Start server in background thread
        try:
            self.hosted_server = GameServer(host="0.0.0.0", port=DEFAULT_PORT, level=1)
            self.hosted_server.start(background=True)
            self.is_hosting = True
        except Exception as e:
            print(f"Error hosting server: {e}")
            return

        # Connect as host client
        self.client_network = NetworkClient()
        success = self.client_network.connect("127.0.0.1", DEFAULT_PORT, player_name="Host_Player")
        if success:
            self.switch_state(self.STATE_LAN)
        else:
            self.hosted_server.stop()
            self.is_hosting = False

    def connect_to_lan_game(self):
        host_ip = self.ip_input.text.strip() or "127.0.0.1"
        try:
            port = int(self.port_input.text.strip())
        except ValueError:
            port = DEFAULT_PORT
        name = self.name_input.text.strip() or "Player"

        self.client_network = NetworkClient()
        success = self.client_network.connect(host_ip, port, player_name=name)
        if success:
            self.switch_state(self.STATE_LAN)

    def resume_game(self):
        if self.prev_state in (self.STATE_SOLO, self.STATE_LAN):
            self.state = self.prev_state
        else:
            self.state = self.STATE_SOLO

    def restart_current_level(self):
        if self.state in (self.STATE_SOLO, self.STATE_PAUSED, self.STATE_GAME_OVER, self.STATE_VICTORY):
            lvl = self.solo_world.level_index if self.solo_world else 1
            self.start_solo_game()
            self.solo_world.load_level(lvl)
            self.state = self.STATE_SOLO

    def return_to_main_menu(self):
        if self.client_network:
            self.client_network.disconnect()
            self.client_network = None
        if self.hosted_server:
            self.hosted_server.stop()
            self.hosted_server = None
            self.is_hosting = False
        self.solo_world = None
        self.switch_state(self.STATE_MENU)

    def quit_game(self):
        self.return_to_main_menu()
        self.running = False

    def run(self):
        while self.running:
            dt = min(self.clock.tick(TARGET_FPS) / 1000.0, 0.05)
            self.grid_scroll = (self.grid_scroll + dt * 20.0) % 40.0

            self.handle_events()
            self.update(dt)
            self.draw()

        pygame.quit()
        sys.exit()

    def handle_events(self):
        mouse_pos = pygame.mouse.get_pos()

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self.quit_game()
                return

            if self.state == self.STATE_MENU:
                for btn in self.menu_buttons:
                    btn.update(mouse_pos)
                    btn.handle_event(event)

            elif self.state == self.STATE_JOIN:
                self.ip_input.handle_event(event)
                self.port_input.handle_event(event)
                self.name_input.handle_event(event)
                for btn in self.join_buttons:
                    btn.update(mouse_pos)
                    btn.handle_event(event)
                if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                    self.switch_state(self.STATE_MENU)

            elif self.state == self.STATE_CONTROLS:
                self.controls_back_btn.update(mouse_pos)
                self.controls_back_btn.handle_event(event)
                if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                    self.switch_state(self.STATE_MENU)

            elif self.state in (self.STATE_SOLO, self.STATE_LAN):
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_ESCAPE:
                        self.switch_state(self.STATE_PAUSED)

            elif self.state == self.STATE_PAUSED:
                for btn in self.pause_buttons:
                    btn.update(mouse_pos)
                    btn.handle_event(event)
                if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                    self.resume_game()

            elif self.state in (self.STATE_GAME_OVER, self.STATE_VICTORY):
                for btn in self.end_buttons:
                    btn.update(mouse_pos)
                    btn.handle_event(event)
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_r:
                        self.restart_current_level()
                    elif event.key == pygame.K_ESCAPE:
                        self.return_to_main_menu()

    def update(self, dt: float):
        self.particles.update(dt)

        if self.state == self.STATE_SOLO:
            if not self.solo_world:
                return

            keys = pygame.key.get_pressed()
            mouse_pos = pygame.mouse.get_pos()
            mouse_btn = pygame.mouse.get_pressed()

            # Gather Input
            mx = float(keys[pygame.K_d] or keys[pygame.K_RIGHT]) - float(keys[pygame.K_a] or keys[pygame.K_LEFT])
            my = float(keys[pygame.K_s] or keys[pygame.K_DOWN]) - float(keys[pygame.K_w] or keys[pygame.K_UP])

            p = self.solo_world.players.get(self.solo_player_id)
            if p:
                aim_vec = Vec2(mouse_pos[0] - p.position.x, mouse_pos[1] - p.position.y)
                if aim_vec.length_squared() > 1e-4:
                    aim_vec = aim_vec.normalize()
                else:
                    aim_vec = Vec2(1, 0)
                ax, ay = aim_vec.x, aim_vec.y
            else:
                ax, ay = 1.0, 0.0

            want_fire = mouse_btn[0]
            want_dash = bool(keys[pygame.K_SPACE] or keys[pygame.K_LSHIFT])
            want_echo = bool(keys[pygame.K_e])

            self.solo_world.apply_player_input(
                self.solo_player_id,
                move_x=mx,
                move_y=my,
                aim_x=ax,
                aim_y=ay,
                want_fire=want_fire,
                want_dash=want_dash,
                want_echo=want_echo,
            )

            self.solo_world.update(dt)

            # Process Audio and Visual Events
            self._process_events(self.solo_world.recent_events)

            # Check Game Over / Victory
            if self.solo_world.state == GameWorld.STATE_GAME_OVER:
                self.state = self.STATE_GAME_OVER
            elif self.solo_world.state == GameWorld.STATE_VICTORY:
                self.state = self.STATE_VICTORY

        elif self.state == self.STATE_LAN:
            if not self.client_network or self.client_network.status != NetworkClient.STATUS_CONNECTED:
                return

            keys = pygame.key.get_pressed()
            mouse_pos = pygame.mouse.get_pos()
            mouse_btn = pygame.mouse.get_pressed()

            mx = float(keys[pygame.K_d] or keys[pygame.K_RIGHT]) - float(keys[pygame.K_a] or keys[pygame.K_LEFT])
            my = float(keys[pygame.K_s] or keys[pygame.K_DOWN]) - float(keys[pygame.K_w] or keys[pygame.K_UP])

            snap = self.client_network.get_snapshot()
            ax, ay = 1.0, 0.0
            if snap and self.client_network.player_id:
                for p_dict in snap.get("players", []):
                    if p_dict["id"] == self.client_network.player_id:
                        aim_vec = Vec2(mouse_pos[0] - p_dict["x"], mouse_pos[1] - p_dict["y"])
                        if aim_vec.length_squared() > 1e-4:
                            aim_vec = aim_vec.normalize()
                            ax, ay = aim_vec.x, aim_vec.y
                        break

            want_fire = mouse_btn[0]
            want_dash = bool(keys[pygame.K_SPACE] or keys[pygame.K_LSHIFT])
            want_echo = bool(keys[pygame.K_e])

            self.client_network.send_input(mx, my, ax, ay, want_fire, want_dash, want_echo)

            # Process network sound/fx events
            net_events = self.client_network.pop_events()
            self._process_events(net_events)

            # State check from snapshot
            if snap:
                s_state = snap.get("state")
                if s_state == GameWorld.STATE_GAME_OVER:
                    self.state = self.STATE_GAME_OVER
                elif s_state == GameWorld.STATE_VICTORY:
                    self.state = self.STATE_VICTORY

    def _process_events(self, events: List[dict]):
        for ev in events:
            etype = ev.get("type")
            if etype == "sound":
                audio.play(ev.get("name", ""))
            elif etype == "fx":
                name = ev.get("name")
                x, y = ev.get("x", 0), ev.get("y", 0)
                if name == "echo_spawn":
                    self.particles.emit_warp_spiral(x, y, ECHO_COLOR, 18)
                elif name == "explosion":
                    self.particles.emit_explosion(x, y, 22)
                elif name == "shard_collect":
                    self.particles.emit_sparks(x, y, (255, 230, 90), 16)
            elif etype == "enemy_hit":
                self.particles.emit_sparks(ev["x"], ev["y"], WHITE if ev.get("is_echo") else ENEMY_COLOR, 6)

    def draw(self):
        self.screen.fill(BACKGROUND)
        self._draw_background_grid()

        if self.state == self.STATE_MENU:
            self._draw_main_menu()
        elif self.state == self.STATE_JOIN:
            self._draw_join_menu()
        elif self.state == self.STATE_CONTROLS:
            self._draw_controls_menu()
        elif self.state in (self.STATE_SOLO, self.STATE_PAUSED, self.STATE_GAME_OVER, self.STATE_VICTORY):
            # Solo-mode states: always draw solo world if present
            if self.solo_world:
                self._draw_world(self.solo_world.get_snapshot(), local_player_id=self.solo_player_id)
            if self.state == self.STATE_PAUSED:
                self._draw_pause_overlay()
            elif self.state == self.STATE_GAME_OVER:
                self._draw_end_overlay(is_victory=False)
            elif self.state == self.STATE_VICTORY:
                self._draw_end_overlay(is_victory=True)
        elif self.state == self.STATE_LAN:
            # LAN mode: draw latest snapshot, plus end overlays when match ends
            if self.client_network:
                snap = self.client_network.get_snapshot()
                if snap:
                    self._draw_world(snap, local_player_id=self.client_network.player_id)
                    # Show end overlay on top of the last world view
                    net_state = snap.get("state")
                    if net_state == GameWorld.STATE_GAME_OVER:
                        self._draw_end_overlay(is_victory=False)
                    elif net_state == GameWorld.STATE_VICTORY:
                        self._draw_end_overlay(is_victory=True)
                else:
                    self._draw_connecting_screen()

        self.particles.draw(self.screen)
        pygame.display.flip()

    def _draw_background_grid(self):
        grid_sz = 40
        w, h = SCREEN_WIDTH, SCREEN_HEIGHT
        offset_y = int(self.grid_scroll)

        for x in range(0, w, grid_sz):
            pygame.draw.line(self.screen, GRID_COLOR, (x, 0), (x, h), 1)
        for y in range(offset_y, h, grid_sz):
            pygame.draw.line(self.screen, GRID_COLOR, (0, y), (w, y), 1)

    def _draw_main_menu(self):
        cx = SCREEN_WIDTH // 2

        # Glowing Logo
        title_surf = self.font_logo.render("ECHO // SHIFT", True, PLAYER_COLOR)
        sub_surf = self.font_body.render("TEMPORAL COOPERATIVE TACTICAL COMBAT", True, MUTED)

        self.screen.blit(title_surf, title_surf.get_rect(center=(cx, 150)))
        self.screen.blit(sub_surf, sub_surf.get_rect(center=(cx, 205)))

        mouse_pos = pygame.mouse.get_pos()
        for btn in self.menu_buttons:
            btn.update(mouse_pos)
            btn.draw(self.screen)

        ver = self.font_small.render(f"v{VERSION}  |  LAN Server Authoritative", True, (70, 100, 120))
        self.screen.blit(ver, (20, SCREEN_HEIGHT - 30))

    def _draw_join_menu(self):
        cx = SCREEN_WIDTH // 2
        title = self.font_title.render("JOIN LOCAL LAN GAME", True, WHITE)
        self.screen.blit(title, title.get_rect(center=(cx, 210)))

        self.ip_input.draw(self.screen)
        self.port_input.draw(self.screen)
        self.name_input.draw(self.screen)

        mouse_pos = pygame.mouse.get_pos()
        for btn in self.join_buttons:
            btn.update(mouse_pos)
            btn.draw(self.screen)

        if self.client_network and self.client_network.error_message:
            err = self.font_small.render(self.client_network.error_message, True, ENEMY_COLOR)
            self.screen.blit(err, err.get_rect(center=(cx, 605)))

    def _draw_controls_menu(self):
        cx = SCREEN_WIDTH // 2
        card = pygame.Rect(cx - 360, 100, 720, 460)
        pygame.draw.rect(self.screen, (10, 24, 38), card, border_radius=8)
        pygame.draw.rect(self.screen, BORDER_COLOR, card, 2, border_radius=8)

        title = self.font_title.render("MISSION PROTOCOL // FIELD CONTROLS", True, PLAYER_COLOR)
        self.screen.blit(title, title.get_rect(center=(cx, 140)))

        instructions = [
            ("WASD / ARROW KEYS", "Movement with normalized diagonal speed."),
            ("MOUSE CURSOR", "Aim direction and crosshair."),
            ("LEFT MOUSE BUTTON", "Discharge standard plasma pulse rifle."),
            ("SPACE / LSHIFT", "Tactical high-speed dash (brief invulnerability)."),
            ("KEY [E] (CORE HOOK)", "CREATE TEMPORAL ECHO: Replays your past 5 seconds of movement and fire!"),
            ("ECHO PUZZLES", "Echoes activate floor pressure plates to unlock security doors and bulkheads."),
            ("ECHO COMBAT", "Echoes distract hostile bots and deal 55% damage with replayed weapons fire."),
            ("KEY [ESC]", "Pause simulation or return to tactical terminal."),
        ]

        y = 190
        for key_text, desc in instructions:
            k_surf = self.font_body.render(key_text, True, ECHO_COLOR if "[E]" in key_text else WHITE)
            d_surf = self.font_body.render(desc, True, MUTED)
            self.screen.blit(k_surf, (card.x + 35, y))
            self.screen.blit(d_surf, (card.x + 220, y))
            y += 34

        mouse_pos = pygame.mouse.get_pos()
        self.controls_back_btn.update(mouse_pos)
        self.controls_back_btn.draw(self.screen)

    def _draw_world(self, snapshot: dict, local_player_id: Optional[int]):
        w, h = SCREEN_WIDTH, SCREEN_HEIGHT

        # 1. Arena Boundaries and Level Walls
        lvl = snapshot.get("level", 1)
        ab = pygame.Rect(45, 80, w - 90, h - 130)
        pygame.draw.rect(self.screen, BORDER_COLOR, ab, 2, border_radius=6)

        # Draw interior walls based on level
        if lvl == 1:
            mid_x = w // 2 - 15
            pygame.draw.rect(self.screen, (18, 55, 75), pygame.Rect(mid_x, 80, 30, 200), border_radius=4)
            pygame.draw.rect(self.screen, (18, 55, 75), pygame.Rect(mid_x, 380, 30, h - 130 - 300), border_radius=4)
        elif lvl == 2:
            for px, py in [(350, 200), (350, 420), (820, 200), (820, 420)]:
                pygame.draw.rect(self.screen, (18, 55, 75), pygame.Rect(px, py, 70, 120), border_radius=4)
        elif lvl == 3:
            for cx, cy in [(180, 140), (w - 240, 140), (180, h - 220), (w - 240, h - 220)]:
                pygame.draw.rect(self.screen, (25, 45, 65), pygame.Rect(cx, cy, 60, 60), border_radius=6)

        # 2. Pressure Plates
        for p in snapshot.get("plates", []):
            prect = pygame.Rect(p["x"], p["y"], p["w"], p["h"])
            p_col = (90, 240, 150) if p["active"] else (45, 75, 95)
            pygame.draw.rect(self.screen, (15, 30, 45), prect, border_radius=4)
            pygame.draw.rect(self.screen, p_col, prect, width=3 if p["active"] else 1, border_radius=4)
            # Switch inner indicator
            inner_r = prect.inflate(-16, -16)
            if p["active"]:
                pygame.draw.rect(self.screen, (60, 210, 130), inner_r, border_radius=3)
            lbl = self.font_small.render(p.get("label", "PLATE"), True, p_col)
            self.screen.blit(lbl, lbl.get_rect(center=prect.center))

        # 3. Doors & Bulkheads
        for d in snapshot.get("doors", []):
            drect = pygame.Rect(d["x"], d["y"], d["w"], d["h"])
            is_open = d.get("open", False)
            if not is_open:
                # Closed security barrier
                pygame.draw.rect(self.screen, (160, 40, 60), drect, border_radius=4)
                pygame.draw.rect(self.screen, ENEMY_COLOR, drect, 2, border_radius=4)
                # Diagonal warning stripes
                for sx in range(drect.left, drect.right + drect.height, 12):
                    pygame.draw.line(self.screen, (200, 50, 70), (sx, drect.top), (sx - 10, drect.bottom), 1)
            else:
                # Open portal
                pygame.draw.rect(self.screen, (15, 45, 35), drect, border_radius=4)
                pygame.draw.rect(self.screen, (50, 220, 120), drect, 1, border_radius=4)

        # 4. Energy Shards
        for s in snapshot.get("shards", []):
            if not s.get("collected"):
                sx, sy = int(s["x"]), int(s["y"])
                draw_glow(self.screen, (sx, sy), (255, 230, 90), 8)
                # Diamond shape
                pts = [(sx, sy - 9), (sx + 8, sy), (sx, sy + 9), (sx - 8, sy)]
                pygame.draw.polygon(self.screen, (255, 240, 120), pts)

        # 5. Holographic Echoes (Core Hook)
        player_colors = {
            pl["id"]: PLAYER_COLORS[pl.get("color_index", 0) % len(PLAYER_COLORS)]
            for pl in snapshot.get("players", [])
        }

        for e in snapshot.get("echoes", []):
            owner_col = player_colors.get(e.get("owner"), ECHO_COLOR)
            draw_hologram_echo(
                self.screen,
                pos=(e["x"], e["y"]),
                facing=(e["aim_x"], e["aim_y"]),
                alpha=e.get("alpha", 1.0),
                radius=e.get("radius", 16.0),
                is_holding=e.get("is_holding", False),
                owner_color=owner_col,
            )

        # 6. Enemies & Boss
        boss_data = None
        for en in snapshot.get("enemies", []):
            etype = en.get("type", "hunter")
            pos = (int(en["x"]), int(en["y"]))
            r = int(en.get("radius", 16.0))
            col = WHITE if en.get("hit_flash") else ENEMY_COLOR

            if etype == "warden":
                boss_data = en
                # Large mechanical boss
                draw_glow(self.screen, pos, col, r, layers=3)
                pygame.draw.circle(self.screen, (40, 15, 28), pos, r)
                pygame.draw.circle(self.screen, col, pos, r, 3)
                # Center core
                core_col = (100, 160, 255) if (en.get("shield") and not en.get("shield_down")) else (255, 45, 75)
                pygame.draw.circle(self.screen, core_col, pos, r // 2)
                # Facing cannons
                fx, fy = en.get("facing_x", 1.0), en.get("facing_y", 0.0)
                tip = (pos[0] + fx * (r + 15), pos[1] + fy * (r + 15))
                pygame.draw.line(self.screen, WHITE, pos, tip, 4)

            elif etype == "brute":
                # Heavy armored bot with front shield
                draw_glow(self.screen, pos, col, r)
                pygame.draw.circle(self.screen, (50, 20, 30), pos, r)
                pygame.draw.circle(self.screen, col, pos, r, 2)
                # Shield arc on front
                fx, fy = en.get("facing_x", 1.0), en.get("facing_y", 0.0)
                shield_tip = (pos[0] + fx * (r + 6), pos[1] + fy * (r + 6))
                pygame.draw.circle(self.screen, (100, 180, 255), (round(shield_tip[0]), round(shield_tip[1])), 8)

            elif etype == "sentry":
                # Turret with charging telegraph laser
                draw_glow(self.screen, pos, col, r)
                pygame.draw.circle(self.screen, (35, 20, 40), pos, r)
                pygame.draw.circle(self.screen, col, pos, r, 2)
                if en.get("is_charging"):
                    lx, ly = en.get("laser_x", pos[0]), en.get("laser_y", pos[1])
                    pygame.draw.line(self.screen, (255, 80, 80), pos, (round(lx), round(ly)), 2)

            else:
                # Hunter Drone
                draw_glow(self.screen, pos, col, r)
                pygame.draw.circle(self.screen, (40, 18, 25), pos, r)
                pygame.draw.circle(self.screen, col, pos, r, 2)
                pygame.draw.circle(self.screen, WHITE, pos, 4)

        # 7. Projectiles
        for pr in snapshot.get("projectiles", []):
            ppos = (round(pr["x"]), round(pr["y"]))
            if pr.get("is_enemy"):
                p_col = ENEMY_COLOR
            elif pr.get("is_echo"):
                p_col = ECHO_COLOR
            else:
                p_col = PLAYER_COLOR

            draw_glow(self.screen, ppos, p_col, pr.get("radius", 4), layers=1)
            pygame.draw.circle(self.screen, WHITE, ppos, max(2, int(pr.get("radius", 4)) - 1))

        # 8. Players
        local_player_dict = None
        for pl in snapshot.get("players", []):
            if local_player_id and pl["id"] == local_player_id:
                local_player_dict = pl

            ppos = (round(pl["x"]), round(pl["y"]))
            c_idx = pl.get("color_index", 0) % len(PLAYER_COLORS)
            p_col = PLAYER_COLORS[c_idx]

            if pl.get("is_downed"):
                # Downed cross marker
                pygame.draw.circle(self.screen, (80, 20, 30), ppos, 16)
                pygame.draw.line(self.screen, ENEMY_COLOR, (ppos[0] - 8, ppos[1] - 8), (ppos[0] + 8, ppos[1] + 8), 3)
                pygame.draw.line(self.screen, ENEMY_COLOR, (ppos[0] - 8, ppos[1] + 8), (ppos[0] + 8, ppos[1] - 8), 3)
            else:
                draw_glow(self.screen, ppos, p_col, 16)
                pygame.draw.circle(self.screen, (10, 45, 55), ppos, 16)
                pygame.draw.circle(self.screen, p_col, ppos, 16, 2)

                # Aim triangle pointer
                ax, ay = pl.get("aim_x", 1.0), pl.get("aim_y", 0.0)
                tip = (ppos[0] + ax * 24, ppos[1] + ay * 24)
                pygame.draw.circle(self.screen, WHITE, (round(tip[0]), round(tip[1])), 3)

                # Player name tag above
                nametag = self.font_small.render(pl.get("name", "Player"), True, (200, 230, 245))
                self.screen.blit(nametag, nametag.get_rect(center=(ppos[0], ppos[1] - 24)))

        # 9. Mouse Crosshair for local player
        if local_player_dict and not local_player_dict.get("is_downed"):
            mx, my = pygame.mouse.get_pos()
            pygame.draw.circle(self.screen, PLAYER_COLOR, (mx, my), 8, 1)
            pygame.draw.line(self.screen, PLAYER_COLOR, (mx - 12, my), (mx + 12, my), 1)
            pygame.draw.line(self.screen, PLAYER_COLOR, (mx, my - 12), (mx, my + 12), 1)

        # 10. HUD
        obj_text = ""
        if lvl == 1:
            obj_text = "LEVEL 1 // Record past actions with [E] to hold the switch and unlock the bulkhead."
        elif lvl == 2:
            obj_text = "LEVEL 2 // Use Echoes on dual nodes, eliminate sentries, collect 3 Shards."
        elif lvl == 3:
            obj_text = "LEVEL 3 // DESTROY THE WARDEN. Hold Disruptor plates with Echoes during Phase 2!"

        active_count = 0
        if local_player_id:
            active_count = sum(1 for e in snapshot.get("echoes", []) if e.get("owner") == local_player_id)

        self.hud.draw(
            surface=self.screen,
            player_dict=local_player_dict,
            all_players=snapshot.get("players", []),
            team_score=snapshot.get("team_score", 0),
            level_index=lvl,
            objective_text=obj_text,
            boss_dict=boss_data,
            active_echo_count=active_count,
        )

    def _draw_pause_overlay(self):
        overlay = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT), pygame.SRCALPHA)
        overlay.fill(DARK_OVERLAY)
        self.screen.blit(overlay, (0, 0))

        cx = SCREEN_WIDTH // 2
        title = self.font_title.render("TEMPORAL STASIS // SIMULATION PAUSED", True, PLAYER_COLOR)
        self.screen.blit(title, title.get_rect(center=(cx, 190)))

        if self.is_hosting:
            ips = get_local_ips()
            ip_str = ips[0] if ips else "127.0.0.1"
            host_info = self.font_body.render(f"HOSTING LAN SERVER ON: {ip_str}:{DEFAULT_PORT}", True, (255, 220, 100))
            self.screen.blit(host_info, host_info.get_rect(center=(cx, 230)))

        mouse_pos = pygame.mouse.get_pos()
        for btn in self.pause_buttons:
            btn.update(mouse_pos)
            btn.draw(self.screen)

    def _draw_end_overlay(self, is_victory: bool):
        overlay = pygame.Surface((SCREEN_WIDTH, SCREEN_HEIGHT), pygame.SRCALPHA)
        overlay.fill((5, 12, 24, 230))
        self.screen.blit(overlay, (0, 0))

        cx = SCREEN_WIDTH // 2
        col = (90, 240, 150) if is_victory else ENEMY_COLOR
        header = "MISSION COMPLETE // WARDEN DESTROYED" if is_victory else "SYSTEM FAILURE // TEMPORAL COLLAPSE"

        title = self.font_title.render(header, True, col)
        self.screen.blit(title, title.get_rect(center=(cx, 220)))

        # Read score from whichever source is active (solo or LAN)
        if self.solo_world:
            score = self.solo_world.team_score
        elif self.client_network:
            snap = self.client_network.get_snapshot()
            score = snap.get("team_score", 0) if snap else 0
        else:
            score = 0
        score_surf = self.font_body.render(f"FINAL OPERATIONAL SCORE: {score:06d}", True, WHITE)
        self.screen.blit(score_surf, score_surf.get_rect(center=(cx, 280)))

        sub = "All objectives secured. The temporal loop has been stabilized." if is_victory else "All field operatives downed. Press R to restart simulation."
        sub_surf = self.font_body.render(sub, True, MUTED)
        self.screen.blit(sub_surf, sub_surf.get_rect(center=(cx, 320)))

        mouse_pos = pygame.mouse.get_pos()
        for btn in self.end_buttons:
            btn.update(mouse_pos)
            btn.draw(self.screen)

    def _draw_connecting_screen(self):
        cx = SCREEN_WIDTH // 2
        cy = SCREEN_HEIGHT // 2
        msg = self.font_title.render("CONNECTING TO AUTHORITATIVE SERVER...", True, PLAYER_COLOR)
        self.screen.blit(msg, msg.get_rect(center=(cx, cy)))


def main():
    game = EchoShiftGame()
    game.run()


if __name__ == "__main__":
    main()
