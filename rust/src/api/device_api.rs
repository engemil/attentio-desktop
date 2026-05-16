use anyhow::Result;
use attentio::device::discovery::{find_devices, cache_remember, DeviceMode};
use attentio::error::AttentioError;
use attentio::protocol::{open_client, ApClient};
use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Mutex as StdMutex, OnceLock};
use std::time::Duration;
use tokio::sync::Mutex as AsyncMutex;
use std::sync::Arc;

use crate::frb_generated::StreamSink;

/// FRB-exposed mirror of `attentio::protocol::client::DeviceStatus`.
///
/// We define our own struct instead of re-exporting the one from `attentio-cli`
/// so that flutter_rust_bridge can generate Dart bindings for it (it cannot
/// see into transitive crates).
pub struct DeviceStatus {
    pub system_state: u8,
    pub current_r: u8,
    pub current_g: u8,
    pub current_b: u8,
    pub brightness: u8,
    pub control_mode: u8,
    pub active_controller: u8,
    pub standalone_mode: u8,
    pub effects_submode: u8,
    pub standalone_color_index: u8,
    pub standalone_brightness_raw: u8,
    pub anim_type: u8,
    pub session_id: u16,
}

impl From<attentio::protocol::client::DeviceStatus> for DeviceStatus {
    fn from(s: attentio::protocol::client::DeviceStatus) -> Self {
        Self {
            system_state: s.system_state,
            current_r: s.current_r,
            current_g: s.current_g,
            current_b: s.current_b,
            brightness: s.brightness,
            control_mode: s.control_mode,
            active_controller: s.active_controller,
            standalone_mode: s.standalone_mode,
            effects_submode: s.effects_submode,
            standalone_color_index: s.standalone_color_index,
            standalone_brightness_raw: s.standalone_brightness_raw,
            anim_type: s.anim_type,
            session_id: s.session_id,
        }
    }
}

/// Lightweight summary of a connected device (used by device list views).
pub struct DeviceInfo {
    /// USB chip serial number (stable identifier).
    pub serial: String,
    /// User-assigned name from device settings (`device_name`), if available.
    pub name: Option<String>,
    /// USB product string (e.g. "EngEmil.io AttentioLight-1"), if available.
    pub device_type: Option<String>,
    /// "Normal", "Bootloader", or "Unknown".
    pub mode: String,
    /// USB bus location, e.g. "Bus 001 Device 060".
    pub usb_location: Option<String>,
    /// Serial/debug port path (CDC0), e.g. "/dev/ttyACM0".
    pub serial_port: Option<String>,
    /// Attentio Protocol port path (CDC1), e.g. "/dev/ttyACM1".
    pub protocol_port: Option<String>,
}

/// A single key-value entry from metadata or settings.
pub struct KvEntry {
    pub key: String,
    pub value: String,
}

/// One-time app initialisation hook invoked by flutter_rust_bridge on the Dart
/// side before any other API call.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Install a `log` backend BEFORE FRB's setup so subsequent `log::warn!()`
    // calls (including FRB's own "Fail to post message to Dart" warning at
    // `flutter_rust_bridge::rust2dart::sender`) are routed through `log` and
    // can be filtered via `RUST_LOG`. Without this, FRB falls back to a bare
    // `println!` (see `flutter_rust_bridge/src/misc/logs.rs`).
    //
    // Default filter is `warn` so behaviour is unchanged out of the box; users
    // who want to silence the FRB warning can run with e.g.
    //   RUST_LOG=warn,flutter_rust_bridge::rust2dart=error flutter run -d linux
    // Install a tracing subscriber that reads RUST_LOG and outputs to stderr.
    // Handles tracing events from attentio-cli (tracing::debug! etc.).
    // RUST_LOG=trace shows everything; default is warn.
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("warn"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .init();

    // Bridge log events to tracing so mio_serial, FRB etc. are also visible.
    let _ = tracing_log::LogTracer::init();

    flutter_rust_bridge::setup_default_user_utils();
}

fn mode_string(m: DeviceMode) -> String {
    match m {
        DeviceMode::Normal => "Normal".to_string(),
        DeviceMode::Bootloader => "Bootloader".to_string(),
        DeviceMode::Unknown => "Unknown".to_string(),
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Persistent per-device client cache
// ─────────────────────────────────────────────────────────────────────────────
//
// Each connected device gets one long-lived `ApClient` wrapped in an
// `Arc<AsyncMutex<Option<ApClient>>>`. All FRB calls for that serial acquire
// the same async mutex, run their operation against the cached client, and
// release. The serial port is opened once on first use and held open until
// the device disappears or a transport error forces a reopen.
//
// This eliminates the self-race that produced `PortBusy` when the GUI's
// 2 s status poll and a user-triggered write happened to overlap.
//
// Key design points:
//   • The outer map uses a `std::sync::Mutex` because lookups are nearly
//     instantaneous (HashMap insert/get) — no need for an async lock there.
//   • The inner client uses `tokio::sync::Mutex` because operations are
//     awaited (USB round-trips, ~ms-level).
//   • `Option<ApClient>` lets us evict-in-place: if a transport error fires,
//     we drop the bad client (returning the port to the OS) and the next
//     call will reopen.
//   • `serial = None` resolves to the first available device's serial up-
//     front, then the rest of the call shares that key. The GUI always
//     passes `Some(serial)` today, but this keeps the CLI-style single-
//     device flow working too.

type SharedSlot = Arc<AsyncMutex<Option<ApClient>>>;

pub(crate) fn slot_for(serial: &str) -> SharedSlot {
    static MAP: OnceLock<StdMutex<HashMap<String, SharedSlot>>> = OnceLock::new();
    let map = MAP.get_or_init(|| StdMutex::new(HashMap::new()));
    let mut guard = map.lock().expect("device-cache map poisoned");
    guard
        .entry(serial.to_string())
        .or_insert_with(|| Arc::new(AsyncMutex::new(None)))
        .clone()
}

/// Resolve `serial = None` to the serial of the first available device.
pub(crate) async fn resolve_serial(serial: Option<String>) -> Result<String> {
    if let Some(s) = serial {
        return Ok(s);
    }
    let devices = tokio::time::timeout(Duration::from_secs(5), find_devices())
        .await
        .map_err(|_| anyhow::anyhow!("Timeout"))??;
    let first = devices
        .into_iter()
        .next()
        .ok_or_else(|| anyhow::anyhow!("no device(s) found"))?;
    Ok(first.serial)
}

/// Should we evict the cached client and reopen on the next call? Returns
/// true for transport-level failures where the in-memory `ApClient` is
/// likely no longer usable; returns false for protocol-level errors (the
/// device is fine, the request just failed).
fn is_transport_error(err: &AttentioError) -> bool {
    matches!(
        err,
        AttentioError::PortBusy { .. }
            | AttentioError::Serial(_)
            | AttentioError::Io(_)
            | AttentioError::Timeout { .. }
            | AttentioError::DeviceNotFound
            | AttentioError::DeviceSerialNotFound { .. }
    )
}

/// Run `op` against the persistent `ApClient` for `serial`.
///
/// On a transport error the client is dropped and a single retry is made
/// with a freshly opened client; on protocol errors the client is kept and
/// the error is returned immediately.
async fn with_client<F, T>(serial: Option<String>, op: F) -> Result<T>
where
    F: for<'a> AsyncFn(&'a mut ApClient) -> Result<T, AttentioError>,
{
    let resolved = resolve_serial(serial).await?;
    let slot = slot_for(&resolved);
    let mut guard = slot.lock().await;

    // Ensure we have an open client.
    if guard.is_none() {
        let client = open_client(Some(resolved.as_str()))
            .await
            .map_err(|e| anyhow::anyhow!(e))?;
        *guard = Some(client);
    }

    // First attempt.
    let first_err = {
        let client = guard.as_mut().expect("client just initialised");
        match op(client).await {
            Ok(v) => return Ok(v),
            Err(e) => e,
        }
    };

    // On transport errors: evict, reopen, retry once.
    if is_transport_error(&first_err) {
        *guard = None;
        let mut fresh = open_client(Some(resolved.as_str()))
            .await
            .map_err(|e| anyhow::anyhow!(e))?;
        let result = op(&mut fresh).await;
        match result {
            Ok(v) => {
                *guard = Some(fresh);
                Ok(v)
            }
            Err(e) => Err(anyhow::anyhow!(e)),
        }
    } else {
        Err(anyhow::anyhow!(first_err))
    }
}

/// Crate-visible alias of [`with_client`] for use by other API modules.
pub(crate) async fn with_client_pub<F, T>(serial: Option<String>, op: F) -> Result<T>
where
    F: for<'a> AsyncFn(&'a mut ApClient) -> Result<T, AttentioError>,
{
    with_client(serial, op).await
}

// ─────────────────────────────────────────────────────────────────────────────
// FRB API surface
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the serial numbers of all currently connected AttentioLight-1
/// devices. Times out after 5 seconds.
pub async fn api_list_devices() -> Result<Vec<String>> {
    let devices = tokio::time::timeout(Duration::from_secs(5), find_devices())
        .await
        .map_err(|_| anyhow::anyhow!("Timeout"))??;

    Ok(devices.into_iter().map(|d| d.serial).collect())
}

/// Returns richer information for all connected devices: serial, user name,
/// USB product string, mode, and USB bus location. Times out after 5 seconds.
pub async fn api_list_devices_full() -> Result<Vec<DeviceInfo>> {
    let devices = tokio::time::timeout(Duration::from_secs(5), find_devices())
        .await
        .map_err(|_| anyhow::anyhow!("Timeout"))??;

    Ok(devices
        .into_iter()
        .map(device_to_info)
        .collect())
}

/// Queries the current status of a device. If `serial` is `None`, the
/// first available device is used.
pub async fn api_get_status(serial: Option<String>) -> Result<DeviceStatus> {
    with_client(serial, async |c| c.get_status().await).await.map(Into::into)
}

/// Transition the device from STANDALONE to REMOTE mode. Returns session id.
pub async fn api_claim(serial: Option<String>) -> Result<u16> {
    with_client(serial, async |c| c.claim().await).await
}

/// Release REMOTE control, returning the device to STANDALONE.
pub async fn api_release(serial: Option<String>) -> Result<()> {
    with_client(serial, async |c| c.release().await).await
}

/// Round-trip ping in milliseconds.
pub async fn api_ping(serial: Option<String>) -> Result<u64> {
    with_client(serial, async |c| {
        let start = std::time::Instant::now();
        c.ping().await?;
        Ok(start.elapsed().as_millis() as u64)
    })
    .await
}

/// Set LED colour by RGB. Auto-claims the device.
pub async fn api_set_rgb(serial: Option<String>, r: u8, g: u8, b: u8) -> Result<()> {
    with_client(serial, async move |c| {
        c.ensure_claimed().await?;
        c.set_rgb(r, g, b).await
    })
    .await
}

/// Set LED colour by HSV. H is 0-359, S and V are 0-100.
pub async fn api_set_hsv(serial: Option<String>, h: u16, s: u8, v: u8) -> Result<()> {
    with_client(serial, async move |c| {
        c.ensure_claimed().await?;
        c.set_hsv(h, s, v).await
    })
    .await
}

/// Set brightness 0-100%.
pub async fn api_set_brightness(serial: Option<String>, brightness: u8) -> Result<()> {
    with_client(serial, async move |c| {
        c.ensure_claimed().await?;
        c.set_brightness(brightness).await
    })
    .await
}

/// Turn LEDs off.
pub async fn api_led_off(serial: Option<String>) -> Result<()> {
    with_client(serial, async |c| {
        c.ensure_claimed().await?;
        c.led_off().await
    })
    .await
}

/// Wake from low-power mode.
pub async fn api_power_on(serial: Option<String>) -> Result<()> {
    with_client(serial, async |c| {
        c.ensure_claimed().await?;
        c.power_on().await
    })
    .await
}

/// Enter low-power mode.
pub async fn api_power_off(serial: Option<String>) -> Result<()> {
    with_client(serial, async |c| {
        c.ensure_claimed().await?;
        c.power_off().await
    })
    .await
}

/// Fetch all device metadata (read-only key-value pairs).
pub async fn api_get_metadata(serial: Option<String>) -> Result<Vec<KvEntry>> {
    let entries = with_client(serial, async |c| c.get_metadata().await).await?;
    Ok(entries
        .into_iter()
        .map(|(key, value)| KvEntry { key, value })
        .collect())
}

/// List all persistent device settings (key-value pairs).
pub async fn api_settings_list(serial: Option<String>) -> Result<Vec<KvEntry>> {
    let entries = with_client(serial, async |c| c.settings_list().await).await?;
    Ok(entries
        .into_iter()
        .map(|(key, value)| KvEntry { key, value })
        .collect())
}

/// Get the value of a single setting.
pub async fn api_settings_get(serial: Option<String>, key: String) -> Result<String> {
    let (_k, value) =
        with_client(serial, async move |c| c.settings_get(&key).await).await?;
    Ok(value)
}

/// Set a persistent setting (auto-claims the device).
pub async fn api_settings_set(
    serial: Option<String>,
    key: String,
    value: String,
) -> Result<()> {
    with_client(serial, async move |c| {
        c.ensure_claimed().await?;
        c.settings_set(&key, &value).await
    })
    .await
}

/// Rename a device by setting `device_name` via the cached client, then
/// update the discovery name cache so subsequent `find_devices()` calls
/// return the new name immediately (even if the port is busy).
pub async fn api_rename_device(serial: Option<String>, name: String) -> Result<()> {
    let resolved = resolve_serial(serial).await?;
    let name_clone = name.clone();
    with_client(Some(resolved.clone()), async move |c| {
        c.ensure_claimed().await?;
        c.settings_set("device_name", &name_clone).await
    })
    .await?;
    cache_remember(&resolved, &name);
    Ok(())
}

// ─────────────────────────────────────────────────────────────────────────────
// Long-lived polling streams (replaces per-tick one-shot futures)
// ─────────────────────────────────────────────────────────────────────────────
//
// Why: every `async fn` exposed to Dart posts its result back to a one-shot
// Dart receive port via `flutter_rust_bridge::Rust2DartSender::send_or_warn`.
// If the Dart side has cancelled / disposed the listener before the Rust
// future completes (Riverpod family auto-dispose, page navigation, list
// rebuild, etc.), FRB prints "Fail to post message to Dart." once per
// orphaned future. Polling Rust APIs from Dart `Stream.periodic(...)`
// generators made this easy to trigger because each tick spawns a fresh
// future with a fresh receive port.
//
// Fix: keep one long-lived Rust task per stream that owns a `StreamSink`.
// `sink.add(...)` returns `Err` (no warning) when the Dart side closes,
// and the loop exits cleanly. Only when the *last* sink clone is dropped
// does FRB attempt to post a close-stream sentinel — and that is the only
// remaining path through which a warning could surface, ~once per stream
// lifetime. Combined with the env_logger init in `init_app`, residual
// warnings are routable via `RUST_LOG`.

/// Unix-millis deadline until which the device list stream polls fast
/// (2 s instead of 5 s). 0 = no fast-poll requested.
fn fast_refresh_deadline() -> &'static AtomicI64 {
    static DEADLINE: OnceLock<AtomicI64> = OnceLock::new();
    DEADLINE.get_or_init(|| AtomicI64::new(0))
}

fn now_unix_millis() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Request that the device list stream poll at the fast cadence (2 s) for
/// the next 15 seconds. Idempotent / monotonic — repeated calls extend the
/// window. The corresponding Dart-side notifier (`deviceRefreshProvider`)
/// continues to track the deadline for UI badges; this just informs Rust.
pub fn api_devices_request_fast_refresh() {
    fast_refresh_deadline().store(now_unix_millis() + 15_000, Ordering::Relaxed);
}

/// Per-serial wake-ups for the device-status stream poll loop. When fired,
/// the loop skips its current sleep and polls immediately. Used to make
/// post-action UI updates feel instant without tearing down and respawning
/// the stream (which would trigger FRB's "Fail to post message to Dart"
/// close-sentinel warning every time).
fn status_notify_map() -> &'static StdMutex<HashMap<String, Arc<tokio::sync::Notify>>> {
    static MAP: OnceLock<StdMutex<HashMap<String, Arc<tokio::sync::Notify>>>> = OnceLock::new();
    MAP.get_or_init(|| StdMutex::new(HashMap::new()))
}

fn status_notify_for(serial: &str) -> Arc<tokio::sync::Notify> {
    let mut g = status_notify_map().lock().expect("status-notify map poisoned");
    g.entry(serial.to_string())
        .or_insert_with(|| Arc::new(tokio::sync::Notify::new()))
        .clone()
}

/// Wake the per-serial device-status poll loop so it polls *now* rather than
/// waiting for the next 2-second tick. Used by the UI after state-changing
/// commands (claim, release, set RGB, etc.) so the next status update lands
/// promptly without invalidating the stream provider — the latter triggers
/// FRB's stream-close-sentinel warning ("Fail to post message to Dart").
///
/// No-op if no stream is currently subscribed for `serial`; the notify is
/// edge-triggered (not a flag) so a kick before the loop starts is dropped.
/// Acceptable: the first stream tick is immediate anyway.
pub fn api_device_status_kick(serial: String) {
    status_notify_for(&serial).notify_one();
}

/// Long-lived stream of the current device list. Replaces the previous
/// Dart-side `Stream.periodic` polling around `apiListDevicesFull`.
///
/// Cadence: 2 s while `api_devices_request_fast_refresh` is in effect,
/// otherwise 5 s. The first emit is immediate. Errors from `find_devices`
/// produce an empty list (matches previous Dart-side fallback).
pub async fn api_devices_stream_start(sink: StreamSink<Vec<DeviceInfo>>) -> Result<()> {
    tokio::spawn(async move {
        log::trace!("frb_diag: devices_stream task started");
        // Fast initial emit so the UI populates without waiting a full tick.
        let initial = match tokio::time::timeout(Duration::from_secs(5), find_devices()).await {
            Ok(Ok(devs)) => devs.into_iter().map(device_to_info).collect(),
            _ => Vec::new(),
        };
        if sink.add(initial).is_err() {
            log::trace!("frb_diag: devices_stream task exiting reason=sink_closed_on_initial");
            return;
        }

        loop {
            let fast = fast_refresh_deadline().load(Ordering::Relaxed) > now_unix_millis();
            let interval = if fast {
                Duration::from_secs(2)
            } else {
                Duration::from_secs(5)
            };
            tokio::time::sleep(interval).await;

            let next = match tokio::time::timeout(Duration::from_secs(5), find_devices()).await {
                Ok(Ok(devs)) => devs.into_iter().map(device_to_info).collect(),
                _ => Vec::new(),
            };

            if sink.add(next).is_err() {
                log::trace!("frb_diag: devices_stream task exiting reason=sink_closed_on_tick");
                return;
            }
        }
    });

    Ok(())
}

/// Long-lived per-device status stream. Replaces the previous Dart-side
/// `Stream.periodic` loop around `apiGetStatus`.
///
/// Polls every 2 s. Successful results are pushed to Dart; errors are
/// silently skipped (next tick retries). Exits when the Dart subscription
/// is cancelled.
pub async fn api_device_status_stream_start(
    serial: String,
    sink: StreamSink<DeviceStatus>,
) -> Result<()> {
    let notify = status_notify_for(&serial);
    tokio::spawn(async move {
        log::trace!("frb_diag: device_status task started serial={}", serial);
        // Immediate first tick.
        if let Ok(s) = with_client(Some(serial.clone()), async |c| c.get_status().await).await {
            if sink.add(Into::<DeviceStatus>::into(s)).is_err() {
                log::trace!(
                    "frb_diag: device_status task exiting serial={} reason=sink_closed_on_initial",
                    serial
                );
                return;
            }
        }
        loop {
            // Sleep up to 2 s, but wake early if a kick arrived (state-changing
            // command finished — UI wants a fresh status now).
            tokio::select! {
                _ = tokio::time::sleep(Duration::from_secs(2)) => {}
                _ = notify.notified() => {
                    log::trace!(
                        "frb_diag: device_status task kicked serial={}",
                        serial
                    );
                }
            }
            match with_client(Some(serial.clone()), async |c| c.get_status().await).await {
                Ok(status) => {
                    if sink.add(Into::<DeviceStatus>::into(status)).is_err() {
                        log::trace!(
                            "frb_diag: device_status task exiting serial={} reason=sink_closed_on_tick",
                            serial
                        );
                        return;
                    }
                }
                Err(_e) => {
                    // Skip this tick. Note we cannot probe sink liveness here
                    // without sending a message; rely on the next successful
                    // tick (or a long string of failures producing a slow
                    // shutdown — acceptable, no warnings emitted).
                }
            }
        }
    });

    Ok(())
}

// ─────────────────────────────────────────────────────────────────────────────
// Firmware update (DFU)
// ─────────────────────────────────────────────────────────────────────────────

/// Structured progress event for a firmware flash operation.
///
/// `phase` is one of: `"validating"`, `"entering_bootloader"`, `"erasing"`,
/// `"flashing"`, `"rebooting"`, `"done"`, `"error"`.
pub struct DfuProgress {
    pub phase: String,
    pub bytes_written: u64,
    pub bytes_total: u64,
    pub error_message: Option<String>,
}

/// Drop the cached `ApClient` for `serial` so its serial port is released
/// before the DFU process tries to open the device.
async fn evict_client(serial: &str) {
    let slot = slot_for(serial);
    let mut guard = slot.lock().await;
    *guard = None;
}

fn dfu_event_to_progress(event: attentio::cli::commands::dfu::DfuEvent) -> DfuProgress {
    use attentio::cli::commands::dfu::DfuEvent;
    match event {
        DfuEvent::ValidatingFirmware => DfuProgress {
            phase: "validating".to_string(),
            bytes_written: 0,
            bytes_total: 0,
            error_message: None,
        },
        DfuEvent::EnteringBootloader => DfuProgress {
            phase: "entering_bootloader".to_string(),
            bytes_written: 0,
            bytes_total: 0,
            error_message: None,
        },
        DfuEvent::Erasing => DfuProgress {
            phase: "erasing".to_string(),
            bytes_written: 0,
            bytes_total: 0,
            error_message: None,
        },
        DfuEvent::Writing { bytes_written, bytes_total } => DfuProgress {
            phase: "flashing".to_string(),
            bytes_written,
            bytes_total,
            error_message: None,
        },
        DfuEvent::WaitingForReboot => DfuProgress {
            phase: "rebooting".to_string(),
            bytes_written: 0,
            bytes_total: 0,
            error_message: None,
        },
        DfuEvent::Done => DfuProgress {
            phase: "done".to_string(),
            bytes_written: 0,
            bytes_total: 0,
            error_message: None,
        },
    }
}

/// Flash firmware from `firmware_path` to the device identified by `serial`,
/// streaming structured [`DfuProgress`] events to `sink`.
///
/// The device may be in Normal or Bootloader mode; if Normal, the AP
/// `DFU_ENTER` command is sent first. The cached `ApClient` for the device
/// is evicted before the operation so the serial port is free for DFU.
///
/// After a successful flash, the device list stream is nudged to fast-poll so
/// the device re-appears in the UI promptly.
pub async fn api_flash_firmware(
    serial: String,
    firmware_path: String,
    sink: StreamSink<DfuProgress>,
) -> Result<()> {
    // Release any open ApClient so the port is available for DFU.
    evict_client(&serial).await;

    // Read firmware file before spawning so we can surface I/O errors early.
    let firmware_data = tokio::fs::read(&firmware_path)
        .await
        .map_err(|e| anyhow::anyhow!("failed to read firmware file: {}", e))?;

    let (tx, mut rx) =
        tokio::sync::mpsc::unbounded_channel::<attentio::cli::commands::dfu::DfuEvent>();

    let serial_clone = serial.clone();
    let flash_task = tokio::spawn(async move {
        attentio::cli::commands::dfu::flash_firmware_for_serial(&serial_clone, firmware_data, tx)
            .await
    });

    // Forward events from the channel to the Flutter sink.
    while let Some(event) = rx.recv().await {
        if sink.add(dfu_event_to_progress(event)).is_err() {
            flash_task.abort();
            return Ok(());
        }
    }

    // Channel closed — flash task has finished. Surface any error.
    match flash_task.await {
        Ok(Ok(())) => {
            // Nudge device list to fast-poll so the re-appeared device shows up quickly.
            api_devices_request_fast_refresh();
        }
        Ok(Err(e)) => {
            let _ = sink.add(DfuProgress {
                phase: "error".to_string(),
                bytes_written: 0,
                bytes_total: 0,
                error_message: Some(e.to_string()),
            });
        }
        Err(_) => {
            let _ = sink.add(DfuProgress {
                phase: "error".to_string(),
                bytes_written: 0,
                bytes_total: 0,
                error_message: Some("DFU task panicked".to_string()),
            });
        }
    }

    Ok(())
}

/// Internal: convert an `attentio::device::discovery::AttentioDevice` into the
/// FRB-exposed `DeviceInfo`. Centralised here so both `api_list_devices_full`
/// and `api_devices_stream_start` agree on the mapping.
fn device_to_info(d: attentio::device::discovery::AttentioDevice) -> DeviceInfo {
    DeviceInfo {
        serial: d.serial,
        name: d.product,
        device_type: d.device_type,
        mode: mode_string(d.mode),
        usb_location: d.usb_location,
        serial_port: d.cdc0.as_ref().map(|p| p.path.clone()),
        protocol_port: d.cdc1.as_ref().or(d.single_cdc.as_ref()).map(|p| p.path.clone()),
    }
}
