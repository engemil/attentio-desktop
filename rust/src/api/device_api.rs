use anyhow::Result;
use attentio::device::discovery::{find_devices, cache_remember, DeviceMode};
use attentio::error::AttentioError;
use attentio::protocol::{open_client, ApClient};
use std::collections::HashMap;
use std::sync::{Mutex as StdMutex, OnceLock};
use std::time::Duration;
use tokio::sync::Mutex as AsyncMutex;
use std::sync::Arc;

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

fn slot_for(serial: &str) -> SharedSlot {
    static MAP: OnceLock<StdMutex<HashMap<String, SharedSlot>>> = OnceLock::new();
    let map = MAP.get_or_init(|| StdMutex::new(HashMap::new()));
    let mut guard = map.lock().expect("device-cache map poisoned");
    guard
        .entry(serial.to_string())
        .or_insert_with(|| Arc::new(AsyncMutex::new(None)))
        .clone()
}

/// Resolve `serial = None` to the serial of the first available device.
async fn resolve_serial(serial: Option<String>) -> Result<String> {
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
        .map(|d| DeviceInfo {
            serial: d.serial,
            name: d.product,
            device_type: d.device_type,
            mode: mode_string(d.mode),
            usb_location: d.usb_location,
            serial_port: d.cdc0.as_ref().map(|p| p.path.clone()),
            protocol_port: d.cdc1.as_ref().or(d.single_cdc.as_ref()).map(|p| p.path.clone()),
        })
        .collect())
}

/// Queries the current status of an AL-1 device. If `serial` is `None`, the
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
