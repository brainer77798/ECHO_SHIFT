"""
Procedural sci-fi sound effects synthesizer with graceful fallback.
Requires zero external audio files.
"""

import io
import math
import struct
import wave
from typing import Dict, Optional, Any


class AudioManager:
    """Synthesizes retro-futuristic sci-fi sound effects in memory using PCM wave buffers."""

    def __init__(self):
        self.enabled = False
        self.sounds: Dict[str, Any] = {}
        self._init_mixer()

    def _init_mixer(self):
        try:
            import pygame
            if not pygame.mixer.get_init():
                pygame.mixer.init(frequency=22050, size=-16, channels=1, buffer=512)
            self.enabled = True
            self._generate_all_sounds()
        except Exception:
            # No audio device available or mixer failed; fail gracefully
            self.enabled = False

    def _generate_all_sounds(self):
        import pygame

        self.sounds["shoot"] = pygame.mixer.Sound(self._synthesize_sweep(880, 220, 0.12, decay=True))
        self.sounds["echo_shoot"] = pygame.mixer.Sound(self._synthesize_sweep(520, 180, 0.16, decay=True, harmonic=True))
        self.sounds["echo_spawn"] = pygame.mixer.Sound(self._synthesize_warp(0.28))
        self.sounds["hit"] = pygame.mixer.Sound(self._synthesize_noise_blip(0.08))
        self.sounds["explosion"] = pygame.mixer.Sound(self._synthesize_explosion(0.35))
        self.sounds["switch_click"] = pygame.mixer.Sound(self._synthesize_chime(660, 0.14))
        self.sounds["dash"] = pygame.mixer.Sound(self._synthesize_whoosh(0.18))
        self.sounds["boss_alarm"] = pygame.mixer.Sound(self._synthesize_alarm(0.40))

        # Set balanced default volume
        for s in self.sounds.values():
            s.set_volume(0.4)

    def _make_wav_bytes(self, samples: list, sample_rate: int = 22050) -> io.BytesIO:
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            # Pack 16-bit signed PCM
            raw_data = struct.pack(f"<{len(samples)}h", *samples)
            wf.writeframes(raw_data)
        buf.seek(0)
        return buf

    def _synthesize_sweep(self, start_hz: float, end_hz: float, duration: float, decay: bool = True, harmonic: bool = False) -> io.BytesIO:
        sample_rate = 22050
        num_samples = int(sample_rate * duration)
        samples = []
        phase = 0.0

        for i in range(num_samples):
            t = i / num_samples
            freq = start_hz + (end_hz - start_hz) * t
            phase += 2.0 * math.pi * freq / sample_rate
            val = math.sin(phase)
            if harmonic:
                val = 0.7 * val + 0.3 * math.sin(phase * 1.5)

            env = (1.0 - t) if decay else 1.0
            val *= env
            sample_val = int(val * 16000)
            sample_val = max(-32767, min(32767, sample_val))
            samples.append(sample_val)

        return self._make_wav_bytes(samples, sample_rate)

    def _synthesize_warp(self, duration: float) -> io.BytesIO:
        sample_rate = 22050
        num_samples = int(sample_rate * duration)
        samples = []
        phase = 0.0

        for i in range(num_samples):
            t = i / num_samples
            freq = 240.0 + 400.0 * math.sin(t * math.pi)
            phase += 2.0 * math.pi * freq / sample_rate
            val = math.sin(phase) * math.sin(t * math.pi)
            sample_val = int(val * 18000)
            samples.append(max(-32767, min(32767, sample_val)))

        return self._make_wav_bytes(samples, sample_rate)

    def _synthesize_noise_blip(self, duration: float) -> io.BytesIO:
        sample_rate = 22050
        num_samples = int(sample_rate * duration)
        samples = []
        import random

        for i in range(num_samples):
            t = i / num_samples
            env = (1.0 - t) ** 2
            noise = random.uniform(-1.0, 1.0)
            tone = math.sin(2.0 * math.pi * 320.0 * (i / sample_rate))
            val = (0.5 * noise + 0.5 * tone) * env
            sample_val = int(val * 18000)
            samples.append(max(-32767, min(32767, sample_val)))

        return self._make_wav_bytes(samples, sample_rate)

    def _synthesize_explosion(self, duration: float) -> io.BytesIO:
        sample_rate = 22050
        num_samples = int(sample_rate * duration)
        samples = []
        import random
        filter_val = 0.0

        for i in range(num_samples):
            t = i / num_samples
            env = (1.0 - t) ** 1.8
            raw = random.uniform(-1.0, 1.0)
            # Low-pass filter for rumbling bass explosion
            filter_val += (raw - filter_val) * 0.18
            val = filter_val * env
            sample_val = int(val * 24000)
            samples.append(max(-32767, min(32767, sample_val)))

        return self._make_wav_bytes(samples, sample_rate)

    def _synthesize_chime(self, freq: float, duration: float) -> io.BytesIO:
        sample_rate = 22050
        num_samples = int(sample_rate * duration)
        samples = []
        phase = 0.0

        for i in range(num_samples):
            t = i / num_samples
            phase += 2.0 * math.pi * freq / sample_rate
            env = math.exp(-6.0 * t)
            val = math.sin(phase) * env
            sample_val = int(val * 16000)
            samples.append(max(-32767, min(32767, sample_val)))

        return self._make_wav_bytes(samples, sample_rate)

    def _synthesize_whoosh(self, duration: float) -> io.BytesIO:
        sample_rate = 22050
        num_samples = int(sample_rate * duration)
        samples = []
        import random
        lp = 0.0

        for i in range(num_samples):
            t = i / num_samples
            env = math.sin(t * math.pi)
            raw = random.uniform(-1.0, 1.0)
            lp += (raw - lp) * (0.1 + 0.3 * t)
            val = lp * env
            sample_val = int(val * 18000)
            samples.append(max(-32767, min(32767, sample_val)))

        return self._make_wav_bytes(samples, sample_rate)

    def _synthesize_alarm(self, duration: float) -> io.BytesIO:
        sample_rate = 22050
        num_samples = int(sample_rate * duration)
        samples = []
        phase = 0.0

        for i in range(num_samples):
            t = i / num_samples
            freq = 280.0 if (int(t * 8) % 2 == 0) else 440.0
            phase += 2.0 * math.pi * freq / sample_rate
            val = math.sin(phase) * (1.0 - t * 0.5)
            sample_val = int(val * 16000)
            samples.append(max(-32767, min(32767, sample_val)))

        return self._make_wav_bytes(samples, sample_rate)

    def play(self, name: str):
        if not self.enabled:
            return
        snd = self.sounds.get(name)
        if snd:
            try:
                snd.play()
            except Exception:
                pass


# Global singleton instance
audio = AudioManager()
