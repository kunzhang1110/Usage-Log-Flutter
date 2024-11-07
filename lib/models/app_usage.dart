import 'app_model.dart';

class AppUsage extends AppModel {
  AppUsage({
    required int durationInSeconds,
    required super.time,
    required super.appName,
    required super.appIconByte,
  }) {
    this.durationInSeconds = durationInSeconds;
  }

  int _durationInSeconds = 0;

  int get durationInSeconds => _durationInSeconds;

  set durationInSeconds(int value) {
    _durationInSeconds = value;
    int seconds = value % 60;
    int minutes = (value ~/ 60) % 60;
    int hours = (value ~/ (60 * 60));
    durationInText = "${hours}h ${minutes}m ${seconds}s";
  }
  String? durationInText;
}
