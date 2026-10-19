"""Original, reproducible mono sports foley; no music or third-party recordings."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 24000
ROOT = Path(__file__).resolve().parents[1] / 'audio'
SOUNDS = {
    'bump': (.22, 155, .60, .35), 'set': (.16, 235, .36, .50),
    'spike': (.28, 135, .78, .70), 'serve': (.27, 165, .72, .58),
    'block': (.21, 200, .62, .68), 'ball_floor': (.30, 125, .80, .26),
    'ball_wall': (.24, 170, .70, .44), 'ball_net': (.36, 70, .22, .95),
    'step_1': (.14, 92, .30, .50), 'step_2': (.15, 103, .30, .45),
    'step_3': (.13, 87, .29, .54), 'land': (.26, 80, .55, .62),
    'pickup': (.15, 255, .24, .47), 'toss': (.16, 210, .20, .40),
    'throw': (.22, 155, .24, .70), 'jump': (.18, 130, .22, .68),
    'dive': (.50, 85, .38, .95), 'skid': (.24, 540, .12, .95),
    'swing': (.20, 170, .10, .98),
    'ui_tap': (.045, 760, .14, .15), 'ui_open': (.11, 680, .14, .10),
    'ui_close': (.10, 540, .13, .10), 'ui_tick': (.035, 900, .10, .10),
    'whistle': (.42, 2550, .25, .10), 'point': (.15, 880, .16, .04),
    'join': (.16, 620, .14, .04), 'leave': (.15, 460, .14, .04),
}


def synth(name, duration, hz, loudness, noise_mix, seed):
    rng = random.Random(seed)
    count = round(duration * RATE)
    low = 0.0
    smooth = 0.0
    phase = 0.0
    samples = []
    for i in range(count):
        t = i / RATE
        u = t / duration
        raw = rng.uniform(-1, 1)
        low += .14 * (raw - low)
        smooth += .045 * (raw - smooth)
        band = low - smooth
        freq = hz * (1 + .7 * math.exp(-t * 90))
        phase += 2 * math.pi * freq / RATE
        tone = math.sin(phase) * .70 + math.sin(phase * 1.69) * .18
        attack = min(1.0, t / .0015)
        envelope = attack * math.exp(-u * 8.5) * min(1, (duration - t) / .012)
        sound = (tone * (1 - noise_mix) + band * 4.0 * noise_mix) * envelope
        # Hollow inflated ball: two coupled membrane resonances plus a palm click.
        if name in ('spike', 'serve', 'block', 'bump', 'ball_floor', 'ball_wall'):
            sound += .24 * math.sin(2 * math.pi * hz * .52 * t) * math.exp(-t * 32)
            sound += raw * .16 * math.exp(-t * 450)
        # Shoe friction and clothes use shaped noise, without cartoon pitch glides.
        if name in ('dive', 'swing', 'skid', 'jump', 'throw'):
            shape = math.sin(math.pi * u) ** 1.6 * math.exp(-u * 2.5)
            sound = band * 4.0 * shape + tone * .045 * envelope
            if name == 'skid':
                sound += math.sin(phase * 2.7) * .20 * shape
        if name == 'ball_net':
            sound = band * 3 * envelope + raw * .20 * math.exp(-u * 6) * (math.sin(t * 83) ** 2)
        if name == 'whistle':
            envelope = min(1, t / .025) * min(1, (duration - t) / .07)
            vibrato = .9 + .1 * math.sin(t * 2 * math.pi * 26)
            sound = (math.sin(2 * math.pi * hz * t + .32 * math.sin(t * 93)) * .7 + math.sin(2 * math.pi * hz * 1.015 * t) * .25 + band * .35) * envelope * vibrato
        sound *= loudness * min(1, t / .001) * min(1, (duration - t) / .008)
        samples.append(sound)
    peak = max(abs(s) for s in samples)
    scale = min(1, .88 / max(peak, .001))
    return b''.join(struct.pack('<h', round(s * scale * 32767)) for s in samples)


def main():
    ROOT.mkdir(exist_ok=True)
    for index, (name, values) in enumerate(SOUNDS.items()):
        with wave.open(str(ROOT / (name + '.wav')), 'wb') as output:
            output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
            output.writeframes(synth(name, *values, seed=31000 + index))
    print(f'Generated {len(SOUNDS)} original short sound effects; no loops or music.')


if __name__ == '__main__':
    main()
