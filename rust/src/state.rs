#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Machine {
    pub alpha: f64,
    pub smoothed: f64,
    pub state: u32,
    pub candidate: i32,
    pub candidate_count: u32,
    pub has_smoothed: u32,
}
#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Snapshot {
    pub usage: f64,
    pub smoothed: f64,
    pub state: u32,
}

pub fn classify(usage: f64, thresholds: &[f64; 4]) -> u32 {
    thresholds.iter().position(|t| usage < *t).unwrap_or(4) as u32
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_machine_new(alpha: f64) -> Machine {
    Machine {
        alpha: if alpha.is_finite() {
            alpha.clamp(0.01, 1.0)
        } else {
            0.35
        },
        smoothed: 0.0,
        state: 1,
        candidate: -1,
        candidate_count: 0,
        has_smoothed: 0,
    }
}
impl Machine {
    pub fn ingest(&mut self, raw: f64, thresholds: [f64; 4]) -> Snapshot {
        let usage = if raw.is_finite() {
            raw.clamp(0.0, 100.0)
        } else {
            0.0
        };
        let smoothed = if self.has_smoothed != 0 {
            self.alpha * usage + (1.0 - self.alpha) * self.smoothed
        } else {
            usage
        };
        self.smoothed = smoothed;
        self.has_smoothed = 1;
        let upward = classify(smoothed, &thresholds);
        let downward = classify(smoothed, &thresholds.map(|t| (t - 5.0).max(0.0)));
        let target = if upward > self.state {
            upward
        } else {
            downward
        };
        if target == self.state {
            self.candidate = -1;
            self.candidate_count = 0;
        } else {
            if self.candidate == target as i32 {
                self.candidate_count += 1;
            } else {
                self.candidate = target as i32;
                self.candidate_count = 1;
            }
            if self.candidate_count >= if target > self.state { 3 } else { 5 } {
                self.state = target;
                self.candidate = -1;
                self.candidate_count = 0;
            }
        }
        Snapshot {
            usage,
            smoothed,
            state: self.state,
        }
    }
}
/// # Safety
/// machine points to an initialized, exclusively borrowed Machine.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbp_machine_ingest(
    machine: *mut Machine,
    raw: f64,
    sensitivity: u32,
) -> Snapshot {
    let thresholds = match sensitivity {
        0 => [30.0, 60.0, 80.0, 95.0],
        2 => [10.0, 35.0, 60.0, 80.0],
        _ => [20.0, 50.0, 75.0, 90.0],
    };
    if let Some(machine) = unsafe { machine.as_mut() } {
        machine.ingest(raw, thresholds)
    } else {
        Snapshot {
            usage: 0.0,
            smoothed: 0.0,
            state: 1,
        }
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_classify(usage: f64, a: f64, b: f64, c: f64, d: f64) -> u32 {
    classify(usage, &[a, b, c, d])
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sustained_transitions_and_invalid_input() {
        let mut m = mbp_machine_new(1.0);
        for _ in 0..2 {
            m.ingest(100.0, [20.0, 50.0, 75.0, 90.0]);
        }
        assert_eq!(m.state, 1);
        assert_eq!(m.ingest(100.0, [20.0, 50.0, 75.0, 90.0]).state, 4);
        for _ in 0..4 {
            m.ingest(0.0, [20.0, 50.0, 75.0, 90.0]);
        }
        assert_eq!(m.state, 4);
        assert_eq!(m.ingest(0.0, [20.0, 50.0, 75.0, 90.0]).state, 0);
        let mut m = mbp_machine_new(f64::NAN);
        assert!(
            m.ingest(f64::NAN, [20.0, 50.0, 75.0, 90.0])
                .smoothed
                .is_finite()
        );
    }
}
