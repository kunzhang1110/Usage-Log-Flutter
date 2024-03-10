import 'app_model.dart';

class AppEvent extends AppModel {
  AppEvent({
    required super.time,
    required super.appName,
    required super.appIconByte,
    required this.eventType,
  });

  String? eventType;
}
