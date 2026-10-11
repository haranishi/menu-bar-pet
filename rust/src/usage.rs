use serde_json::{Value, json};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::ptr;

#[repr(C)]
pub struct Buffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}
impl Buffer {
    pub fn from_bytes(mut bytes: Vec<u8>) -> Self {
        let result = Self {
            data: bytes.as_mut_ptr(),
            len: bytes.len(),
            capacity: bytes.capacity(),
        };
        std::mem::forget(bytes);
        result
    }
    pub fn empty() -> Self {
        Self {
            data: ptr::null_mut(),
            len: 0,
            capacity: 0,
        }
    }
}
/// # Safety
/// buffer was returned by this library and has not already been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbp_buffer_free(buffer: Buffer) {
    if !buffer.data.is_null() {
        drop(unsafe { Vec::from_raw_parts(buffer.data, buffer.len, buffer.capacity) });
    }
}
fn number(value: &Value) -> Option<f64> {
    value.as_f64().filter(|n| n.is_finite())
}
fn epoch(value: &Value) -> Option<f64> {
    number(value)
        .filter(|n| *n > 0.0)
        .map(|n| if n > 1e11 { n / 1000.0 } else { n })
}
fn text(value: &Value) -> Option<&str> {
    value.as_str().filter(|s| !s.is_empty())
}
pub fn window_label(minutes: f64) -> String {
    if !minutes.is_finite() || minutes <= 0.0 {
        return "枠".into();
    }
    let (value, unit) = if minutes < 60.0 {
        (minutes, "分")
    } else if minutes < 1440.0 {
        (minutes / 60.0, "時間")
    } else {
        (minutes / 1440.0, "日")
    };
    let rounded = (value * 10.0).round() / 10.0;
    format!("{rounded}{unit}")
}
fn window(label: &str, used: f64, resets: Option<f64>, duration: Option<f64>) -> Value {
    json!({"label":label,"used":used,"resets":resets,"duration":duration})
}
pub fn claude(data: &[u8]) -> Option<Value> {
    let root: Value = serde_json::from_slice(data).ok()?;
    let limits = root.get("rate_limits")?.as_object()?;
    let keys = [
        ("five_hour", "5時間", Some(300.0)),
        ("seven_day", "7日", Some(10080.0)),
        ("spend_limit", "支出上限", None),
    ];
    let windows: Vec<_> = keys
        .iter()
        .filter_map(|(key, label, duration)| {
            let raw = limits.get(*key)?;
            Some(window(
                label,
                number(&raw["used_percentage"])?,
                epoch(&raw["resets_at"]),
                *duration,
            ))
        })
        .collect();
    if windows.is_empty() {
        return None;
    }
    let mut extras = serde_json::Map::new();
    if let Some(model) = text(&root["model"]["display_name"]) {
        extras.insert("model".into(), json!(model));
    }
    if let Some(context) = number(&root["context_window"]["used_percentage"]) {
        extras.insert("context".into(), json!(format!("{}%", context.round())));
    }
    if let Some(cost) = number(&root["cost"]["total_cost_usd"]) {
        extras.insert(
            "cost".into(),
            json!(format!("{currency}{cost:.2}", currency = "$")),
        );
    }
    Some(json!({"windows":windows,"extras":extras}))
}
pub fn codex(data: &[u8]) -> Option<Value> {
    let mut newest: Option<Value> = None;
    let mut newest_timestamp: Option<String> = None;
    let mut windows_timestamp: Option<String> = None;
    let mut windows = Vec::new();
    let mut total: Option<String> = None;
    for line in data.rsplit(|b| *b == b'\n') {
        if !line.windows(11).any(|s| s == b"token_count") {
            continue;
        }
        let Ok(root) = serde_json::from_slice::<Value>(line) else {
            continue;
        };
        if root["type"] != "event_msg" || root["payload"]["type"] != "token_count" {
            continue;
        }
        let payload = &root["payload"];
        let timestamp = text(&root["timestamp"]).map(str::to_owned);
        if newest.is_none() {
            newest = Some(payload.clone());
            newest_timestamp = timestamp.clone();
        }
        if total.is_none() {
            total = number(&payload["info"]["total_token_usage"]["total_tokens"])
                .map(|n| n.round().to_string());
        }
        if windows.is_empty() {
            for key in ["primary", "secondary"] {
                let raw = &payload["rate_limits"][key];
                let Some(used) = number(&raw["used_percent"]) else {
                    continue;
                };
                let minutes = number(&raw["window_minutes"]);
                windows.push(window(
                    &window_label(minutes.unwrap_or(0.0)),
                    used,
                    epoch(&raw["resets_at"]),
                    minutes,
                ));
            }
            if !windows.is_empty() {
                windows_timestamp = timestamp;
            }
        }
        if !windows.is_empty() && total.is_some() {
            break;
        }
    }
    let newest = newest?;
    let mut extras = serde_json::Map::new();
    if let Some(total) = total {
        extras.insert("total_tokens".into(), json!(total));
    }
    let reached = text(&newest["rate_limits"]["rate_limit_reached_type"]);
    let note = reached.map(|reason| {
        extras.insert("rate_limit_reached_type".into(), json!(reason));
        let headline = match reason {
            "workspace_member_credits_depleted" => "クレジット切れ",
            "usage_limit_reached" => "利用上限に到達",
            _ => "利用制限",
        };
        format!("{headline}（{reason}）")
    });
    Some(
        json!({"windows":windows,"extras":extras,"observedText":windows_timestamp.or(newest_timestamp.clone()),"noteText":newest_timestamp,"note":note}),
    )
}
fn parse(data: &[u8], kind: u32) -> Buffer {
    let value = if kind == 0 { claude(data) } else { codex(data) };
    value
        .and_then(|v| serde_json::to_vec(&v).ok())
        .map(Buffer::from_bytes)
        .unwrap_or_else(Buffer::empty)
}
/// # Safety
/// data points to len readable bytes for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbp_usage_parse(data: *const u8, len: usize, kind: u32) -> Buffer {
    if data.is_null() || len == 0 {
        return Buffer::empty();
    }
    parse(unsafe { std::slice::from_raw_parts(data, len) }, kind)
}
/// # Safety
/// path points to len readable UTF-8 bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mbp_read_tail(path: *const u8, len: usize, max_bytes: usize) -> Buffer {
    if path.is_null() {
        return Buffer::empty();
    }
    let bytes = unsafe { std::slice::from_raw_parts(path, len) };
    let Ok(path) = std::str::from_utf8(bytes) else {
        return Buffer::empty();
    };
    let Ok(mut file) = File::open(path) else {
        return Buffer::empty();
    };
    let Ok(end) = file.seek(SeekFrom::End(0)) else {
        return Buffer::empty();
    };
    if file
        .seek(SeekFrom::Start(end.saturating_sub(max_bytes as u64)))
        .is_err()
    {
        return Buffer::empty();
    }
    let mut data = Vec::with_capacity(max_bytes.min(end as usize));
    if file.take(max_bytes as u64).read_to_end(&mut data).is_err() {
        return Buffer::empty();
    }
    if std::str::from_utf8(&data).is_err() {
        let Some(newline) = data.iter().position(|b| *b == b'\n') else {
            return Buffer::empty();
        };
        data.drain(..=newline);
        if std::str::from_utf8(&data).is_err() {
            return Buffer::empty();
        }
    }
    Buffer::from_bytes(data)
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_effective_used(used: f64, resets: f64, now: f64) -> f64 {
    if !used.is_finite() || (resets.is_finite() && resets <= now) {
        0.0
    } else {
        used.clamp(0.0, 100.0)
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn mbp_limit_is_fresh(observed: f64, now: f64) -> u32 {
    u32::from((0.0..=18000.0).contains(&(now - observed)))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_usage_fields_escape_parser() {
        let v=claude(br#"{"secret":"CANARY","rate_limits":{"five_hour":{"used_percentage":42,"resets_at":2000000000000}}}"#).unwrap();
        assert!(!v.to_string().contains("CANARY"));
        assert_eq!(v["windows"][0]["resets"], 2000000000.0);
    }
    #[test]
    fn codex_keeps_old_windows_and_new_limit_note() {
        let v=codex(b"{\"type\":\"event_msg\",\"timestamp\":\"2026-01-01T00:00:00Z\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"primary\":{\"used_percent\":20,\"window_minutes\":300}},\"info\":{\"total_token_usage\":{\"total_tokens\":40}}}}\n{\"type\":\"event_msg\",\"timestamp\":\"2026-01-01T01:00:00Z\",\"payload\":{\"type\":\"token_count\",\"rate_limits\":{\"rate_limit_reached_type\":\"usage_limit_reached\"}}}").unwrap();
        assert_eq!(v["windows"][0]["used"], 20.0);
        assert_eq!(
            v["extras"]["rate_limit_reached_type"],
            "usage_limit_reached"
        );
        assert_eq!(v["observedText"], "2026-01-01T00:00:00Z");
    }
    #[test]
    fn invalid_input_and_reset_edges() {
        assert!(claude(b"{").is_none());
        assert!(codex(b"truncated line").is_none());
        assert_eq!(mbp_effective_used(90.0, 100.0, 100.0), 0.0);
        assert_eq!(mbp_limit_is_fresh(101.0, 100.0), 0);
        assert_eq!(window_label(1439.0), "24時間");
    }
}
