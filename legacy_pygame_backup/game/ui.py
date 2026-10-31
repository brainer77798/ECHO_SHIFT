"""
UI components, HUD rendering, menus, text input fields, and overlays.
"""

import pygame
from typing import List, Tuple, Optional, Callable
from settings import (
    SCREEN_WIDTH,
    SCREEN_HEIGHT,
    PLAYER_COLOR,
    ECHO_COLOR,
    ENEMY_COLOR,
    WHITE,
    MUTED,
    DARK_OVERLAY,
    BACKGROUND,
    GRID_COLOR,
    BORDER_COLOR,
)


class Button:
    def __init__(
        self,
        text: str,
        x: int,
        y: int,
        width: int,
        height: int,
        action: Optional[Callable] = None,
        color: tuple = PLAYER_COLOR,
        font_size: int = 26,
    ):
        self.text = text
        self.rect = pygame.Rect(x, y, width, height)
        self.action = action
        self.color = color
        self.font = pygame.font.Font(None, font_size)
        self.is_hovered = False

    def update(self, mouse_pos: tuple) -> bool:
        self.is_hovered = self.rect.collidepoint(mouse_pos)
        return self.is_hovered

    def handle_event(self, event: pygame.event.Event) -> bool:
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.is_hovered and self.action:
                self.action()
                return True
        return False

    def draw(self, surface: pygame.Surface):
        border_col = self.color if self.is_hovered else (50, 80, 100)
        bg_col = (18, 40, 58) if self.is_hovered else (10, 24, 38)

        pygame.draw.rect(surface, bg_col, self.rect, border_radius=6)
        pygame.draw.rect(surface, border_col, self.rect, width=2 if self.is_hovered else 1, border_radius=6)

        txt_col = WHITE if self.is_hovered else (200, 220, 235)
        rendered = self.font.render(self.text, True, txt_col)
        surface.blit(rendered, rendered.get_rect(center=self.rect.center))


class TextInput:
    def __init__(self, x: int, y: int, width: int, height: int, default_text: str = "", label: str = ""):
        self.rect = pygame.Rect(x, y, width, height)
        self.text = default_text
        self.label = label
        self.active = False
        self.font = pygame.font.Font(None, 24)
        self.label_font = pygame.font.Font(None, 20)

    def handle_event(self, event: pygame.event.Event):
        if event.type == pygame.MOUSEBUTTONDOWN:
            self.active = self.rect.collidepoint(event.pos)
        elif event.type == pygame.KEYDOWN and self.active:
            if event.key == pygame.K_BACKSPACE:
                self.text = self.text[:-1]
            elif event.key == pygame.K_RETURN:
                self.active = False
            elif event.unicode and len(self.text) < 24:
                self.text += event.unicode

    def draw(self, surface: pygame.Surface):
        if self.label:
            lbl = self.label_font.render(self.label, True, MUTED)
            surface.blit(lbl, (self.rect.x, self.rect.y - 18))

        border_col = PLAYER_COLOR if self.active else (45, 75, 95)
        bg_col = (12, 28, 42) if self.active else (8, 20, 32)
        pygame.draw.rect(surface, bg_col, self.rect, border_radius=4)
        pygame.draw.rect(surface, border_col, self.rect, width=2 if self.active else 1, border_radius=4)

        display_txt = self.text + ("|" if self.active and (int(pygame.time.get_ticks() / 500) % 2 == 0) else "")
        txt_surf = self.font.render(display_txt, True, WHITE)
        surface.blit(txt_surf, (self.rect.x + 8, self.rect.y + (self.rect.height - txt_surf.get_height()) // 2))


class HUD:
    def __init__(self):
        self.font_small = pygame.font.Font(None, 22)
        self.font_medium = pygame.font.Font(None, 28)
        self.font_large = pygame.font.Font(None, 48)

    def draw(
        self,
        surface: pygame.Surface,
        player_dict: Optional[dict],
        all_players: List[dict],
        team_score: int,
        level_index: int,
        objective_text: str,
        boss_dict: Optional[dict] = None,
        active_echo_count: int = 0,
    ):
        w, h = surface.get_size()

        # Top Bar Background
        header_rect = pygame.Rect(0, 0, w, 55)
        pygame.draw.rect(surface, (5, 15, 25), header_rect)
        pygame.draw.line(surface, BORDER_COLOR, (0, 55), (w, 55), 1)

        # Title
        title = self.font_medium.render("ECHO//SHIFT", True, PLAYER_COLOR)
        surface.blit(title, (35, 16))

        # Objective
        obj_surf = self.font_small.render(objective_text, True, MUTED)
        surface.blit(obj_surf, (200, 20))

        # Score
        score_surf = self.font_medium.render(f"SCORE: {team_score:06d}", True, WHITE)
        surface.blit(score_surf, (w - score_surf.get_width() - 35, 16))

        # Bottom Bar Background
        footer_rect = pygame.Rect(0, h - 50, w, 50)
        pygame.draw.rect(surface, (5, 15, 25), footer_rect)
        pygame.draw.line(surface, BORDER_COLOR, (0, h - 50), (w, h - 50), 1)

        if player_dict:
            # Health Bar
            hp = max(0, player_dict.get("health", 100))
            max_hp = player_dict.get("max_health", 100)
            hp_ratio = hp / max_hp

            lbl_hp = self.font_small.render(f"HEALTH {hp}/{max_hp}", True, WHITE)
            surface.blit(lbl_hp, (35, h - 33))

            bar_bg = pygame.Rect(170, h - 33, 160, 16)
            pygame.draw.rect(surface, (30, 45, 60), bar_bg, border_radius=4)
            bar_fill = pygame.Rect(bar_bg.x, bar_bg.y, int(bar_bg.width * hp_ratio), bar_bg.height)
            hp_col = PLAYER_COLOR if hp_ratio > 0.35 else ENEMY_COLOR
            if bar_fill.width > 0:
                pygame.draw.rect(surface, hp_col, bar_fill, border_radius=4)

            # Dash Indicator
            dash_cd = player_dict.get("dash_cd", 0.0)
            dash_txt = "DASH [SPACE] READY" if dash_cd <= 0 else f"DASH [SPACE] {dash_cd:.1f}s"
            dash_col = PLAYER_COLOR if dash_cd <= 0 else MUTED
            dash_surf = self.font_small.render(dash_txt, True, dash_col)
            surface.blit(dash_surf, (370, h - 33))

            # Echo Hook Meter & Indicator
            echo_ready = player_dict.get("echo_ready", False)
            echo_cd = player_dict.get("echo_cd", 0.0)
            if echo_ready:
                echo_txt = f"PROJECT ECHO [E] READY  |  ECHOES: {active_echo_count}/2"
                echo_col = ECHO_COLOR
            else:
                cd_str = f"{echo_cd:.1f}s" if echo_cd > 0 else "RECORDING..."
                echo_txt = f"ECHO RECHARGE {cd_str}  |  ECHOES: {active_echo_count}/2"
                echo_col = (140, 130, 180)
            echo_surf = self.font_small.render(echo_txt, True, echo_col)
            surface.blit(echo_surf, (570, h - 33))

        # Boss Health Bar (if present)
        if boss_dict and boss_dict.get("active", True):
            boss_hp = max(0.0, boss_dict.get("health", 0.0))
            boss_max = max(1.0, boss_dict.get("max_health", 1.0))
            ratio = boss_hp / boss_max
            phase = boss_dict.get("phase", 1)
            shield = boss_dict.get("shield", False)
            shield_down = boss_dict.get("shield_down", False)

            bb_w = 400
            bb_rect = pygame.Rect(w // 2 - bb_w // 2, 65, bb_w, 14)
            pygame.draw.rect(surface, (40, 15, 25), bb_rect, border_radius=4)
            fill_rect = pygame.Rect(bb_rect.x, bb_rect.y, int(bb_rect.width * ratio), bb_rect.height)
            if fill_rect.width > 0:
                col = (100, 140, 255) if (shield and not shield_down) else ENEMY_COLOR
                pygame.draw.rect(surface, col, fill_rect, border_radius=4)
            pygame.draw.rect(surface, (180, 50, 70), bb_rect, 1, border_radius=4)

            b_status = "WARDEN CORE // PHASE " + str(phase)
            if shield:
                b_status += " [SHIELD COMPROMISED]" if shield_down else " [TEMPORAL SHIELD ACTIVE - HOLD PLATES]"
            b_label = self.font_small.render(b_status, True, WHITE)
            surface.blit(b_label, b_label.get_rect(center=(w // 2, 92)))

        # Co-op Teammates Info
        if len(all_players) > 1:
            card_x = w - 300
            card_y = h - 35
            for p in all_players:
                if player_dict and p["id"] == player_dict["id"]:
                    continue
                p_name = p.get("name", "Player")
                p_hp = p.get("health", 100)
                status_txt = f"{p_name}: {p_hp} HP"
                if p.get("is_downed"):
                    status_txt = f"{p_name}: DOWNED! REVIVE [STAND NEAR]"
                t_surf = self.font_small.render(status_txt, True, (255, 100, 120) if p.get("is_downed") else MUTED)
                surface.blit(t_surf, (card_x, card_y))
                break
