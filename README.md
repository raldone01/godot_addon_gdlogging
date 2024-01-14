# gdlogging Godot addon

## Usage

```gdscript
var console_sink = Log.ConsoleSink.new()
Log.add_sink(console_sink)

var dir_sink = Log.DirSink.new("mylog", "res://logs", 4042)
var buffered_sink = Log.BufferedSink.new(dir_sink, 500)
# Don't log TRACE messages to the log file
var file_filtered_sink = Log.FilteringSink.new(buffered_sink, Log.DEBUG)
Log.add_sink(file_filtered_sink)

Log.debug("Hello World")
# [24/Jan/14 13:28:03] [         Global] [DBG] Hello World
var logger: Log.LocalLogger = Log.LocalLog.new("MyClass")
logger.debug("Hello World")
# [24/Jan/14 13:28:03] [        MyClass] [DBG] Hello World
Log.info(Log.format_error(ERR_FILE_NOT_FOUND))
# [24/Jan/14 13:28:03] [         Global] [INF] File: Not found error.
var timer = Log.LogTimer.new("MyTimer", 0, logger)
OS.delay_msec(1111)
timer.stop()
# [24/Jan/14 13:28:04] [        MyClass] [INF] MyTimer took 1.111963 seconds.
const threshold_msec: int = 1000
timer.set_threshold_msec(threshold_msec)
timer.start()
OS.delay_msec(800)
timer.stop()
# Prints nothing, because the timer was stopped before the threshold was reached.
timer.start()
OS.delay_msec(1111)
timer.stop()
# [24/Jan/14 13:28:06] [        MyClass] [INF] MyTimer exceeded threshold of 1000 msec: took 1.111750 seconds.
```

## Sinks

* `FilteringSink`: Filters messages by level and forwards them to another sink.
* `BroadcastSink`: Broadcasts messages to multiple sinks.
* `BufferedSink`: Buffers messages and forwards them to another sink.
* `ConsoleSink`: Outputs messages to the console.
* `DirSink`: Outputs messages to a log files and rotates them. Uses a thread for file io.
* `LocalLogger`: Can receive messages from other LocalLoggers and Sinks. Users will call the log functions which format the message.
* `MemoryWindowSink`: Keeps `n` log messages in memory. Can be used to display the last `n` messages in a GUI.

## Log Levels

* `Log.TRACE`: Prints the call site in debug builds. The stack depth can be configured per call.
* `Log.DEBUG`: Debug messages
* `Log.INFO`: Informational messages
* `Log.WARN`: Warnings
* `Log.ERROR`: Errors

## Custom Formatters

```gdscript
class MyLogRecordFormatter extends Log.LogRecordFormatter:
  func format(log_record: Dictionary, raw_message: String) -> String:
    var time_unix = log_record["time_unix"]
    var level = log_record["level"]

    var time_str = Time.get_date_string_from_unix_time(time_unix)
    var level_str = Log.get_level_name(level)
    var formatted_message = "[%s] [%s] %s" % [
      time_str,
      level_str,
      raw_message
    ]
    return formatted_message
# LocalLoggers use the global formatter by default but this can be overridden in the constructor.
Log.set_log_record_formatter(MyLogRecordFormatter.new())
```

## Installation

```bash
cd <godot_project_dir>
cd addons
git submodule add git@github.com:raldone01/godot_addon_gdlogging.git gdlogging
```

`Project -> Project Settings -> Plugins -> gdlogging -> Activate`

## Licensing

Marked parts are licensed under the `LICENSE-godot-logger.md` (MIT) license.
The rest is licensed under `LICENSE.md` (MIT).
