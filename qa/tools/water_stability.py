"""Reproduce the analytic water-footprint numbers in qa/water-stability.md."""

from math import atan, cos, pi, radians, sin, sqrt, tan


WAVES = (
    (18.0, (0.970143, 0.242536), 0.100, 0.36),
    (9.0, (-0.554700, 0.832050), 0.052, 0.48),
    (4.5, (0.196116, -0.980581), 0.025, 0.64),
    (2.2, (0.780869, 0.624695), 0.011, 0.86),
    (1.1, (-0.894427, -0.447214), 0.004, 1.12),
)


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    t = min(1.0, max(0.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def pixel_footprint(distance: float, elevation_deg: float, fovy_deg: float, height: int):
    """Conservative adjacent-pixel X/Z footprint on a horizontal plane at image centre."""
    beta = radians(elevation_deg)
    angular_pixel = atan(2.0 * tan(radians(fovy_deg) * 0.5) / height)
    camera_height = distance * sin(beta)
    forward = distance * cos(beta)
    lateral = distance * tan(angular_pixel)
    forward_steps = (
        abs(camera_height / tan(beta + angular_pixel) - forward),
        abs(camera_height / tan(beta - angular_pixel) - forward),
    )
    return lateral, max(forward_steps)


def resolved_weight(phase_footprint: float) -> float:
    return 1.0 - smoothstep(0.35 * pi, pi, phase_footprint)


def row(distance: float, elevation_deg=10.0, fovy_deg=70.0, height=1080):
    dx, dz = pixel_footprint(distance, elevation_deg, fovy_deg, height)
    phase_pi = []
    weights = []
    unresolved_layers = 0.0
    unresolved_slope = 0.0
    for wavelength, direction, amplitude, _speed in WAVES:
        wave_number = 2.0 * pi / wavelength
        footprint = max(wave_number * abs(direction[0]) * dx,
                        wave_number * abs(direction[1]) * dz)
        weight = resolved_weight(footprint)
        phase_pi.append(footprint / pi)
        weights.append(weight)
        unresolved_layers += 1.0 - weight
        unresolved_slope += amplitude * wave_number * (1.0 - weight)
    roughness = min(0.30, max(0.035, 0.035 + 0.030 * unresolved_layers
                              + 0.55 * unresolved_slope))
    return dx, dz, phase_pi, weights, roughness


if __name__ == "__main__":
    print("wave  lambda  direction              amplitude speed  omega@100% period")
    for index, (wavelength, direction, amplitude, speed) in enumerate(WAVES):
        omega = sqrt(9.81 * 2.0 * pi / wavelength) * speed
        print(f"{index:>4} {wavelength:>7.2f}  ({direction[0]: .6f},{direction[1]: .6f})"
              f"  {amplitude:>8.3f} {speed:>5.2f}  {omega:>10.6f} {2*pi/omega:>6.3f}s")

    print("\ndistance dx       dz       phase/pi by wave                    resolved by wave                    roughness")
    for distance in (32.0, 64.0, 128.0, 256.0):
        dx, dz, phase_pi, weights, roughness = row(distance)
        print(f"{distance:>8.0f} {dx:>8.5f} {dz:>8.5f}  "
              + " ".join(f"{value:>6.3f}" for value in phase_pi) + "    "
              + " ".join(f"{value:>6.3f}" for value in weights)
              + f"    {roughness:.6f}")

    slope_sum = sum(amplitude * 2.0 * pi / wavelength
                    for wavelength, _direction, amplitude, _speed in WAVES)
    print("\nfully unresolved roughness by WATER_WAVE_HEIGHT:")
    for height_percent in (25, 100, 200):
        roughness = min(0.30, 0.035 + 0.030 * len(WAVES)
                        + 0.55 * slope_sum * height_percent / 100.0)
        print(f"  {height_percent:>3}%: {roughness:.6f}")

    epsilon = 1e-7
    for boundary, expected in ((0.35 * pi, 1.0), (pi, 0.0)):
        left = resolved_weight(boundary - epsilon)
        centre = resolved_weight(boundary)
        right = resolved_weight(boundary + epsilon)
        assert abs(centre - expected) < 1e-12
        assert abs(left - right) < 1e-6
    print("boundary continuity assertions: PASS")
