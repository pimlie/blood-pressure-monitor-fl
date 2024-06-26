import 'dart:async';

import 'package:blood_pressure_app/bluetooth/ble_read_cubit.dart';
import 'package:blood_pressure_app/bluetooth/bluetooth_cubit.dart';
import 'package:blood_pressure_app/bluetooth/characteristics/ble_measurement_data.dart';
import 'package:blood_pressure_app/bluetooth/device_scan_cubit.dart';
import 'package:blood_pressure_app/bluetooth/flutter_blue_plus_mockable.dart';
import 'package:blood_pressure_app/components/bluetooth_input/closed_bluetooth_input.dart';
import 'package:blood_pressure_app/components/bluetooth_input/device_selection.dart';
import 'package:blood_pressure_app/components/bluetooth_input/input_card.dart';
import 'package:blood_pressure_app/components/bluetooth_input/measurement_failure.dart';
import 'package:blood_pressure_app/components/bluetooth_input/measurement_success.dart';
import 'package:blood_pressure_app/logging.dart';
import 'package:blood_pressure_app/model/storage/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show BluetoothDevice, Guid;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:health_data_store/health_data_store.dart';

/// Class for inputting measurement through bluetooth.
class BluetoothInput extends StatefulWidget {
  /// Create a measurement input through bluetooth.
  const BluetoothInput({super.key,
    required this.onMeasurement,
    this.bluetoothCubit,
    this.deviceScanCubit,
    this.bleReadCubit,
    this.flutterBluePlus,
  });

  /// Called when a measurement was received through bluetooth.
  final void Function(BloodPressureRecord data) onMeasurement;

  /// Function to customize [BluetoothCubit] creation.
  final BluetoothCubit Function()? bluetoothCubit;

  /// Function to customize [DeviceScanCubit] creation.
  final DeviceScanCubit Function()? deviceScanCubit;

  /// Function to customize [BleReadCubit] creation.
  final BleReadCubit Function(BluetoothDevice dev)? bleReadCubit;

  final FlutterBluePlusMockable? flutterBluePlus;

  @override
  State<BluetoothInput> createState() => _BluetoothInputState();
}

class _BluetoothInputState extends State<BluetoothInput> {
  /// Whether the user expanded bluetooth input
  bool _isActive = false;

  late final BluetoothCubit _bluetoothCubit;
  DeviceScanCubit? _deviceScanCubit;
  BleReadCubit? _deviceReadCubit;

  StreamSubscription<BluetoothState>? _bluetoothSubscription;

  /// Data received from reading bluetooth values.
  ///
  /// Its presence indicates that this input is done.
  BleMeasurementData? _finishedData;

  @override
  void initState() {
    super.initState();
    _bluetoothCubit = widget.bluetoothCubit?.call()
      ?? BluetoothCubit(flutterBluePlus: widget.flutterBluePlus);
  }

  @override
  void dispose() {
    unawaited(_bluetoothSubscription?.cancel());
    unawaited(_bluetoothCubit.close());
    unawaited(_deviceScanCubit?.close());
    unawaited(_deviceReadCubit?.close());
    super.dispose();
  }

  void _returnToIdle() async {
    // No need to show wait in the UI.
    if (_isActive) {
      setState(() {
        _isActive = false;
        _finishedData = null;
      });
    }

    await _deviceReadCubit?.close();
    _deviceReadCubit = null;
    await _deviceScanCubit?.close();
    _deviceScanCubit = null;
    await _bluetoothSubscription?.cancel();
    _bluetoothSubscription = null;
  }

  Widget _buildActive(BuildContext context) {
    final Guid serviceUUID = Guid('1810');
    final Guid characteristicUUID = Guid('2A35');
    _bluetoothSubscription = _bluetoothCubit.stream.listen((state) {
      if (state is! BluetoothReady) {
        Log.trace('_BluetoothInputState: _bluetoothSubscription state=$state, calling _returnToIdle');
        _returnToIdle();
      }
    });
    final settings = context.watch<Settings>();
    _deviceScanCubit ??= widget.deviceScanCubit?.call() ?? DeviceScanCubit(
      service: serviceUUID,
      settings: settings,
      flutterBluePlus: widget.flutterBluePlus,
    );
    return BlocBuilder<DeviceScanCubit, DeviceScanState>(
      bloc: _deviceScanCubit,
      builder: (context, DeviceScanState state) {
        Log.trace('BluetoothInput _BluetoothInputState _deviceScanCubit: $state');
        SizeChangedLayoutNotification().dispatch(context);
        return switch(state) {
          DeviceListLoading() => _buildMainCard(context,
            title: Text(AppLocalizations.of(context)!.scanningForDevices),
            child: const CircularProgressIndicator(),
          ),
          DeviceListAvailable() => DeviceSelection(
            scanResults: state.devices,
            onAccepted: (dev) => _deviceScanCubit!.acceptDevice(dev),
          ),
          SingleDeviceAvailable() => DeviceSelection(
            scanResults: [ state.device ],
            onAccepted: (dev) => _deviceScanCubit!.acceptDevice(dev),
          ),
            // distinction
          DeviceSelected() => BlocConsumer<BleReadCubit, BleReadState>(
            bloc: () {
              _deviceReadCubit = widget.bleReadCubit?.call(state.device) ?? BleReadCubit(
                state.device,
                characteristicUUID: characteristicUUID,
                serviceUUID: serviceUUID,
              );
              return _deviceReadCubit;
            }(),
            listener: (BuildContext context, BleReadState state) {
              if (state is BleReadSuccess) {
                final BloodPressureRecord record = BloodPressureRecord(
                  time: state.data.timestamp ?? DateTime.now(),
                  sys: state.data.isMMHG
                    ? Pressure.mmHg(state.data.systolic.toInt())
                    : Pressure.kPa(state.data.systolic),
                  dia: state.data.isMMHG
                    ? Pressure.mmHg(state.data.diastolic.toInt())
                    : Pressure.kPa(state.data.diastolic),
                  pul: state.data.pulse?.toInt(),
                );
                widget.onMeasurement(record);
                setState(() {
                  _finishedData = state.data;
                });
              }
            },
            builder: (BuildContext context, BleReadState state) {
              Log.trace('_BluetoothInputState BleReadCubit: $state');
              SizeChangedLayoutNotification().dispatch(context);
              return switch (state) {
                BleReadInProgress() => _buildMainCard(context,
                  child: const CircularProgressIndicator(),
                ),
                BleReadFailure() => MeasurementFailure(
                  onTap: _returnToIdle,
                ),
                BleReadSuccess() => MeasurementSuccess(
                  onTap: _returnToIdle,
                  data: state.data,
                ),
              };
            },
          ),
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    SizeChangedLayoutNotification().dispatch(context);
    if (_finishedData != null) {
      return MeasurementSuccess(
        onTap: _returnToIdle,
        data: _finishedData!,
      );
    }
    if (_isActive) return _buildActive(context);
    return ClosedBluetoothInput(
      bluetoothCubit: _bluetoothCubit,
      onStarted: () => setState(() =>_isActive = true),
      inputInfo: () async {
        if (context.mounted) {
          await showDialog(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: Text(AppLocalizations.of(context)!.bluetoothInput),
              content: Text(AppLocalizations.of(context)!.aboutBleInput),
                actions: <Widget>[
                  ElevatedButton(
                    child: Text((AppLocalizations.of(context)!.btnConfirm)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
            ),
          );
        }
      },
    );
  }

  Widget _buildMainCard(BuildContext context, {
    required Widget child,
    Widget? title,
  }) => InputCard(
    onClosed: _returnToIdle,
    title: title,
    child: child,
  );
}
