//! Streaming monitor API for the desktop app.
//!
//! Provides real-time streams of:
//! - Serial debug output (CDC0) — line-oriented text
//! - AP protocol traffic (CDC1) — formatted command/response strings via
//!   the broadcast channel tapped into the shared `ApClient`

use anyhow::Result;
use attentio::device::connection::DeviceConnection;
use attentio::device::discovery::find_devices;
use attentio::monitor::format::{format_incoming, format_outgoing, log_level_name};
use attentio::protocol::MonitorEvent;

use std::time::Duration;

use crate::frb_generated::StreamSink;

// Re-use the slot_for helper from device_api to tap into the same ApClient.
use super::device_api::{slot_for, resolve_serial};

/// Start streaming serial debug output (CDC0) for a device.
///
/// Opens the serial/debug port independently of the protocol client and
/// streams each line to the Dart side. Automatically reconnects on
/// transient errors. The stream runs until the sink is closed (Dart
/// disposes the stream subscription).
pub async fn api_monitor_serial_start(
    serial: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let resolved = resolve_serial(Some(serial)).await?;

    // Find the CDC0 port path.
    let devices = tokio::time::timeout(Duration::from_secs(5), find_devices())
        .await
        .map_err(|_| anyhow::anyhow!("Timeout"))??;
    let dev = devices
        .iter()
        .find(|d| d.serial == resolved)
        .ok_or_else(|| anyhow::anyhow!("device not found: {}", resolved))?;
    let port_path = dev
        .cdc0
        .as_ref()
        .map(|p| p.path.clone())
        .ok_or_else(|| anyhow::anyhow!("device '{}' has no serial port (CDC0)", resolved))?;

    // Spawn the reader task.
    let serial_for_log = resolved.clone();
    tokio::spawn(async move {
        log::trace!(
            "frb_diag: monitor_serial task started serial={} port={}",
            serial_for_log,
            port_path
        );
        serial_reader_loop(&port_path, &sink, &serial_for_log).await;
    });

    Ok(())
}

/// Internal loop: open CDC0, read lines, push to sink. Reconnects on error.
///
/// Uses a short read timeout (1s) so the loop cycles frequently and detects
/// when the Dart-side stream subscription has been cancelled (sink closed).
/// When `sink.add()` returns `Err`, the `DeviceConnection` is dropped,
/// immediately releasing the exclusive port lock.
async fn serial_reader_loop(port_path: &str, sink: &StreamSink<String>, serial: &str) {
    loop {
        match DeviceConnection::open(port_path) {
            Ok(conn) => {
                // Use a short timeout so we cycle quickly and detect sink closure.
                let mut conn = conn.with_timeout(Duration::from_secs(1));
                let _ = sink.add("[connected]".to_string());
                loop {
                    match conn.read_line().await {
                        Ok(line) => {
                            if sink.add(line).is_err() {
                                log::trace!(
                                    "frb_diag: monitor_serial task exiting serial={} reason=sink_closed_on_line",
                                    serial
                                );
                                return; // Sink closed — drop conn, exit.
                            }
                        }
                        Err(attentio::error::AttentioError::Timeout { .. }) => {
                            // No data — check if sink is still alive.
                            if sink.add(String::new()).is_err() {
                                log::trace!(
                                    "frb_diag: monitor_serial task exiting serial={} reason=sink_closed_on_timeout_probe",
                                    serial
                                );
                                return; // Sink closed — drop conn, exit.
                            }
                            continue;
                        }
                        Err(_e) => {
                            let _ = sink.add("[disconnected]".to_string());
                            break; // Reconnect.
                        }
                    }
                }
                // conn is dropped here, releasing the port immediately.
            }
            Err(attentio::error::AttentioError::PortBusy { .. }) => {
                if sink.add("[port busy — retrying]".to_string()).is_err() {
                    log::trace!(
                        "frb_diag: monitor_serial task exiting serial={} reason=sink_closed_on_port_busy",
                        serial
                    );
                    return;
                }
            }
            Err(_e) => {
                if sink.add("[connection failed — retrying]".to_string()).is_err() {
                    log::trace!(
                        "frb_diag: monitor_serial task exiting serial={} reason=sink_closed_on_open_failure",
                        serial
                    );
                    return;
                }
            }
        }

        // Wait before reconnecting, checking sink liveness.
        tokio::time::sleep(Duration::from_secs(3)).await;
        if sink.add(String::new()).is_err() {
            log::trace!(
                "frb_diag: monitor_serial task exiting serial={} reason=sink_closed_on_reconnect_probe",
                serial
            );
            return;
        }
    }
}

/// Start streaming AP protocol traffic (CDC1) for a device.
///
/// Subscribes to the broadcast channel on the shared `ApClient` (the same
/// client used by all device commands). Each outgoing command and incoming
/// response is formatted as a human-readable string and pushed to the Dart
/// side.
///
/// If no `ApClient` exists yet for this device, one will be created (and
/// cached) so that the monitor can start receiving events immediately once
/// commands are issued through the app.
pub async fn api_monitor_protocol_start(
    serial: String,
    sink: StreamSink<String>,
) -> Result<()> {
    let resolved = resolve_serial(Some(serial)).await?;
    let slot = slot_for(&resolved);

    // Ensure a client exists so we can subscribe.
    {
        let mut guard = slot.lock().await;
        if guard.is_none() {
            let client = attentio::protocol::open_client(Some(resolved.as_str()))
                .await
                .map_err(|e| anyhow::anyhow!(e))?;
            *guard = Some(client);
        }
    }

    // Subscribe to the monitor broadcast.
    let rx = {
        let guard = slot.lock().await;
        guard
            .as_ref()
            .expect("client just initialised")
            .subscribe_monitor()
    };

    let _ = sink.add("[listening for protocol traffic]".to_string());

    // Spawn the reader task.
    let serial_for_log = resolved.clone();
    tokio::spawn(async move {
        log::trace!(
            "frb_diag: monitor_protocol task started serial={}",
            serial_for_log
        );
        protocol_reader_loop(rx, &sink, &serial_for_log).await;
    });

    Ok(())
}

/// Internal loop: receive monitor events and format them for display.
async fn protocol_reader_loop(
    mut rx: tokio::sync::broadcast::Receiver<MonitorEvent>,
    sink: &StreamSink<String>,
    serial: &str,
) {
    loop {
        match rx.recv().await {
            Ok(event) => {
                let line = match &event {
                    MonitorEvent::Outgoing { cmd, payload } => format_outgoing(*cmd, payload),
                    MonitorEvent::Incoming(resp) => format_incoming(resp),
                };
                if sink.add(line).is_err() {
                    log::trace!(
                        "frb_diag: monitor_protocol task exiting serial={} reason=sink_closed_on_event",
                        serial
                    );
                    return; // Sink closed.
                }
            }
            Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                let _ = sink.add(format!("[dropped {} event(s)]", n));
            }
            Err(tokio::sync::broadcast::error::RecvError::Closed) => {
                let _ = sink.add("[protocol monitor channel closed]".to_string());
                log::trace!(
                    "frb_diag: monitor_protocol task exiting serial={} reason=broadcast_closed",
                    serial
                );
                return;
            }
        }
    }
}

/// Set the runtime firmware log level for a device.
///
/// Level: 0=NONE, 1=ERROR, 2=WARN, 3=INFO, 4=DEBUG.
pub async fn api_monitor_set_log_level(serial: String, level: u8) -> Result<()> {
    if level > 4 {
        anyhow::bail!("log level must be 0-4");
    }
    super::device_api::with_client_pub(Some(serial), async move |c| {
        c.log_set_level(level).await
    })
    .await
}

/// Get the current runtime firmware log level for a device.
///
/// Returns the level and its human-readable name as a tuple string
/// e.g. "3" for INFO.
pub async fn api_monitor_get_log_level(serial: String) -> Result<MonitorLogLevel> {
    let level = super::device_api::with_client_pub(Some(serial), async move |c| {
        c.log_get_level().await
    })
    .await?;
    Ok(MonitorLogLevel {
        level,
        name: log_level_name(level).to_string(),
    })
}

/// Log level info returned to Dart.
pub struct MonitorLogLevel {
    pub level: u8,
    pub name: String,
}
