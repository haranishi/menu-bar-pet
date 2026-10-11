use std::collections::HashMap;
use std::ptr;

unsafe extern "C" {
    fn mach_host_self() -> libc::mach_port_t;
    static mach_task_self_: libc::mach_port_t;
    fn mach_port_deallocate(
        task: libc::mach_port_t,
        name: libc::mach_port_t,
    ) -> libc::kern_return_t;
    fn host_page_size(host: libc::mach_port_t, size: *mut libc::vm_size_t) -> libc::kern_return_t;
}
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct CpuSampler {
    pub ticks: [u32; 4],
    pub initialized: u32,
}
impl CpuSampler {
    pub fn consume(&mut self, ticks: [u32; 4]) -> f64 {
        let prior = self.ticks;
        self.ticks = ticks;
        if self.initialized == 0 {
            self.initialized = 1;
            return f64::NAN;
        }
        let delta: [u64; 4] = std::array::from_fn(|i| u64::from(ticks[i].wrapping_sub(prior[i])));
        let total: u64 = delta.iter().sum();
        if total == 0 {
            return f64::NAN;
        }
        (delta[0] + delta[1] + delta[3]) as f64 / total as f64 * 100.0
    }
}
/// # Safety
/// sampler points to an initialized, exclusively borrowed CpuSampler.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbp_cpu_sample(sampler: *mut CpuSampler) -> f64 {
    let Some(sampler) = (unsafe { sampler.as_mut() }) else {
        return f64::NAN;
    };
    let mut info: libc::host_cpu_load_info = unsafe { std::mem::zeroed() };
    let mut count = libc::HOST_CPU_LOAD_INFO_COUNT;
    let host = unsafe { mach_host_self() };
    let result = unsafe {
        libc::host_statistics(
            host,
            libc::HOST_CPU_LOAD_INFO,
            ptr::from_mut(&mut info).cast(),
            &mut count,
        )
    };
    unsafe { mach_port_deallocate(mach_task_self_, host) };
    if result != 0 {
        return f64::NAN;
    }
    sampler.consume(info.cpu_ticks)
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_memory_usage() -> u32 {
    let mut info: libc::vm_statistics64 = unsafe { std::mem::zeroed() };
    let mut count = libc::HOST_VM_INFO64_COUNT;
    let mut page_size = 0;
    let host = unsafe { mach_host_self() };
    let result = unsafe {
        libc::host_statistics64(
            host,
            libc::HOST_VM_INFO64,
            ptr::from_mut(&mut info).cast(),
            &mut count,
        )
    };
    let page_result = unsafe { host_page_size(host, &mut page_size) };
    unsafe { mach_port_deallocate(mach_task_self_, host) };
    if result != 0 || page_result != 0 {
        return 0;
    }
    let mut total = 0u64;
    let mut length = std::mem::size_of::<u64>();
    let mut mib = [libc::CTL_HW, libc::HW_MEMSIZE];
    if unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            2,
            ptr::from_mut(&mut total).cast(),
            &mut length,
            ptr::null_mut(),
            0,
        )
    } != 0
        || total == 0
    {
        return 0;
    }
    let pages = u64::from(info.active_count)
        + u64::from(info.inactive_count)
        + u64::from(info.wire_count)
        + u64::from(info.compressor_page_count);
    ((pages as f64 * page_size as f64 / total as f64 * 100.0)
        .round()
        .clamp(0.0, 100.0)) as u32
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct NetworkSample {
    pub received: f64,
    pub sent: f64,
}
#[derive(Default)]
pub struct NetworkSampler {
    previous: HashMap<u16, (u64, u64)>,
    previous_time: Option<f64>,
}
impl NetworkSampler {
    pub fn consume(&mut self, counters: HashMap<u16, (u64, u64)>, now: f64) -> NetworkSample {
        let elapsed = self.previous_time.map(|old| now - old).unwrap_or(0.0);
        let mut sample = NetworkSample::default();
        if elapsed.is_finite() && elapsed > 0.0 {
            for (index, (received, sent)) in &counters {
                if let Some((old_received, old_sent)) = self.previous.get(index) {
                    sample.received += received.saturating_sub(*old_received) as f64 / elapsed;
                    sample.sent += sent.saturating_sub(*old_sent) as f64 / elapsed;
                }
            }
        }
        self.previous = counters;
        self.previous_time = Some(now);
        sample
    }
}
fn network_counters() -> Option<HashMap<u16, (u64, u64)>> {
    let mut mib = [
        libc::CTL_NET,
        libc::PF_ROUTE,
        0,
        libc::AF_UNSPEC,
        libc::NET_RT_IFLIST2,
        0,
    ];
    let mut size = 0;
    if unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            6,
            ptr::null_mut(),
            &mut size,
            ptr::null_mut(),
            0,
        )
    } != 0
    {
        return None;
    }
    let mut bytes = vec![0u8; size];
    if unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            6,
            bytes.as_mut_ptr().cast(),
            &mut size,
            ptr::null_mut(),
            0,
        )
    } != 0
    {
        return None;
    }
    bytes.truncate(size);
    let mut result = HashMap::new();
    let mut offset = 0;
    while offset + 4 <= bytes.len() {
        let len = u16::from_ne_bytes([bytes[offset], bytes[offset + 1]]) as usize;
        if len < 4 || offset + len > bytes.len() {
            break;
        }
        if bytes[offset + 3] == libc::RTM_IFINFO2 as u8
            && len >= std::mem::size_of::<libc::if_msghdr2>()
        {
            let info = unsafe {
                bytes
                    .as_ptr()
                    .add(offset)
                    .cast::<libc::if_msghdr2>()
                    .read_unaligned()
            };
            if info.ifm_flags & libc::IFF_LOOPBACK == 0 && info.ifm_flags & libc::IFF_UP != 0 {
                result.insert(
                    info.ifm_index,
                    (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes),
                );
            }
        }
        offset += len;
    }
    Some(result)
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_network_new() -> *mut NetworkSampler {
    Box::into_raw(Box::new(NetworkSampler::default()))
}
/// # Safety
/// sampler is a live, exclusively borrowed pointer from mbp_network_new.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbp_network_sample(
    sampler: *mut NetworkSampler,
    now: f64,
) -> NetworkSample {
    let Some(sampler) = (unsafe { sampler.as_mut() }) else {
        return NetworkSample::default();
    };
    network_counters()
        .map(|c| sampler.consume(c, now))
        .unwrap_or_default()
}
/// # Safety
/// sampler came from mbp_network_new and has not been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbp_network_free(sampler: *mut NetworkSampler) {
    if !sampler.is_null() {
        drop(unsafe { Box::from_raw(sampler) });
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cpu_ticks_wrap_and_first_sample_is_baseline() {
        let mut sampler = CpuSampler::default();
        assert!(sampler.consume([u32::MAX - 1, 0, 100, 0]).is_nan());
        assert!((sampler.consume([3, 0, 105, 0]) - 50.0).abs() < 1e-12);
        assert!(sampler.consume([3, 0, 105, 0]).is_nan());
    }
    #[test]
    fn network_is_64_bit_and_resets_do_not_spike() {
        let mut sampler = NetworkSampler::default();
        assert_eq!(
            sampler
                .consume(HashMap::from([(1, (1u64 << 34, 100))]), 1.0)
                .received,
            0.0
        );
        assert_eq!(
            sampler
                .consume(HashMap::from([(1, ((1u64 << 34) + 1000, 120))]), 3.0)
                .received,
            500.0
        );
        assert_eq!(
            sampler
                .consume(HashMap::from([(1, (20, 10)), (2, (u64::MAX, 0))]), 4.0)
                .received,
            0.0
        );
        assert_eq!(
            sampler
                .consume(HashMap::from([(1, (30, 20))]), 4.0)
                .received,
            0.0
        );
    }
    #[test]
    fn native_sampling_does_not_require_external_services() {
        let mut cpu = CpuSampler::default();
        let _ = unsafe { mbp_cpu_sample(&mut cpu) };
        assert!(mbp_memory_usage() <= 100);
        let sampler = mbp_network_new();
        assert_eq!(unsafe { mbp_network_sample(sampler, 1.0) }.received, 0.0);
        unsafe { mbp_network_free(sampler) };
    }
}
