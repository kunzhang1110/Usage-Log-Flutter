import 'package:flutter/material.dart';

const Map<int, String> eventTypeMap = {
  1: "Activity Resumed",
  23: "Activity Stopped",
  16: "Screen Non-Interactive",
  18: "Keyguard Hidden",
  15: "Screen Interactive",
  17: "Keyguard Shown",
  2: "Activity Paused",
  19: "Foreground Service Start",
  20: "Foreground Service Stop",
  27: "Device Startup",
  26: "Device Shutdown",
  5: "Configuration Change",
  8: "Shortcut Invocation",
  7: "User Interaction",
};

const List<String>
    eventTypeForDurationList = //These four types are used in calculate duration
    [
  "Activity Resumed",
  "Activity Paused",
  "Activity Stopped",
];

const List<String> appNameExcludedList = [
  "Permission controller",
  "Pixel Launcher",
  "Quickstep",
  "System UI"
];

const int conciseMinTimeInSeconds = 1200;

const int daysOfEventsIncluded = 1;

const copySessionStartTime = TimeOfDay(hour: 23, minute: 0);
const copySessionEndTime = TimeOfDay(hour: 8, minute: 0);
