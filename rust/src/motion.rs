use std::f64::consts::PI;

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}
impl Rect {
    fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }
}
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct HamsterFrame {
    pub wheel_angle: f64,
    pub front: f64,
    pub rear: f64,
    pub intensity: f64,
    pub body_offset: f64,
    pub breathing: f64,
    pub overlay_pulse: f64,
    pub bounds: Rect,
}
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct ShibaFrame {
    pub front: f64,
    pub rear: f64,
    pub bounce: f64,
    pub breathing: f64,
    pub scale_x: f64,
    pub scale_y: f64,
    pub lean: f64,
    pub tail: f64,
    pub shadow_scale: f64,
    pub shadow_opacity: f64,
    pub overlay_pulse: f64,
    pub overlay: Rect,
    pub bounds: Rect,
    pub has_overlay: u32,
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_phase(phase: f64) -> f64 {
    if !phase.is_finite() {
        return 0.0;
    }
    let remainder = phase % 1.0;
    if remainder >= 0.0 {
        remainder
    } else {
        remainder + 1.0
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_cycle_duration(cpu: f64) -> f64 {
    2.2 - 1.75
        * (if cpu.is_finite() {
            cpu.clamp(0.0, 100.0)
        } else {
            0.0
        })
        / 100.0
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_fps(state: u32, cpu: f64, frame_count: i64) -> f64 {
    let minimum = match state {
        0 => 8.0,
        1 | 2 => 12.0,
        _ => 15.0,
    };
    ((frame_count.max(12) as f64) / mbp_cycle_duration(cpu)).clamp(minimum, 30.0)
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_frame_index(phase: f64, frame_count: i64) -> i64 {
    if frame_count <= 0 {
        return 0;
    }
    ((mbp_phase(phase) * frame_count as f64).floor() as i64).clamp(0, frame_count - 1)
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_amplitude(state: u32) -> f64 {
    match state {
        0 => 0.5,
        1 => 1.5,
        2 => 2.5,
        3 => 3.0,
        _ => 3.5,
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_wheel_cycle(cpu: f64) -> f64 {
    mbp_cycle_duration(cpu).max(0.9)
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_wheel_increment(elapsed: f64, cpu: f64) -> f64 {
    if !elapsed.is_finite() || elapsed <= 0.0 {
        0.0
    } else {
        (elapsed / mbp_wheel_cycle(cpu)).min(0.07)
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_wheel_angle(state: u32, phase: f64) -> f64 {
    if state == 0 {
        0.0
    } else {
        -2.0 * PI * mbp_phase(phase)
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_bounce(phase: f64) -> f64 {
    let p = mbp_phase(phase);
    let t = if p < 0.35 { p / 0.35 } else { (1.0 - p) / 0.65 };
    // Zero velocity at contact, flight apex and the loop seam.
    // A small bias keeps the brisk take-off / longer landing timing.
    0.5 - 0.5 * (PI * t).cos() + 0.08 * (PI * t).sin().powi(2)
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_scaled_body_extent(state: u32) -> Rect {
    let (extent, x, y) = if state == 0 {
        (Rect::new(16.25, 4.15, 11.95, 8.8), 25.9, 4.5)
    } else {
        (Rect::new(15.22, 2.7, 13.42, 11.3), 24.2, 4.13)
    };
    Rect::new(
        x + (extent.x - x) * 1.45,
        y + (extent.y - y) * 1.45,
        extent.width * 1.45,
        extent.height * 1.45,
    )
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_hamster_frame(
    state: u32,
    phase: f64,
    wheel_phase: f64,
    reduce_motion: u32,
) -> HamsterFrame {
    let reduce = reduce_motion != 0;
    let p = if reduce { 0.0 } else { mbp_phase(phase) };
    let wheel = if reduce { 0.0 } else { mbp_phase(wheel_phase) };
    let front = mbp_phase(p * 2.0);
    let resting = state == 0;
    let intensity = mbp_amplitude(state) / 3.5;
    HamsterFrame {
        wheel_angle: mbp_wheel_angle(state, wheel),
        front,
        rear: mbp_phase(front + 0.5),
        intensity,
        body_offset: if resting || reduce {
            0.0
        } else {
            0.5 * intensity * (p * 4.0 * PI).sin()
        },
        breathing: if resting && !reduce {
            0.3 * (p * 2.0 * PI).sin()
        } else {
            0.0
        },
        overlay_pulse: if reduce {
            1.0
        } else {
            1.0 + 0.15 * (p * 2.0 * PI).sin()
        },
        bounds: match state {
            3 => Rect::new(10.3, 0.1, 23.7, 21.6),
            4 => Rect::new(2.7, 0.1, 29.0, 21.6),
            _ => Rect::new(10.3, 0.1, 21.4, 21.6),
        },
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_shiba_frame(state: u32, phase: f64, reduce_motion: u32) -> ShibaFrame {
    let reduce = reduce_motion != 0;
    let p = if reduce { 0.0 } else { mbp_phase(phase) };
    let resting = state == 0;
    let intensity = mbp_amplitude(state) / 3.5;
    let breathing = if resting && !reduce {
        0.3 * (p * 2.0 * PI).sin()
    } else {
        0.0
    };
    let bounce = if resting || reduce {
        0.0
    } else {
        mbp_bounce(p) * (0.65 + intensity)
    };
    let airborne = bounce / 1.65;
    ShibaFrame {
        front: if resting { 0.0 } else { mbp_phase(p + 0.1) },
        rear: if resting { 0.0 } else { mbp_phase(p + 0.6) },
        bounce,
        breathing,
        scale_x: if resting {
            1.0
        } else {
            1.025 - airborne * 0.025
        },
        scale_y: if resting { 1.0 } else { 0.96 + airborne * 0.08 },
        lean: if resting { 0.0 } else { intensity * 0.8 },
        tail: if resting || reduce {
            0.0
        } else {
            0.35 * (p * 2.0 * PI - 0.6).sin()
        },
        shadow_scale: if resting {
            0.92 + breathing * 0.025
        } else {
            1.0 - airborne * 0.22
        },
        shadow_opacity: if resting {
            0.11
        } else {
            0.16 - airborne * 0.07
        },
        overlay_pulse: if reduce || !matches!(state, 3 | 4) {
            1.0
        } else {
            1.0 + 0.15 * (p * 2.0 * PI).sin()
        },
        overlay: match state {
            3 => Rect::new(37.7, 16.7, 4.3, 5.3),
            4 => Rect::new(0.3, 2.8, 5.7, 13.1),
            _ => Rect::default(),
        },
        bounds: match state {
            0 => Rect::new(5.2, 2.0, 32.2, 18.8),
            3 => Rect::new(3.8, 1.2, 37.9, 20.5),
            4 => Rect::new(0.3, 1.2, 39.9, 19.6),
            _ => Rect::new(3.8, 1.2, 36.4, 19.6),
        },
        has_overlay: u32::from(matches!(state, 3 | 4)),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn phase_speed_and_wheel_are_bounded() {
        for cpu in [-10.0, 0.0, 25.0, 50.0, 100.0, 1000.0, f64::NAN] {
            assert!((0.45 - 1e-12..=2.2).contains(&mbp_cycle_duration(cpu)));
            assert!(mbp_wheel_increment(3600.0, cpu) <= 0.07);
        }
        assert_eq!(mbp_phase(f64::INFINITY), 0.0);
        assert!((mbp_phase(-0.2) - 0.8).abs() < 1e-12);
    }
    #[test]
    fn reduce_motion_freezes_every_state() {
        for state in 0..5 {
            assert_eq!(
                mbp_shiba_frame(state, 0.3, 1).bounce,
                mbp_shiba_frame(state, 0.8, 1).bounce
            );
            assert_eq!(mbp_shiba_frame(state, 0.3, 1).tail, 0.0);
            assert_eq!(mbp_hamster_frame(state, 0.3, 0.8, 1).wheel_angle, 0.0);
        }
    }
}
