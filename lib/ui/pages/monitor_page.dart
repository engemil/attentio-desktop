import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:attentio_desktop/src/rust/api/monitor_api.dart';

/// Maximum number of lines retained per pane (matches CLI's MAX_LINES).
const _kMaxLines = 1000;

/// Log level constants matching firmware values.
const _logLevels = [
  (level: 0, name: 'NONE'),
  (level: 1, name: 'ERROR'),
  (level: 2, name: 'WARN'),
  (level: 3, name: 'INFO'),
  (level: 4, name: 'DEBUG'),
];

/// Full-screen two-pane monitor page showing real-time serial debug output
/// (CDC0, bottom) and AP protocol traffic (CDC1, top) for a single device.
class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key, required this.serial, required this.deviceName});

  final String serial;
  final String deviceName;

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  // ── Pane state ──────────────────────────────────────────────────────────
  final List<String> _serialLines = [];
  final List<String> _protocolLines = [];

  bool _serialConnected = false;
  bool _protocolConnected = false;

  final ScrollController _serialScrollCtrl = ScrollController();
  final ScrollController _protocolScrollCtrl = ScrollController();

  bool _serialAutoScroll = true;
  bool _protocolAutoScroll = true;

  // ── Filter ──────────────────────────────────────────────────────────────
  // Hide background `→ GET_STATUS` / matching `← OK` reply from the protocol
  // pane. The parent Device Detail page keeps polling `get_status` every 2 s
  // to feed its live status header; on the Monitor page that traffic drowns
  // out anything else of interest. Default off — user opts in.
  bool _filterGetStatus = false;
  // Pair-state: we've just suppressed a `→ GET_STATUS` and are waiting to
  // suppress its matching `← OK` / `← ERROR` reply. CDC1 is strictly
  // request/response so a single bool is enough.
  bool _suppressNextOkReply = false;

  // ── Streams ─────────────────────────────────────────────────────────────
  StreamSubscription<String>? _serialSub;
  StreamSubscription<String>? _protocolSub;

  // ── Log level ───────────────────────────────────────────────────────────
  int _logLevel = -1; // -1 = unknown / loading
  bool _logLevelBusy = false;

  // ── Focus ───────────────────────────────────────────────────────────────
  /// Which pane is focused (for keyboard scroll). 0 = protocol, 1 = serial.
  int _focusedPane = 0;
  final FocusNode _keyboardFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _startStreams();
    _fetchLogLevel();

    // Listen for scroll position changes to detect manual scroll-up.
    _serialScrollCtrl.addListener(() {
      if (!_serialScrollCtrl.hasClients) return;
      final atBottom = _serialScrollCtrl.position.pixels >=
          _serialScrollCtrl.position.maxScrollExtent - 20;
      if (_serialAutoScroll != atBottom) {
        setState(() => _serialAutoScroll = atBottom);
      }
    });
    _protocolScrollCtrl.addListener(() {
      if (!_protocolScrollCtrl.hasClients) return;
      final atBottom = _protocolScrollCtrl.position.pixels >=
          _protocolScrollCtrl.position.maxScrollExtent - 20;
      if (_protocolAutoScroll != atBottom) {
        setState(() => _protocolAutoScroll = atBottom);
      }
    });
  }

  void _startStreams() {
    _serialSub = apiMonitorSerialStart(serial: widget.serial).listen(
      (line) {
        // Empty strings are heartbeat probes from Rust — ignore them.
        if (line.isEmpty) return;
        setState(() {
          if (line == '[connected]') {
            _serialConnected = true;
          } else if (line == '[disconnected]' ||
              line.startsWith('[port busy') ||
              line.startsWith('[connection failed')) {
            _serialConnected = false;
          }
          _serialLines.add(line);
          if (_serialLines.length > _kMaxLines) {
            _serialLines.removeRange(0, _serialLines.length - _kMaxLines);
          }
        });
        _maybeAutoScroll(_serialScrollCtrl, _serialAutoScroll);
      },
      onError: (e) {
        setState(() {
          _serialConnected = false;
          _serialLines.add('[error: $e]');
        });
      },
    );

    _protocolSub = apiMonitorProtocolStart(serial: widget.serial).listen(
      (line) {
        if (_filterGetStatus) {
          if (line.startsWith('→ GET_STATUS')) {
            _suppressNextOkReply = true;
            return;
          }
          if (_suppressNextOkReply &&
              (line.startsWith('← OK') || line.startsWith('← ERROR'))) {
            _suppressNextOkReply = false;
            return;
          }
          // Any other outgoing command means our pairing got lost
          // (e.g. a disconnect ate the OK). Clear so we don't eat
          // someone else's reply.
          if (line.startsWith('→')) {
            _suppressNextOkReply = false;
          }
        }
        setState(() {
          if (line == '[listening for protocol traffic]') {
            _protocolConnected = true;
          } else if (line == '[protocol monitor channel closed]') {
            _protocolConnected = false;
          }
          _protocolLines.add(line);
          if (_protocolLines.length > _kMaxLines) {
            _protocolLines.removeRange(0, _protocolLines.length - _kMaxLines);
          }
        });
        _maybeAutoScroll(_protocolScrollCtrl, _protocolAutoScroll);
      },
      onError: (e) {
        setState(() {
          _protocolConnected = false;
          _protocolLines.add('[error: $e]');
        });
      },
    );
  }

  void _maybeAutoScroll(ScrollController ctrl, bool autoScroll) {
    if (!autoScroll || !ctrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctrl.hasClients) {
        ctrl.jumpTo(ctrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _fetchLogLevel() async {
    try {
      final result = await apiMonitorGetLogLevel(serial: widget.serial);
      if (mounted) setState(() => _logLevel = result.level);
    } catch (_) {
      // Leave as unknown.
    }
  }

  Future<void> _setLogLevel(int level) async {
    if (_logLevelBusy) return;
    setState(() => _logLevelBusy = true);
    try {
      await apiMonitorSetLogLevel(serial: widget.serial, level: level);
      if (mounted) setState(() => _logLevel = level);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set log level: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _logLevelBusy = false);
    }
  }

  @override
  void dispose() {
    _serialSub?.cancel();
    _protocolSub?.cancel();
    _serialScrollCtrl.dispose();
    _protocolScrollCtrl.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    // Tab toggles pane focus.
    if (key == LogicalKeyboardKey.tab) {
      setState(() => _focusedPane = (_focusedPane + 1) % 2);
      return KeyEventResult.handled;
    }

    // Arrow keys scroll the focused pane.
    final ctrl =
        _focusedPane == 0 ? _protocolScrollCtrl : _serialScrollCtrl;
    if (!ctrl.hasClients) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowUp) {
      ctrl.jumpTo((ctrl.offset - 16).clamp(0, ctrl.position.maxScrollExtent));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      ctrl.jumpTo((ctrl.offset + 16).clamp(0, ctrl.position.maxScrollExtent));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      ctrl.jumpTo(
          (ctrl.offset - 160).clamp(0, ctrl.position.maxScrollExtent));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      ctrl.jumpTo(
          (ctrl.offset + 160).clamp(0, ctrl.position.maxScrollExtent));
      return KeyEventResult.handled;
    }

    // Number keys 1-4 set log level.
    if (key == LogicalKeyboardKey.digit1) {
      _setLogLevel(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2) {
      _setLogLevel(2);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit3) {
      _setLogLevel(3);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit4) {
      _setLogLevel(4);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Monitor — ${widget.deviceName}'),
          actions: [
            // Log level controls in the app bar.
            _LogLevelControls(
              currentLevel: _logLevel,
              busy: _logLevelBusy,
              onChanged: _setLogLevel,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // Protocol pane (top, ~40%)
            Expanded(
              flex: 4,
              child: _MonitorPane(
                title: 'Protocol (CDC1)',
                lines: _protocolLines,
                connected: _protocolConnected,
                scrollController: _protocolScrollCtrl,
                autoScroll: _protocolAutoScroll,
                focused: _focusedPane == 0,
                onTap: () => setState(() => _focusedPane = 0),
                onClear: () => setState(() => _protocolLines.clear()),
                onScrollToBottom: () {
                  setState(() => _protocolAutoScroll = true);
                  _maybeAutoScroll(_protocolScrollCtrl, true);
                },
                filterActive: _filterGetStatus,
                onToggleFilter: () => setState(() {
                  _filterGetStatus = !_filterGetStatus;
                  _suppressNextOkReply = false;
                }),
              ),
            ),
            const Divider(height: 1),
            // Serial pane (bottom, ~60%)
            Expanded(
              flex: 6,
              child: _MonitorPane(
                title: 'Serial (CDC0)',
                lines: _serialLines,
                connected: _serialConnected,
                scrollController: _serialScrollCtrl,
                autoScroll: _serialAutoScroll,
                focused: _focusedPane == 1,
                onTap: () => setState(() => _focusedPane = 1),
                onClear: () => setState(() => _serialLines.clear()),
                onScrollToBottom: () {
                  setState(() => _serialAutoScroll = true);
                  _maybeAutoScroll(_serialScrollCtrl, true);
                },
              ),
            ),
            // Status bar
            _StatusBar(
              serial: widget.serial,
              logLevel: _logLevel,
              serialLineCount: _serialLines.length,
              protocolLineCount: _protocolLines.length,
              focusedPane: _focusedPane,
              protocolFilterActive: _filterGetStatus,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log level controls (app bar)
// ─────────────────────────────────────────────────────────────────────────────

class _LogLevelControls extends StatelessWidget {
  const _LogLevelControls({
    required this.currentLevel,
    required this.busy,
    required this.onChanged,
  });

  final int currentLevel;
  final bool busy;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return SegmentedButton<int>(
      segments: [
        for (final l in _logLevels.skip(1)) // Skip NONE
          ButtonSegment(
            value: l.level,
            label: Text(
              l.name,
              style: const TextStyle(fontSize: 11),
            ),
            tooltip: '${l.name} (key ${l.level})',
          ),
      ],
      selected: currentLevel >= 1 && currentLevel <= 4
          ? {currentLevel}
          : const {},
      onSelectionChanged: (s) {
        if (s.isNotEmpty) onChanged(s.first);
      },
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single monitor pane
// ─────────────────────────────────────────────────────────────────────────────

class _MonitorPane extends StatelessWidget {
  const _MonitorPane({
    required this.title,
    required this.lines,
    required this.connected,
    required this.scrollController,
    required this.autoScroll,
    required this.focused,
    required this.onTap,
    required this.onClear,
    required this.onScrollToBottom,
    this.filterActive,
    this.onToggleFilter,
  });

  final String title;
  final List<String> lines;
  final bool connected;
  final ScrollController scrollController;
  final bool autoScroll;
  final bool focused;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final VoidCallback onScrollToBottom;
  // Optional GET_STATUS filter toggle. When `onToggleFilter` is null, the
  // filter button is not rendered (used by the Serial pane).
  final bool? filterActive;
  final VoidCallback? onToggleFilter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor =
        focused ? scheme.primary : scheme.outlineVariant.withAlpha(80);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: focused ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pane header
            Container(
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // Connection indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected ? Colors.green : Colors.red.shade400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: focused ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  if (onToggleFilter != null)
                    IconButton(
                      icon: Icon(
                        filterActive == true
                            ? Icons.filter_alt
                            : Icons.filter_alt_off,
                        size: 18,
                      ),
                      tooltip: filterActive == true
                          ? 'Hiding background GET_STATUS polling — click to show all traffic'
                          : 'Showing all traffic — click to hide background GET_STATUS polling',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: onToggleFilter,
                    ),
                  if (!autoScroll)
                    IconButton(
                      icon: const Icon(Icons.vertical_align_bottom, size: 18),
                      tooltip: 'Scroll to bottom',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: onScrollToBottom,
                    ),
                  IconButton(
                    icon: const Icon(Icons.clear_all, size: 18),
                    tooltip: 'Clear',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: onClear,
                  ),
                ],
              ),
            ),
            // Lines
            Expanded(
              child: lines.isEmpty
                  ? Center(
                      child: Text(
                        'Waiting for data...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        return _MonitorLine(line: lines[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single line with syntax colouring
// ─────────────────────────────────────────────────────────────────────────────

class _MonitorLine extends StatelessWidget {
  const _MonitorLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: SelectableText(
        line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: _lineColor(context, line),
        ),
      ),
    );
  }

  Color _lineColor(BuildContext context, String line) {
    final scheme = Theme.of(context).colorScheme;
    // Status messages
    if (line.startsWith('[')) return scheme.onSurfaceVariant;
    // Outgoing commands
    if (line.startsWith('→')) return Colors.blue.shade300;
    // Errors
    if (line.contains('ERROR') || line.contains('← ERROR')) {
      return Colors.red.shade300;
    }
    // Events
    if (line.startsWith('← EVT_')) return Colors.amber.shade300;
    // OK responses
    if (line.startsWith('← OK')) return Colors.green.shade300;
    // Incoming (other)
    if (line.startsWith('←')) return Colors.teal.shade300;
    // Default (serial output)
    return scheme.onSurface;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status bar
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.serial,
    required this.logLevel,
    required this.serialLineCount,
    required this.protocolLineCount,
    required this.focusedPane,
    required this.protocolFilterActive,
  });

  final String serial;
  final int logLevel;
  final int serialLineCount;
  final int protocolLineCount;
  final int focusedPane;
  final bool protocolFilterActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final levelName = logLevel >= 0 && logLevel <= 4
        ? _logLevels[logLevel].name
        : '?';
    final levelColor = switch (logLevel) {
      1 => Colors.red.shade300,
      2 => Colors.orange.shade300,
      3 => Colors.blue.shade300,
      4 => Colors.green.shade300,
      _ => scheme.onSurfaceVariant,
    };

    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          fontFamily: 'monospace',
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        ),
        child: Row(
          children: [
            Text(serial, overflow: TextOverflow.ellipsis),
            const SizedBox(width: 16),
            Text('Log: ', style: TextStyle(color: scheme.onSurfaceVariant)),
            Text(levelName, style: TextStyle(color: levelColor)),
            const SizedBox(width: 16),
            Text(focusedPane == 0 ? 'Focus: Protocol' : 'Focus: Serial'),
            const SizedBox(width: 16),
            Text(
              'P:$protocolLineCount${protocolFilterActive ? ' (filtered)' : ''}  S:$serialLineCount',
            ),
            const Spacer(),
            Flexible(
              child: Text(
                'Tab:switch  ↑↓:scroll  PgUp/PgDn  1-4:log level',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withAlpha(150),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
