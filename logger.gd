# Copyright (c) 2024 The gdlogging Contributors
# Inspired by https://github.com/KOBUGE-Games/godot-logger/blob/master/logger.gd
@tool
extends Node

enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3,
	MAX,
}

const DEBUG = LogLevel.DEBUG
const INFO = LogLevel.INFO
const WARNING = LogLevel.WARNING
const ERROR = LogLevel.ERROR

const LEVEL_NAMES = [
	"DEBUG",
	"INFO",
	"WARNING",
	"ERROR",
]

func get_level_name(level: LogLevel) -> String:
	return LEVEL_NAMES[level]

const SHORT_LEVEL_NAMES = [
	"DBG",
	"INF",
	"WRN",
	"ERR",
]

func get_short_level_name(level: LogLevel) -> String:
	return SHORT_LEVEL_NAMES[level]

static func format_month(month: int) -> String:
	const month_names = [
		"Jan",
		"Feb",
		"Mar",
		"Apr",
		"May",
		"Jun",
		"Jul",
		"Aug",
		"Sep",
		"Oct",
		"Nov",
		"Dec",
	]
	return month_names[month - 1]

static func format_session(session: int)	-> String:
	return "%04d" % session

static func format_time(unix_time: float) -> String:
	var time: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	var time_str = "%02d/%s/%02d_%02d:%02d:%02d" % [
		time["year"] % 100,
		format_month(time["month"]),
		time["day"],
		time["hour"],
		time["minute"],
		time["second"],
	]
	return time_str

## Base class to be inherited by sinks.
## All message formatting has already been done by the logger.
class LogSink:
	## Writes a string to the sink
	func write(details: Dictionary, message: String) -> void:
		printerr("LogSink: write() not implemented.")
	func flush_buffer() -> void:
		printerr("LogSink: flush_buffer() not implemented.")

class FilteringSink extends LogSink:
	var _sink: LogSink
	var _level: LogLevel

	func _init(sink: LogSink, level: LogLevel) -> void:
		_sink = sink
		_level = level

	func write(details: Dictionary, message: String) -> void:
		var level = details["level"]
		if level >= _level:
			_sink.write(details, message)

	func flush_buffer() -> void:
		_sink.flush_buffer()

class BroadcastSink extends LogSink:
	var _sinks: Array = []

	func add_sink(sink: LogSink) -> void:
		_sinks.append(sink)

	func remove_sink(sink: LogSink) -> void:
		_sinks.erase(sink)

	func write(details: Dictionary, message: String) -> void:
		for sink in _sinks:
			sink.write(details, message)

	func flush_buffer() -> void:
		for sink in _sinks:
			sink.flush_buffer()

class BufferedSink extends LogSink:
	var _sink: LogSink

	var _buffer_details: Array = []
	var _buffer = PackedStringArray()
	var _buffer_cnt = 0
	var _buffer_size = 0

	## Creates a new BufferedSink.
	##
	## [param sink]: The sink to write to.
	## [param buffer_size]: The size of the buffer. If 0, the buffer will be disabled.
	##
	## The buffer size is the number of messages that will be buffered before being flushed to the sink.
	func _init(sink: LogSink, buffer_size: int) -> void:
		if buffer_size < 0:
			buffer_size = 0
			printerr("BufferedSink: Buffer size must be equal or greater than 0.")
		_buffer_size = buffer_size
		_sink = sink

	## Flushes the buffer to the sink.
	func flush_buffer() -> void:
		for i in range(_buffer_cnt):
			_sink.write(_buffer_details[i], _buffer[i])
		_buffer_cnt = 0
		_sink.flush_buffer()

	## Writes a string to the end of the buffer.
	func write(details: Dictionary, message: String) -> void:
		if _buffer_size == 0:
			_sink.write(details, message)
			return
		_buffer_details.append(details)
		_buffer.append(message)
		_buffer_cnt += 1
		if _buffer_cnt >= _buffer_size:
			flush_buffer()

class ConsoleSink extends LogSink:
	func write(details: Dictionary, message: String) -> void:
		var level = details["level"]
		if level == LogLevel.DEBUG:
			print_debug(message)
		elif level == LogLevel.INFO:
			print(message)
		elif level == LogLevel.WARNING:
			print(message)
		elif level == LogLevel.ERROR:
			printerr(message)
	func flush_buffer() -> void:
		pass

class DirSink extends LogSink:
	var _log_name: String
	var _dir_path: String
	var _max_file_size: int
	var _max_file_count: int

	var _current_file: FileAccess
	var _current_file_size: int

	var _last_dir_listing: Array = []

	static var _last_session_id: int = randi() % 1000 + roundi(Time.get_unix_time_from_system() * 1000) % 1000
	var _session_id: int = _last_session_id + 1

	func _init(log_name: String, dir_path: String, max_file_size: int = 4042, max_file_count: int = 10) -> void:
		_log_name = log_name
		_dir_path = _validate_dir(dir_path)
		self._max_file_size = max_file_size
		self._max_file_count = max_file_count

	func _validate_dir(dir_path: String) -> Variant:
		if not (dir_path.is_absolute_path() or dir_path.is_relative_path()):
			printerr("DirSink: dir_path must be an absolute or relative path. '%s'" % dir_path)
			return null
		return dir_path

	func _is_log_file(filename: String) -> bool:
		var prefix: String = "log_%s_" % _log_name
		if not filename.begins_with(prefix):
			return false
		if not filename.ends_with(".log"):
			return false
		return true

	func _update_dir_listing() -> void:
		_last_dir_listing = []
		var dir_list: DirAccess = DirAccess.open(_dir_path)
		if not dir_list:
			return
		dir_list.list_dir_begin()
		while true:
			var filename = dir_list.get_next()
			if filename == "":
				break
			if _is_log_file(filename):
				_last_dir_listing.append(filename)
		_last_dir_listing.sort_custom(Callable(self, "_compare_file_modification_time"))
		dir_list.list_dir_end()

	## Descending order: oldest last
	func _compare_file_modification_time(a: String, b: String) -> int:
		var a_path = _dir_path + "/" + a
		var b_path = _dir_path + "/" + b
		var a_time = FileAccess.get_modified_time(a_path)
		var b_time = FileAccess.get_modified_time(b_path)
		return a_time > b_time

	func _generate_filename() -> String:
		var filename = "log_%s_%s_%d.log" % [
			_log_name,
			Logger.format_time(Time.get_unix_time_from_system()),
			_session_id
		]
		return filename

	func _cleanup_old_files() -> void:
		var file_count = _last_dir_listing.size()
		if file_count <= _max_file_count:
			return
		var files_to_delete = file_count - _max_file_count
		for i in range(files_to_delete):
			var filename = _last_dir_listing[-1]
			var path = _dir_path + "/" + filename
			OS.move_to_trash(path)
			_last_dir_listing.remove_at(-1)

	func flush_buffer() -> void:
		if not _current_file:
			return
		_current_file.flush()

	func write(_details: Dictionary, message: String) -> void:
		if not _current_file:
			_open_new_file()
		if _current_file_size >= _max_file_size:
			_open_new_file()
		var log_message = message + "\n"
		# only approximate size utf8
		_current_file_size += log_message.length()
		_current_file.store_string(log_message)

	func _open_new_file() -> void:
		if _current_file:
			_current_file.close()

		_update_dir_listing()
		_cleanup_old_files()

		var filename = _generate_filename()
		var path = _dir_path + "/" + filename
		_current_file = FileAccess.open(path, FileAccess.WRITE)
		_current_file_size = 0

		if not _current_file:
			printerr("DirSink: Failed to open file '%s'." % path)
			return

## Left pads a string with a character to a given length.
static func pad_string(string: String, length: int, pad_char: String = " ") -> String:
	var pad_length = length - string.length()
	if pad_length <= 0:
		return string
	var pad = ""
	for i in range(pad_length):
		pad += pad_char
	return pad + string

class LocalLogger extends LogSink:
	var _sink: LogSink
	var _level: LogLevel
	var _tag: String

	func _init(tag: String, level: LogLevel = LogLevel.DEBUG, sink: LogSink = Logger._global_logger) -> void:
		_sink = sink
		_level = level
		_tag = tag

	static func _format_log_message(details: Dictionary, message: String) -> String:
		var tag = details["tag"]
		var time_unix = details["time_unix"]
		var level = details["level"]

		var time_str = Logger.format_time(time_unix)
		var level_str = Logger.get_short_level_name(level)
		var formatted_log_message = "[%s] [%s] [%s] %s" % [
			Logger.pad_string(tag, 15),
			time_str,
			level_str,
			message
		]
		return formatted_log_message

	# Write will not format the message, it will just pass it to the underlying sink.
	func write(details: Dictionary, message: String) -> void:
		_sink.write(details, message)

	func flush_buffer() -> void:
		_sink.flush_buffer()

	func get_tag() -> String:
		return _tag

	func set_level(level: LogLevel) -> void:
		_level = level

	func get_level() -> LogLevel:
		return _level

	func log(level: LogLevel, message: String) -> void:
		if level < _level:
			return
		var details: Dictionary = {
			"level": level,
			"tag": _tag,
			"time_unix": Time.get_unix_time_from_system(),
		}
		var formatted_log_message = _format_log_message(details, message)
		_sink.write(details, formatted_log_message)

	func debug(message: String) -> void:
		self.log(LogLevel.DEBUG, message)

	func info(message: String) -> void:
		self.log(LogLevel.INFO, message)

	func warning(message: String) -> void:
		self.log(LogLevel.WARNING, message)

	func error(message: String) -> void:
		self.log(LogLevel.ERROR, message)

var _global_broadcast_sink: BroadcastSink = BroadcastSink.new()
var _global_logger: LocalLogger = LocalLogger.new("Global", LogLevel.DEBUG, _global_broadcast_sink)

func debug(message: String) -> void:
	_global_logger.debug(message)

func info(message: String) -> void:
	_global_logger.info(message)

func warning(message: String) -> void:
	_global_logger.warning(message)

func error(message: String) -> void:
	_global_logger.error(message)

func set_level(level: LogLevel) -> void:
	_global_logger.set_level(level)

func get_level() -> LogLevel:
	return _global_logger.get_level()

func add_sink(sink: LogSink) -> void:
	_global_broadcast_sink.add_sink(sink)

func remove_sink(sink: LogSink) -> void:
	_global_broadcast_sink.remove_sink(sink)

func _flush_buffer() -> void:
	_global_logger.flush_buffer()

func _init():
	if Engine.is_editor_hint():
		add_sink(ConsoleSink.new())

func _exit_tree():
	_flush_buffer()

# https://github.com/KOBUGE-Games/godot-logger/blob/c7e0a3bb8957dfff8dfd3b2f7db511e66360ca1e/logger.gd#L256C1-L310C1
# BEGIN LICENSE MIT: LICENSE-godot-logger.md
# Copyright (c) 2016 KOBUGE Games
# Maps Error code to strings.
# This might eventually be supported out of the box in Godot,
# so we'll be able to drop this.
const ERROR_MESSAGES = {
	OK: "OK.",
	FAILED: "Generic error.",
	ERR_UNAVAILABLE: "Unavailable error.",
	ERR_UNCONFIGURED: "Unconfigured error.",
	ERR_UNAUTHORIZED: "Unauthorized error.",
	ERR_PARAMETER_RANGE_ERROR: "Parameter range error.",
	ERR_OUT_OF_MEMORY: "Out of memory (OOM) error.",
	ERR_FILE_NOT_FOUND: "File: Not found error.",
	ERR_FILE_BAD_DRIVE: "File: Bad drive error.",
	ERR_FILE_BAD_PATH: "File: Bad path error.",
	ERR_FILE_NO_PERMISSION: "File: No permission error.",
	ERR_FILE_ALREADY_IN_USE: "File: Already in use error.",
	ERR_FILE_CANT_OPEN: "File: Can't open error.",
	ERR_FILE_CANT_WRITE: "File: Can't write error.",
	ERR_FILE_CANT_READ: "File: Can't read error.",
	ERR_FILE_UNRECOGNIZED: "File: Unrecognized error.",
	ERR_FILE_CORRUPT: "File: Corrupt error.",
	ERR_FILE_MISSING_DEPENDENCIES: "File: Missing dependencies error.",
	ERR_FILE_EOF: "File: End of file (EOF) error.",
	ERR_CANT_OPEN: "Can't open error.",
	ERR_CANT_CREATE: "Can't create error.",
	ERR_QUERY_FAILED: "Query failed error.",
	ERR_ALREADY_IN_USE: "Already in use error.",
	ERR_LOCKED: "Locked error.",
	ERR_TIMEOUT: "Timeout error.",
	ERR_CANT_CONNECT: "Can't connect error.",
	ERR_CANT_RESOLVE: "Can't resolve error.",
	ERR_CONNECTION_ERROR: "Connection error.",
	ERR_CANT_ACQUIRE_RESOURCE: "Can't acquire resource error.",
	ERR_CANT_FORK: "Can't fork process error.",
	ERR_INVALID_DATA: "Invalid data error.",
	ERR_INVALID_PARAMETER: "Invalid parameter error.",
	ERR_ALREADY_EXISTS: "Already exists error.",
	ERR_DOES_NOT_EXIST: "Does not exist error.",
	ERR_DATABASE_CANT_READ: "Database: Read error.",
	ERR_DATABASE_CANT_WRITE: "Database: Write error.",
	ERR_COMPILATION_FAILED: "Compilation failed error.",
	ERR_METHOD_NOT_FOUND: "Method not found error.",
	ERR_LINK_FAILED: "Linking failed error.",
	ERR_SCRIPT_FAILED: "Script failed error.",
	ERR_CYCLIC_LINK: "Cycling link (import cycle) error.",
	ERR_INVALID_DECLARATION: "Invalid declaration error.",
	ERR_DUPLICATE_SYMBOL: "Duplicate symbol error.",
	ERR_PARSE_ERROR: "Parse error.",
	ERR_BUSY: "Busy error.",
	ERR_SKIP: "Skip error.",
	ERR_HELP: "Help error.",
	ERR_BUG: "Bug error.",
	ERR_PRINTER_ON_FIRE: "Printer on fire error.",
}
# END LICENSE MIT: LICENSE-godot-logger.md

func format_error(error: int) -> String:
	if ERROR_MESSAGES.has(error):
		return ERROR_MESSAGES[error]
	return "Unknown error (%d)." % error
