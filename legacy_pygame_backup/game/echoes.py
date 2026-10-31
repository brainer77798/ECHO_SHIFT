"""
The Echo System - Recording, Playback, Hologram Projection, and Switch Interaction.
"""

from typing import List, Dict, Tuple, Optional, Set
from game.entities import Entity, Vec2, clamp, lerp, get_next_id
from settings import (
    RECORDING_SECONDS,
    MAX_ECHOES_PER_PLAYER,
    ECHO_POST_REPLAY_HOLD_TIME,
    ECHO_FADE_WARNING_TIME,
    ECHO_COLOR,
)

ECHO_RADIUS = 16.0


class PlayerActionSample:
    __slots__ = ("t", "x", "y", "aim_x", "aim_y", "fired", "dashing")

    def __init__(
        self,
        t: float,
        x: float,
        y: float,
        aim_x: float,
        aim_y: float,
        fired: bool = False,
        dashing: bool = False,
    ):
        self.t = float(t)
        self.x = float(x)
        self.y = float(y)
        self.aim_x = float(aim_x)
        self.aim_y = float(aim_y)
        self.fired = bool(fired)
        self.dashing = bool(dashing)

    def to_dict(self) -> dict:
        return {
            "t": round(self.t, 3),
            "x": round(self.x, 1),
            "y": round(self.y, 1),
            "ax": round(self.aim_x, 2),
            "ay": round(self.aim_y, 2),
            "f": self.fired,
            "d": self.dashing,
        }


class ActionRecorder:
    """Continuously records player actions over a bounded window of simulation time."""

    def __init__(self, max_duration: float = RECORDING_SECONDS):
        self.max_duration = float(max_duration)
        self.samples: List[PlayerActionSample] = []

    def record(
        self,
        sim_time: float,
        x: float,
        y: float,
        aim_x: float,
        aim_y: float,
        fired: bool,
        dashing: bool = False,
    ):
        # Enforce chronological ordering
        if self.samples and sim_time < self.samples[-1].t:
            return

        sample = PlayerActionSample(sim_time, x, y, aim_x, aim_y, fired, dashing)
        self.samples.append(sample)

        # Bounded in memory: prune samples older than max_duration
        cutoff = sim_time - self.max_duration
        while len(self.samples) > 2 and self.samples[1].t < cutoff:
            self.samples.pop(0)

    def has_enough_history(self, min_duration: float = 0.5) -> bool:
        if len(self.samples) < 2:
            return False
        return (self.samples[-1].t - self.samples[0].t) >= min_duration

    def get_duration(self) -> float:
        if len(self.samples) < 2:
            return 0.0
        return self.samples[-1].t - self.samples[0].t

    def get_normalized_slice(self) -> List[PlayerActionSample]:
        """Return samples rebased so the oldest sample begins at t = 0.0."""
        if not self.samples:
            return []
        start_t = self.samples[0].t
        return [
            PlayerActionSample(
                s.t - start_t,
                s.x,
                s.y,
                s.aim_x,
                s.aim_y,
                s.fired,
                s.dashing,
            )
            for s in self.samples
        ]

    def clear(self):
        self.samples.clear()


class Echo(Entity):
    """
    A holographic temporal projection that replays a recorded sequence once
    and holds its position briefly before fading away.
    """

    STATE_REPLAYING = "replaying"
    STATE_HOLDING = "holding"
    STATE_EXPIRED = "expired"

    def __init__(
        self,
        owner_id: int,
        samples: List[PlayerActionSample],
        echo_id: Optional[int] = None,
        hold_time: float = ECHO_POST_REPLAY_HOLD_TIME,
    ):
        first_pos = (samples[0].x, samples[0].y) if samples else (0.0, 0.0)
        super().__init__(first_pos[0], first_pos[1], radius=ECHO_RADIUS, entity_id=echo_id)
        self.owner_id = owner_id
        self.samples = samples
        self.total_replay_duration = samples[-1].t if samples else 0.0
        self.playback_time = 0.0
        self.state = self.STATE_REPLAYING if self.total_replay_duration > 0 else self.STATE_HOLDING
        self.hold_time = float(hold_time)
        self.hold_timer = float(hold_time)
        self.aim_direction = Vec2(1, 0)
        self.is_dashing = False
        self.fired_indices: Set[int] = set()
        self.fade_alpha = 1.0  # 1.0 = fully visible hologram, 0.0 = vanished

        if samples:
            self.aim_direction = Vec2(samples[0].aim_x, samples[0].aim_y).normalize()

    def update(self, dt: float) -> List[Dict]:
        """
        Advance echo playback by dt.
        Returns a list of shot requests to spawn: [{'x': ..., 'y': ..., 'dir_x': ..., 'dir_y': ...}]
        """
        spawned_shots = []

        if self.state == self.STATE_REPLAYING:
            self.playback_time += dt

            # Check for fired shots during this playback interval
            for idx, s in enumerate(self.samples):
                if s.fired and idx not in self.fired_indices and s.t <= self.playback_time:
                    self.fired_indices.add(idx)
                    spawned_shots.append({
                        "x": s.x + s.aim_x * 20.0,
                        "y": s.y + s.aim_y * 20.0,
                        "dir_x": s.aim_x,
                        "dir_y": s.aim_y,
                    })

            if self.playback_time >= self.total_replay_duration:
                # Replay finished; lock to final recorded sample and begin holding position
                if self.samples:
                    last = self.samples[-1]
                    self.position.x = last.x
                    self.position.y = last.y
                    self.aim_direction = Vec2(last.aim_x, last.aim_y).normalize()
                self.state = self.STATE_HOLDING
            else:
                self._interpolate_playback(self.playback_time)

        elif self.state == self.STATE_HOLDING:
            self.hold_timer -= dt
            if self.hold_timer <= ECHO_FADE_WARNING_TIME:
                self.fade_alpha = max(0.0, self.hold_timer / max(0.01, ECHO_FADE_WARNING_TIME))

            if self.hold_timer <= 0:
                self.state = self.STATE_EXPIRED
                self.active = False

        return spawned_shots

    def _interpolate_playback(self, t: float):
        """Interpolate smooth position and aim along the recorded route."""
        if not self.samples:
            return

        if t <= self.samples[0].t:
            first = self.samples[0]
            self.position.x = first.x
            self.position.y = first.y
            self.aim_direction = Vec2(first.aim_x, first.aim_y).normalize()
            self.is_dashing = first.dashing
            return

        if t >= self.samples[-1].t:
            last = self.samples[-1]
            self.position.x = last.x
            self.position.y = last.y
            self.aim_direction = Vec2(last.aim_x, last.aim_y).normalize()
            self.is_dashing = last.dashing
            return

        # Binary search or scan for interval
        low = 0
        high = len(self.samples) - 1
        while low <= high:
            mid = (low + high) // 2
            if self.samples[mid].t <= t:
                low = mid + 1
            else:
                high = mid - 1

        idx0 = max(0, high)
        idx1 = min(len(self.samples) - 1, idx0 + 1)
        s0 = self.samples[idx0]
        s1 = self.samples[idx1]

        dt_segment = s1.t - s0.t
        factor = (t - s0.t) / dt_segment if dt_segment > 1e-5 else 0.0
        factor = clamp(factor, 0.0, 1.0)

        self.position.x = lerp(s0.x, s1.x, factor)
        self.position.y = lerp(s0.y, s1.y, factor)

        interp_aim_x = lerp(s0.aim_x, s1.aim_x, factor)
        interp_aim_y = lerp(s0.aim_y, s1.aim_y, factor)
        aim = Vec2(interp_aim_x, interp_aim_y)
        if aim.length_squared() > 1e-4:
            self.aim_direction = aim.normalize()

        self.is_dashing = s0.dashing or s1.dashing

    def to_dict(self) -> dict:
        d = super().to_dict()
        d.update({
            "owner": self.owner_id,
            "state": self.state,
            "aim_x": round(self.aim_direction.x, 2),
            "aim_y": round(self.aim_direction.y, 2),
            "alpha": round(self.fade_alpha, 2),
            "is_holding": self.state == self.STATE_HOLDING,
            "dashing": self.is_dashing,
        })
        return d


class EchoManager:
    """Manages active echoes for all players, enforcing limits and lifetimes."""

    def __init__(self, max_per_player: int = MAX_ECHOES_PER_PLAYER):
        self.max_per_player = max_per_player
        self.player_echoes: Dict[int, List[Echo]] = {}

    def get_echoes_for_player(self, player_id: int) -> List[Echo]:
        return self.player_echoes.get(player_id, [])

    def get_all_echoes(self) -> List[Echo]:
        all_e = []
        for echo_list in self.player_echoes.values():
            all_e.extend(echo_list)
        return all_e

    def spawn_echo(
        self,
        player_id: int,
        recorder: ActionRecorder,
        hold_time: float = ECHO_POST_REPLAY_HOLD_TIME,
    ) -> Optional[Echo]:
        if not recorder.has_enough_history(min_duration=0.5):
            return None

        samples = recorder.get_normalized_slice()
        if not samples:
            return None

        echo_list = self.player_echoes.setdefault(player_id, [])

        # Enforce MAX_ECHOES_PER_PLAYER: replace the oldest echo
        while len(echo_list) >= self.max_per_player:
            oldest = echo_list.pop(0)
            oldest.active = False

        new_echo = Echo(owner_id=player_id, samples=samples, hold_time=hold_time)
        echo_list.append(new_echo)
        return new_echo

    def update(self, dt: float) -> List[Dict]:
        """
        Updates all active echoes.
        Returns a list of dicts with new projectiles to spawn:
        [{'owner_id': ..., 'x': ..., 'y': ..., 'dir_x': ..., 'dir_y': ...}]
        """
        all_shots = []

        for p_id, echo_list in list(self.player_echoes.items()):
            remaining = []
            for echo in echo_list:
                shots = echo.update(dt)
                for s in shots:
                    s["owner_id"] = p_id
                    all_shots.append(s)

                if echo.active:
                    remaining.append(echo)

            self.player_echoes[p_id] = remaining

        return all_shots

    def clear(self):
        self.player_echoes.clear()
