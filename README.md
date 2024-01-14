# gdlogging Godot addon

## Usage

```gdscript
Logger.add_sink(Logger.DirSink.new("MyLog", "res://log"))
Logger.add_sink(Logger.ConsoleSink.new())
Logger.debug("Hello World")                                 # Outputs: [24/Jan/13_22:59:12] [         Global] [DBG] Hello World
Logger.LocalLogger("MyClass").debug("Hello World")          # Outputs: [24/Jan/13_22:59:12] [        MyClass] [DBG] Hello World
Logger.info(Logger.format_error(ERR_FILE_NOT_FOUND))        # Outputs: [24/Jan/13_22:59:12] [         Global] [INF] File: Not found error.
```

## Sinks

* `FilteringSink`: Filters messages by level and forwards them to another sink
* `BroadcastSink`: Broadcasts messages to multiple sinks
* `BufferedSink`: Buffers messages and forwards them to another sink
* `ConsoleSink`: Outputs messages to the console
* `DirSink`: Outputs messages to a log files and rotates them
* `LocalLogger`: Can receive messages from other LocalLoggers and Sinks. Users will call the log functions which format the message.
* `MemoryWindowSink`: Keeps `n` log messages in memory. Can be used to display the last `n` messages in a GUI.

## Log Levels

* `Logger.TRACE`: Prints the call site in debug builds. The stack depth can be configured per call.
* `Logger.DEBUG`: Debug messages
* `Logger.INFO`: Informational messages
* `Logger.WARN`: Warnings
* `Logger.ERROR`: Errors

## Custom Formatters

```gdscript
class MyLogRecordFormatter extends Logger.LogRecordFormatter:
  func format(log_record: Dictionary, raw_message: String) -> String:
    var time_unix = log_record["time_unix"]
    var level = log_record["level"]

    var time_str = Time.get_date_string_from_unix_time(time_unix)
    var level_str = Logger.get_level_name(level)
    var formatted_message = "[%s] [%s] %s" % [
      time_str,
      level_str,
      raw_message
    ]
    return formatted_message
set_log_record_formatter(MyLogRecordFormatter.new())
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
