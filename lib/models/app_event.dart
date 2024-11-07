import 'dart:typed_data';

import 'app_model.dart';

class AppEvent extends AppModel {
  AppEvent({
    required super.time,
    required super.appName,
    required super.appIconByte,
    required this.eventType,
  });

  AppEvent.empty()
      : eventType = null,
        super(time: DateTime.now(), appName: '', appIconByte: Uint8List(0));

  String? eventType;
}
