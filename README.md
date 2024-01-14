# gdlogging Godot addon

## Usage

```gdscript
Logger.add_sink(Logger.DirSink.new("MyLog", "res://log"))
Logger.debug("Hello World")                                 # Outputs: [         Global] [24/Jan/13_22:59:12] [DBG] Hello World
Logger.LocalLogger("MyClass").debug("Hello World")          # Outputs: [        MyClass] [24/Jan/13_22:59:12] [DBG] Hello World
Logger.info(Logger.format_error(ERR_FILE_NOT_FOUND))        # Outputs: [         Global] [24/Jan/13_22:59:12] [INF] File: Not found error.
```

## Sinks

* `FilteringSink`: Filters messages by level and forwards them to another sink
* `BroadcastSink`: Broadcasts messages to multiple sinks
* `BufferedSink`: Buffers messages and forwards them to another sink
* `ConsoleSink`: Outputs messages to the console
* `DirSink`: Outputs messages to a log files and rotates them
* `LocalLogger`: Can receive messages from other LocalLoggers and Sinks. Users will call the log functions which format the message.
* `MemoryWindowSink: Keeps `n` log messages in memory. Can be used to display the last `n` messages in a GUI.

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
