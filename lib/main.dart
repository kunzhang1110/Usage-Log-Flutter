import 'constants.dart';
import 'models/app_event.dart';
import 'models/app_model.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:android_package_manager/android_package_manager.dart';

import 'models/app_usage.dart';
import 'utils.dart';

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
  List<AppUsage> _appConciseUsages = [];
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

  bool _isResumed(AppEvent appEvent) {
    return appEvent.eventType == "Activity Resumed";
  }

  bool _isPausedOrStopped(AppEvent appEvent) {
    return appEvent.eventType == "Activity Paused" ||
        appEvent.eventType == "Activity Stopped";
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

    var defaultIcon = await _loadIcon("default-icon.png");
    var lockIcon = await _loadIcon("lock-icon.png");
    // retrieve all events to appEvents and appNameToAppEventMap
    for (var event in queryEvents) {
      var packageName = event.packageName;
      var eventType = eventTypeMap[int.parse(event.eventType!)];
      if (eventType == null || packageName == null) continue;

      var appEvent = AppEvent.empty();
      appEvent.eventType = eventType;
      appEvent.time =
          DateTime.fromMillisecondsSinceEpoch(int.parse(event.timeStamp!));

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
            defaultIcon;
      } catch (e) {
        print(e);
        appEvent.appIconByte = defaultIcon;
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

          if (_isResumed(eventX)) {
            int y = x + 1;

            while (y < events.length && !_isPausedOrStopped(events[y])) {
              y++;
            }

            if (y < events.length) {
              var eventY = events[y];
              Duration duration = eventY.time.difference(eventX.time);
              int durationInSeconds = duration.inSeconds;

              if (durationInSeconds > 0) {
                var appUsage = AppUsage(
                  appName: appName,
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

    // calculate screen locked usage from app usages gaps
    for (int i = 0; i < appUsages.length - 1; i++) {
      AppUsage currentAppUsage = appUsages[i];
      AppUsage nextAppUsage = appUsages[i + 1];

      // Calculate the end time of the current app usage
      DateTime currentAppUsageEndTime = currentAppUsage.time
          .add(Duration(seconds: currentAppUsage.durationInSeconds));
      Duration timeDiff = nextAppUsage.time.difference(currentAppUsageEndTime);

      if (timeDiff.inSeconds > 1) {
        // Create a new "Screen Locked" app usage entry
        AppUsage screenLockedAppUsage = AppUsage(
          appName: "Screen Locked",
          durationInSeconds: timeDiff.inSeconds,
          time: currentAppUsageEndTime,
          appIconByte: lockIcon, // Placeholder for default icon if needed
        );

        // Insert the screen locked usage into the list
        appUsages.insert(i + 1, screenLockedAppUsage);

        // If the screen locked time is long enough, add to the concise list
        if (screenLockedAppUsage.durationInSeconds >= conciseMinTimeInSeconds) {
          appConciseUsages.add(screenLockedAppUsage);
          appConciseUsages.add(nextAppUsage);
        }

        i++; // Skip next iteration to avoid duplication
      }
    }

    setState(() {
      _appEvents = appEvents.reversed.toList();
      _appUsages = appUsages.reversed.toList();
      _appConciseUsages = appConciseUsages.reversed.toList();
    });
  }

  /// Copies all event times that are between [sessionStartTime] and [sessionEndTime] onto clipboard.
  void _handleCopyBtnOnclick() async {
    final copyText = <String>[];

    final DateTime firstStartDateTime = _appConciseUsages.last.time;
    final DateTime referenceDateTime = DateTime(
      firstStartDateTime.year,
      firstStartDateTime.month,
      firstStartDateTime.day,
      0,
      0,
    );

    for (var i = _appConciseUsages.length - 1; i > 0; i--) {
      final appUsageStartDateTime = _appConciseUsages[i].time;
      final durationInSeconds = _appConciseUsages[i].durationInSeconds;

      final DateTime sessionStartDateTime = DateTime(
        referenceDateTime.year,
        referenceDateTime.month,
        referenceDateTime.day,
        copySessionStartTime.hour,
        copySessionStartTime.minute,
      );

      final DateTime sessionEndDateTime = DateTime(
        referenceDateTime.year,
        referenceDateTime.month,
        referenceDateTime.day + 1,
        copySessionEndTime.hour,
        copySessionEndTime.minute,
      );

      final bool isInCopySession = appUsageStartDateTime.isAfter(sessionStartDateTime) &&
          appUsageStartDateTime.isBefore(sessionEndDateTime);

      if (isInCopySession && durationInSeconds > conciseMinTimeInSeconds) {
        copyText.add(getAppModelTimeText(_appConciseUsages, i));
      }
    }

    final clipboardData = ClipboardData(text: copyText.join(' '));
    await Clipboard.setData(clipboardData);
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
                await Clipboard.setData(
                    ClipboardData(text: getAppModelTimeText(appModels, index)));
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
                  Text(appModels[index].time.toString().substring(0, 19)),
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
