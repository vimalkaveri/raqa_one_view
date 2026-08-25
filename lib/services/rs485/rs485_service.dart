import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';

import 'rs485_register_data.dart';
import 'modbus_rtu.dart';
import '../settings/app_settings.dart';

class Rs485Service {

  UsbPort? port;
  StreamSubscription<Uint8List>? inputSub;
  StreamSubscription<UsbEvent>? usbEventSub;

  final BytesBuilder buffer = BytesBuilder();
  Timer? pollTimer;
  Timer? reconnectTimer;
  Timer? requestTimeoutTimer;

  final VoidCallback onStateChanged;

  ////////////////////////////////////////////////////////////
  /// 31 SLAVE NOTIFIERS
  ////////////////////////////////////////////////////////////

  List<ValueNotifier<List<RegisterData>>> slaveRegistersNotifier =
  List.generate(
    31,
        (_) => ValueNotifier<List<RegisterData>>([]),
  );

  int slavePollingIndex = 0;
  bool isManualScanRunning = false;
  bool _requestRunning = false;

  Completer<List<int>?>? _pendingScanCompleter;
  int? _pendingScanSlaveId;

  String connectionStatus = "Disconnected";
  int reconnectAttempts = 0;

  /// Last time a valid poll response was received from each slave ID
  /// (1..31). Used by the Dashboard to decide whether a placed sensor's
  /// live status is stale/offline, mirroring the old project's
  /// SensorModel.isOffline check.
  final Map<int, DateTime> slaveLastSeen = {};

  static const Duration offlineThreshold = Duration(seconds: 60);

  bool isSlaveOffline(int slaveId) {
    final seen = slaveLastSeen[slaveId];
    return seen == null || DateTime.now().difference(seen) > offlineThreshold;
  }

  Rs485Service({required this.onStateChanged});

  ////////////////////////////////////////////////////////////
  /// INIT
  ////////////////////////////////////////////////////////////

  Future<void> init() async {
    //await WakelockPlus.enable();
    await ModbusRtu.loadSettings();
    await AppSettings.loadSettings();
    await _initUSB();
  }

  ////////////////////////////////////////////////////////////
  /// REFRESH SLAVES
  ////////////////////////////////////////////////////////////

  void refreshSlaves() {
    pollTimer?.cancel();
    slavePollingIndex = 0;
    _requestRunning = false;
    buffer.clear();
    _restartPolling();
    onStateChanged();
  }

  ////////////////////////////////////////////////////////////
  /// APPLY NEW SLAVE CONFIGURATION
  ////////////////////////////////////////////////////////////

  Future<void> applyNewSlaveConfiguration() async {
    pollTimer?.cancel();
    slavePollingIndex = 0;
    _requestRunning = false;
    buffer.clear();
    _restartPolling();
    onStateChanged();
  }

  ////////////////////////////////////////////////////////////
  /// USB INIT
  ////////////////////////////////////////////////////////////

  Future<void> _initUSB() async {
    await _closePort();

    usbEventSub ??= UsbSerial.usbEventStream?.listen((event) async {
      if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        await _handleDisconnect();
      } else if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        await scanAndConnectUSB();
      }
    });

    await scanAndConnectUSB();
  }

  ////////////////////////////////////////////////////////////
  /// CONNECT
  ////////////////////////////////////////////////////////////

  Future<void> scanAndConnectUSB() async {
    try {
      final devices = await UsbSerial.listDevices();

      for (final device in devices) {
        final p = await UsbSerial.createFromDeviceId(device.deviceId);
        if (p == null) continue;

        final opened = await p.open();
        if (!opened) {
          await p.close();
          continue;
        }

        await p.setPortParameters(
          ModbusRtu.baudRate,
          ModbusRtu.dataBits,
          ModbusRtu.stopBits,
          ModbusRtu.parity,
        );

        port = p;

        inputSub = port!.inputStream?.listen(
          _onDataReceived,
          onError: (_) => _handleDisconnect(),
          onDone: _handleDisconnect,
        );

        reconnectAttempts = 0;
        connectionStatus = "Connected";
        onStateChanged();

        _restartPolling();
        return;
      }

      _scheduleReconnect();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  ////////////////////////////////////////////////////////////
  /// DISCONNECT
  ////////////////////////////////////////////////////////////

  Future<void> _handleDisconnect() async {
    await _closePort();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    reconnectTimer?.cancel();
    reconnectAttempts++;
    reconnectTimer = Timer(
      Duration(seconds: reconnectAttempts.clamp(1, 10)),
      scanAndConnectUSB,
    );
  }

  Future<void> _closePort() async {
    await inputSub?.cancel();
    await port?.close();

    pollTimer?.cancel();
    requestTimeoutTimer?.cancel();

    inputSub = null;
    port = null;
    buffer.clear();

    _requestRunning = false;
    _pendingScanCompleter = null;
    _pendingScanSlaveId = null;

    connectionStatus = "Disconnected";
    onStateChanged();
  }

  ////////////////////////////////////////////////////////////
  /// POLLING
  ////////////////////////////////////////////////////////////

  void _restartPolling() {
    pollTimer?.cancel();

    if (port == null ||
        ModbusRtu.slaveIds.isEmpty ||
        isManualScanRunning) return;

    pollTimer = Timer.periodic(
      Duration(milliseconds: ModbusRtu.pollIntervalMs),
          (_) async {
        if (_requestRunning || port == null) return;

        final slaveId = ModbusRtu.slaveIds[slavePollingIndex];
        final model = ModbusRtu.getModelForSlave(slaveId);

        await _sendReadRequest(
          slaveId,
          model.startAddress,
          model.quantity,
        );

        slavePollingIndex =
            (slavePollingIndex + 1) % ModbusRtu.slaveIds.length;
      },
    );
  }

  ////////////////////////////////////////////////////////////
  /// SCAN MODE
  ////////////////////////////////////////////////////////////

  Future<List<int>?> readRegistersForScan({
    required int slaveId,
    required int startAddress,
    required int quantity,
    int attempts = 2,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    if (port == null) return null;

    _requestRunning = false;
    buffer.clear();
    _pendingScanCompleter = null;
    _pendingScanSlaveId = null;
    requestTimeoutTimer?.cancel();

    isManualScanRunning = true;
    pollTimer?.cancel();

    await Future.delayed(const Duration(milliseconds: 200));
    buffer.clear();
    _requestRunning = false;

    List<int>? result;

    for (int i = 0; i < attempts; i++) {
      _pendingScanCompleter = Completer<List<int>?>();
      _pendingScanSlaveId = slaveId;

      await Future.delayed(const Duration(milliseconds: 100));
      await _sendReadRequest(slaveId, startAddress, quantity);

      try {
        result = await _pendingScanCompleter!.future.timeout(timeout);
        if (result != null) break;
      } catch (_) {}

      _pendingScanCompleter = null;
      _pendingScanSlaveId = null;
    }

    isManualScanRunning = false;
    _restartPolling();

    return result;
  }

  ////////////////////////////////////////////////////////////
  /// SEND REQUEST
  ////////////////////////////////////////////////////////////

  Future<void> _sendReadRequest(
      int slaveId, int startAddress, int quantity) async {
    if (port == null || _requestRunning) return;

    _requestRunning = true;

    requestTimeoutTimer?.cancel();
    requestTimeoutTimer = Timer(const Duration(milliseconds: 1500), () {
      _requestRunning = false;
      // No response arrived in time. Drop whatever partial/stale bytes
      // are sitting in the buffer -- otherwise they can misalign parsing
      // of the *next* device's response and desync the parser
      // indefinitely (a device coming back online would then keep
      // failing its CRC check and look permanently "offline").
      buffer.clear();
    });

    final frame = <int>[
      slaveId,
      ModbusRtu.functionCode,
      (startAddress >> 8) & 0xFF,
      startAddress & 0xFF,
      (quantity >> 8) & 0xFF,
      quantity & 0xFF,
    ];

    final crc = crc16(Uint8List.fromList(frame));
    frame.addAll([crc & 0xFF, (crc >> 8) & 0xFF]);

    try {
      await port!.write(Uint8List.fromList(frame));
    } catch (_) {
      _requestRunning = false;
      _handleDisconnect();
    }
  }

  ////////////////////////////////////////////////////////////
  /// DATA RECEIVE
  ////////////////////////////////////////////////////////////

  void _onDataReceived(Uint8List data) {
    if (data.isEmpty) return;

    buffer.add(data);

    while (true) {
      final bytes = buffer.toBytes();

      if (bytes.length < 5) return;

      final byteCount = bytes[2];
      final frameLength = 3 + byteCount + 2;

      if (bytes.length < frameLength) return;

      final frame = bytes.sublist(0, frameLength);
      final body = frame.sublist(0, frameLength - 2);

      final crcRx = frame[frameLength - 2] | (frame[frameLength - 1] << 8);
      final crcCalc = crc16(Uint8List.fromList(body));

      if (crcCalc != crcRx) {
        // Frame boundary is mis-aligned -- likely a stray/partial byte
        // left over from a device that was offline or timed out
        // mid-response. Drop only the first byte and try to re-sync on
        // the next one, rather than wiping the whole buffer. Discarding
        // everything here would throw away a legitimate trailing frame
        // too, and if the desync isn't broken, every subsequent valid
        // response (including from a device that just came back online)
        // keeps failing this same check forever -- which is what makes
        // a recovered device look stuck "offline" until something
        // unrelated happens to reset the buffer.
        buffer.clear();
        buffer.add(bytes.sublist(1));
        continue;
      }

      final slaveId = frame[0];

      final payload = frame.sublist(3, 3 + byteCount);

      List<int> values = [];

      for (int i = 0; i < payload.length; i += 2) {
        values.add((payload[i] << 8) | payload[i + 1]);
      }

      final remaining = bytes.sublist(frameLength);
      buffer.clear();
      buffer.add(remaining);

      _requestRunning = false;
      requestTimeoutTimer?.cancel();

      if (_pendingScanCompleter != null &&
          !_pendingScanCompleter!.isCompleted) {
        if (slaveId == _pendingScanSlaveId) {
          _pendingScanCompleter!.complete(values);
        }
        return;
      }

      final model = ModbusRtu.getModelForSlave(slaveId);

      final registers = List.generate(
        values.length,
            (i) => RegisterData(
          address: model.startAddress + i,
          value: values[i],
        ),
      );

      final index = slaveId - 1;

      if (index >= 0 && index < slaveRegistersNotifier.length) {
        slaveRegistersNotifier[index].value = registers;
      }

      slaveLastSeen[slaveId] = DateTime.now();

      onStateChanged();
    }
  }

  ////////////////////////////////////////////////////////////
  /// CRC16
  ////////////////////////////////////////////////////////////

  int crc16(Uint8List bytes) {
    int crc = 0xFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
      }
    }
    return crc;
  }

  ////////////////////////////////////////////////////////////
  /// DISPOSE
  ////////////////////////////////////////////////////////////

  Future<void> dispose() async {
    reconnectTimer?.cancel();
    usbEventSub?.cancel();
    await _closePort();
  }
}
