import 'constants.dart';
import 'models/app_event.dart';
import 'models/app_model.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:android_package_manager/android_package_manager.dart';

import 'models/app_usage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<AppEvent> _appEvents = [];
  List<AppUsage> _appUsages = [];
  final List<AppUsage> _appConciseUsages = [];
  int _selectedIndex = 0;
  final AndroidPackageManager _packageManager = AndroidPackageManager();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshIndicatorKey.currentState?.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    var content = _buildListView();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Usage Log"),
          actions: [
            _selectedIndex == 0
                ? IconButton(
                    onPressed: _handleCopyBtnOnclick,
                    icon: const Icon(Icons.copy))
                : const SizedBox()
          ],
        ),
        body: RefreshIndicator(
          key: _refreshIndicatorKey,
          onRefresh: _updateData,
          child: Center(
            child: content,
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _controller.animateTo(
              0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
            );
          },
          mini: true,
          child: const Icon(
            Icons.arrow_upward,
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.summarize),
              label: 'Concise',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.topic),
              label: 'All',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.stacked_bar_chart),
              label: 'Raw',
            ),
          ],
          currentIndex: _selectedIndex,
          selectedItemColor: Colors.amber[800],
          onTap: (int index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }

  bool _isResumedOrNonInteractive(AppEvent appEvent) {
    return appEvent.eventType == "Activity Resumed" ||
        appEvent.eventType == "Screen Non-Interactive";
  }

  bool _isPausedOrStoppedOrKeyguardHidden(AppEvent appEvent) {
    return appEvent.eventType == "Activity Paused" ||
        appEvent.eventType == "Activity Stopped" ||
        appEvent.eventType == "Keyguard Hidden";
  }

  Future<Uint8List> _loadIcon(String name) async {
    // Replace with actual logic to load a default icon from assets
    final ByteData data = await rootBundle.load('assets/$name');
    return data.buffer.asUint8List();
  }

  Future<void> _updateData() async {
    UsageStats.grantUsagePermission();

    if (_appEvents.isNotEmpty) {
      setState(() {
        _appEvents.clear();
        _appUsages.clear();
        _appConciseUsages.clear();
      });
    }

    DateTime endDate = DateTime.now();
    DateTime startDate =
        endDate.add(const Duration(days: -daysOfEventsIncluded));

    List<EventUsageInfo> queryEvents =
        await UsageStats.queryEvents(startDate, endDate);

    List<AppEvent> appEvents = [];
    List<AppUsage> appUsages = [];
    List<AppUsage> appConciseUsages = [];
    Map<String, List<AppEvent>> appNameToAppEventMap = {};

    // retrieve all events to appEvents and appNameToAppEventMap
    for (var event in queryEvents) {
      var packageName = event.packageName;
      var eventType = eventTypeMap[int.parse(event.eventType!)];
      if (eventType == null || packageName == null) continue;

      var appEvent = AppEvent.empty();
      appEvent.eventType = eventType;
      appEvent.time = DateTime.fromMillisecondsSinceEpoch(
          int.parse(event.timeStamp!));

      try {
        var appName =
            await _packageManager.getApplicationLabel(packageName: packageName);
        if (appNameExcludedList.contains(appName)) continue;
        appEvent.appName = appName ?? packageName;
      } catch (e) {
        print(e);
        appEvent.appName = packageName;
      }

      try {
        appEvent.appIconByte = await _packageManager.getApplicationIcon(
                packageName: packageName) ??
            await _loadIcon("default-icon.svg");
      } catch (e) {
        print(e);
        appEvent.appIconByte = await _loadIcon("default-icon.svg");
      }

      if (eventTypeForDurationList.contains(eventType)) {
        appNameToAppEventMap
            .putIfAbsent(appEvent.appName, () => List.empty(growable: true))
            .add(appEvent);
      }
      appEvents.add(appEvent);
    }

    // calculate app usages
    appNameToAppEventMap.forEach(
      (String appName, List<AppEvent> events) {
        for (int x = 0; x < events.length; x++) {
          var eventX = events[x];

          if (_isResumedOrNonInteractive(eventX)) {
            int y = x + 1;

            while (y < events.length &&
                _isPausedOrStoppedOrKeyguardHidden(events[y])) {
              y++;
            }

            if (y < events.length) {
              var eventY = events[y];
              Duration duration = eventY.time.difference(eventX.time);
              int durationInSeconds = duration.inSeconds;

              if (durationInSeconds > 0) {
                var appUsage = AppUsage(
                  appName:
                      appName == "Android System" ? "Screen Locked" : appName,
                  appIconByte: eventX.appIconByte,
                  time: eventX.time,
                  durationInSeconds: durationInSeconds,
                );
                appUsage.durationInSeconds = durationInSeconds;
                appUsages.add(appUsage);
                x = y;
              }
            }
          }
        }
      },
    );

    appUsages.sort();

    // merge  consecutive activities with the same name
    AppUsage? previousAppUsage;
    for (int i = 0; i < appUsages.length;) {
      AppUsage currentAppUsage = appUsages[i];

      if (previousAppUsage != null &&
          previousAppUsage.appName == currentAppUsage.appName) {
        previousAppUsage.durationInSeconds =
            previousAppUsage.durationInSeconds +
                currentAppUsage.durationInSeconds;

        appUsages.removeAt(i);
      } else {
        previousAppUsage = currentAppUsage;
        i++;
      }
    }

    setState(() {
      _appEvents = appEvents.reversed.toList();
      _appUsages = appUsages.reversed.toList();

      //only show each Screen Locked that is longer than certain min. and the activity before it
      for (int i = 1; i < _appUsages.length; i++) {
        if (_appUsages[i].appName == "Screen Locked" &&
            (_appUsages[i].durationInSeconds >= conciseMinTimeInSeconds)) {
          _appConciseUsages.add(_appUsages[i - 1]);
          _appConciseUsages.add(_appUsages[i]);
        }
      }
    });
  }

  String _getRoundedTimeString(DateTime dateTime) {
    int minutes = dateTime.minute;
    int roundedMinutes = (minutes / 5).round() * 5;
    return DateTime(dateTime.year, dateTime.month, dateTime.day, dateTime.hour,
            roundedMinutes)
        .toIso8601String()
        .substring(11, 16)
        .split(':')
        .join();
  }

  String _getAppModelTimeText(List<AppModel> data, int index) {
    if (index < data.length - 1) {
      // if the time difference between this event and previous event  time is less than 5 minutes
      Duration duration = data[index + 1].time.difference(data[index].time);
      if (duration.inMinutes < 5) {
        // add five minutes toe this event start time
        data[index].time = data[index].time.add(const Duration(minutes: 5));
      }
    }

    var startTimeText = _getRoundedTimeString(data[index].time);
    var endTimeText = _getRoundedTimeString(data[index - 1].time);

    return '$startTimeText$endTimeText';
  }

  /// Copies all event times that are between [sessionStartTime] and [sessionEndTime] onto clipboard.
  void _handleCopyBtnOnclick() {
    final copyText = <String>[];

    int firstIdx =
        -1; // the first index of the event before sessionStartTime, used as a flag

    for (var i = _appConciseUsages.length - 1; i > 0; i--) {
      final appUsageStartTime = _appConciseUsages[i].time;
      final durationInSeconds = _appConciseUsages[i].durationInSeconds;

      final isAfterStartTime =
          appUsageStartTime.hour > copySessionStartTime.hour ||
              (appUsageStartTime.hour == copySessionStartTime.hour &&
                  appUsageStartTime.minute > copySessionStartTime.minute);
      final isBeforeEndTime =
          appUsageStartTime.hour < copySessionEndTime.hour ||
              (appUsageStartTime.hour == copySessionEndTime.hour &&
                  appUsageStartTime.minute < copySessionEndTime.minute);

      if (isAfterStartTime && firstIdx == -1) {
        // find the first index that is after 22:00
        firstIdx = i;
      }

      if ((isAfterStartTime || isBeforeEndTime) &&
          durationInSeconds > conciseMinTimeInSeconds &&
          firstIdx != -1) {
        copyText.add(_getAppModelTimeText(_appConciseUsages, i));
      }
    }

    final clipboardData = ClipboardData(text: copyText.join(' '));
    Clipboard.setData(clipboardData);
  }

  Widget _buildListView() {
    List<AppModel> appModels = [];

    if (_selectedIndex == 0) {
      appModels = _appConciseUsages;
    }

    if (_selectedIndex == 1) {
      appModels = _appUsages;
    }

    if (_selectedIndex == 2) {
      appModels = _appEvents;
    }

    return ListView.separated(
        controller: _controller,
        separatorBuilder: (context, index) => const Divider(),
        itemCount: appModels.length,
        itemBuilder: (context, index) {
          return InkWell(
            onLongPress: () async {
              if (index >= 1 && _selectedIndex == 0) {
                await Clipboard.setData(ClipboardData(
                    text: _getAppModelTimeText(appModels, index)));
              }
            },
            child: Padding(
              padding: _selectedIndex == 2
                  ? const EdgeInsets.fromLTRB(45, 5, 0, 5)
                  : const EdgeInsets.symmetric(horizontal: 45, vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Text(appModels[index].time.toString().substring(0, 16)),
                  const SizedBox(
                    width: 25,
                  ),
                  appModels[index].appIconByte != null
                      ? Image.memory(
                          appModels[index].appIconByte!,
                          width: 35,
                          height: 35,
                        )
                      : const Text(""),
                  const SizedBox(
                    width: 25,
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        Widget? subText;
                        if (_selectedIndex == 0 || _selectedIndex == 1) {
                          var appUsage = appModels[index] as AppUsage;
                          subText = Text(
                            "${appUsage.durationInText}",
                            style: TextStyle(
                                color: appUsage.durationInSeconds >
                                        conciseMinTimeInSeconds //if duration longer than 30 minutes make font red
                                    ? Colors.red
                                    : Colors.black),
                          );
                        }
                        if (_selectedIndex == 2) {
                          var appEvent = appModels[index] as AppEvent;
                          subText = Text(
                            "${appEvent.eventType}",
                            overflow: TextOverflow.visible,
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(appModels[index].appName),
                            if (subText != null) subText
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
  }
}
