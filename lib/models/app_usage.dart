import 'app_model.dart';

class AppUsage extends AppModel {
  AppUsage({
    required this.durationInSeconds,
    required super.time,
    required super.appName,
    required super.appIconByte,
  }) {
    int seconds = durationInSeconds % 60;
    int minutes = (durationInSeconds ~/ 60) % 60;
    int hours = (durationInSeconds ~/ (60 * 60));
    durationInText = "${hours}h ${minutes}m ${seconds}s";
  }

  int durationInSeconds = 0;
  String? durationInText;
}
