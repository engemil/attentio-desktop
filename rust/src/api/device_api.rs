use anyhow::Result;
use attentio::device::discovery::{find_devices, DeviceMode};
use attentio::protocol::open_client;
use std::time::Duration;

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
        })
        .collect())
}

/// Queries the current status of an AL-1 device. If `serial` is `None`, the
/// first available device is used.
pub async fn api_get_status(serial: Option<String>) -> Result<DeviceStatus> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    let status = client
        .get_status()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    Ok(status.into())
}

/// Transition the device from STANDALONE to REMOTE mode. Returns session id.
pub async fn api_claim(serial: Option<String>) -> Result<u16> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client.claim().await.map_err(|e| anyhow::anyhow!(e))
}

/// Release REMOTE control, returning the device to STANDALONE.
pub async fn api_release(serial: Option<String>) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client.release().await.map_err(|e| anyhow::anyhow!(e))
}

/// Round-trip ping in milliseconds.
pub async fn api_ping(serial: Option<String>) -> Result<u64> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    let start = std::time::Instant::now();
    client.ping().await.map_err(|e| anyhow::anyhow!(e))?;
    Ok(start.elapsed().as_millis() as u64)
}

/// Set LED colour by RGB. Auto-claims the device.
pub async fn api_set_rgb(serial: Option<String>, r: u8, g: u8, b: u8) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .ensure_claimed()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .set_rgb(r, g, b)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}

/// Set LED colour by HSV. H is 0-359, S and V are 0-100.
pub async fn api_set_hsv(serial: Option<String>, h: u16, s: u8, v: u8) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .ensure_claimed()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .set_hsv(h, s, v)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}

/// Set brightness 0-100%.
pub async fn api_set_brightness(serial: Option<String>, brightness: u8) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .ensure_claimed()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .set_brightness(brightness)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}

/// Turn LEDs off.
pub async fn api_led_off(serial: Option<String>) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .ensure_claimed()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client.led_off().await.map_err(|e| anyhow::anyhow!(e))
}

/// Wake from low-power mode.
pub async fn api_power_on(serial: Option<String>) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .ensure_claimed()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client.power_on().await.map_err(|e| anyhow::anyhow!(e))
}

/// Enter low-power mode.
pub async fn api_power_off(serial: Option<String>) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .ensure_claimed()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client.power_off().await.map_err(|e| anyhow::anyhow!(e))
}

/// Fetch all device metadata (read-only key-value pairs).
pub async fn api_get_metadata(serial: Option<String>) -> Result<Vec<KvEntry>> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    let entries = client
        .get_metadata()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    Ok(entries
        .into_iter()
        .map(|(key, value)| KvEntry { key, value })
        .collect())
}

/// List all persistent device settings (key-value pairs).
pub async fn api_settings_list(serial: Option<String>) -> Result<Vec<KvEntry>> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    let entries = client
        .settings_list()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    Ok(entries
        .into_iter()
        .map(|(key, value)| KvEntry { key, value })
        .collect())
}

/// Get the value of a single setting.
pub async fn api_settings_get(serial: Option<String>, key: String) -> Result<String> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    let (_k, value) = client
        .settings_get(&key)
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    Ok(value)
}

/// Set a persistent setting (auto-claims the device).
pub async fn api_settings_set(
    serial: Option<String>,
    key: String,
    value: String,
) -> Result<()> {
    let mut client = open_client(serial.as_deref())
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .ensure_claimed()
        .await
        .map_err(|e| anyhow::anyhow!(e))?;
    client
        .settings_set(&key, &value)
        .await
        .map_err(|e| anyhow::anyhow!(e))
}
