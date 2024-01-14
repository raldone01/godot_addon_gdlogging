# Copyright (c) 2024 The gdlogging Contributors
# Inspired by https://github.com/KOBUGE-Games/godot-logger/blob/master/logger.gd
@tool
extends Node

enum LogLevel {
	TRACE = 0,
	DEBUG,
	INFO,
	WARNING,
	ERROR,
	MAX,
}

const TRACE = LogLevel.TRACE
const DEBUG = LogLevel.DEBUG
const INFO = LogLevel.INFO
const WARNING = LogLevel.WARNING
const ERROR = LogLevel.ERROR

const LEVEL_NAMES = [
	"TRACE",
	"DEBUG",
	"INFO",
	"WARNING",
	"ERROR",
]

func get_level_name(level: LogLevel) -> String:
	return LEVEL_NAMES[level]

const SHORT_LEVEL_NAMES = [
	"TRC",
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
	var time_str = "%02d/%s/%02d %02d:%02d:%02d" % [
		time["year"] % 100,
		format_month(time["month"]),
		time["day"],
		time["hour"],
		time["minute"],
		time["second"],
	]
	return time_str

static func format_time_for_filename(unix_time: float) -> String:
	var time: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time)
	var time_str = "%04d-%s-%02d_%02dH-%02dM-%02dS" % [
		time["year"],
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
	## Write many log records to the sink
	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		printerr("LogSink: write_bulks() not implemented.")
	## Flushes the buffer of the sink if it has one.
	func flush_buffer() -> void:
		printerr("LogSink: flush_buffer() not implemented.")
	## Cleans up resources used by the sink.
	func close() -> void:
		pass

class FilteringSink extends LogSink:
	var _sink: LogSink
	var _level: LogLevel

	func _init(sink: LogSink, level: LogLevel) -> void:
		_sink = sink
		_level = level

	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		var filtered_log_records: Array[Dictionary] = []
		var filtered_formatted_messages: PackedStringArray = PackedStringArray()
		for i in range(log_records.size()):
			var log_record = log_records[i]
			var formatted_message = formatted_messages[i]
			var level = log_record["level"]
			if level >= _level:
				filtered_log_records.append(log_record)
				filtered_formatted_messages.append(formatted_message)
		_sink.write_bulks(filtered_log_records, filtered_formatted_messages)

	func flush_buffer() -> void:
		_sink.flush_buffer()

	func close() -> void:
		flush_buffer()
		_sink.close()

class BroadcastSink extends LogSink:
	var _sinks: Array = []

	func add_sink(sink: LogSink) -> void:
		_sinks.append(sink)

	func remove_sink(sink: LogSink) -> void:
		_sinks.erase(sink)

	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		for sink in _sinks:
			sink.write_bulks(log_records, formatted_messages)

	func flush_buffer() -> void:
		for sink in _sinks:
			sink.flush_buffer()

	func close() -> void:
		flush_buffer()
		for sink in _sinks:
			sink.close()

class BufferedSink extends LogSink:
	var _sink: LogSink

	var _buffer_log_records: Array[Dictionary] = []
	var _buffer_formatted_messages: PackedStringArray = PackedStringArray()
	var _buffer_size = 0
	var _last_buffer_write_out_time_usec = 0

	# At most 1 second between buffer flushes
	var _buffer_flush_interval_usec = 1000 * 1000 * 1

	## Creates a new BufferedSink.
	##
	## [param sink]: The sink to write to.
	## [param buffer_size]: The size of the buffer. If 0, the buffer will be disabled.
	##
	## The buffer size is the number of messages that will be buffered before being flushed to the sink.
	func _init(sink: LogSink, buffer_size: int = 42) -> void:
		if buffer_size < 0:
			buffer_size = 0
			printerr("BufferedSink: Buffer size must be equal or greater than 0.")
		_buffer_size = buffer_size
		_sink = sink

	func _write_bulks_buffered() -> void:
		_sink.write_bulks(_buffer_log_records, _buffer_formatted_messages)
		_buffer_log_records.clear()
		_buffer_formatted_messages.clear()
		_last_buffer_write_out_time_usec = Time.get_ticks_usec()

	func flush_buffer() -> void:
		_write_bulks_buffered()
		_sink.flush_buffer()

	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		if _buffer_size == 0:
			_sink.write_bulks(log_records, formatted_messages)
			return
		_buffer_log_records.append_array(log_records)
		_buffer_formatted_messages.append_array(formatted_messages)
		var max_wait_exceeded = Time.get_ticks_usec() - _last_buffer_write_out_time_usec > _buffer_flush_interval_usec
		if (_buffer_log_records.size() >= _buffer_size) \
			or max_wait_exceeded:
			_write_bulks_buffered()
			if max_wait_exceeded:
				# flush the underlying sink every second
				_sink.flush_buffer()

	func close() -> void:
		flush_buffer()
		_sink.close()

class ConsoleSink extends LogSink:

	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		for i in range(formatted_messages.size()):
			var log_record = log_records[i]
			var formatted_message = formatted_messages[i]
			var level = log_record["level"]
			if level <= LogLevel.INFO:
				print(formatted_message)
			else:
				printerr(formatted_message)

	func flush_buffer() -> void:
		pass

class DirSink extends LogSink:
	var _log_name: String
	var _dir_path: String
	var _max_file_size: int
	var _max_file_count: int

	var _io_thread_last_dir_listing: Array = []

	var _io_thread_current_file: FileAccess
	var _io_thread_current_file_size: int
	var _io_thread_file_count: int = 0

	static var _last_session_id: int = randi() % 1000 + roundi(Time.get_unix_time_from_system() * 1000) % 1000
	var _session_id: int = _last_session_id + 1

	var _io_thread: Thread
	var _io_thread_formatted_messages: PackedStringArray = PackedStringArray()
	var _io_thread_log_lock: Mutex = Mutex.new()
	var _io_thread_work_semaphore: Semaphore = Semaphore.new()
	var _io_thread_exit: bool = false
	var _io_thread_flush_buffer: bool = false

	func _init(log_name: String, dir_path: String, max_file_size: int = 4042, max_file_count: int = 10) -> void:
		_log_name = log_name
		if dir_path.begins_with("user://") or dir_path.begins_with("res://"):
			dir_path = ProjectSettings.globalize_path(dir_path)
		var dir_path_t = _validate_dir(dir_path)
		if dir_path_t:
			_dir_path = dir_path_t
		self._max_file_size = max_file_size
		self._max_file_count = max_file_count

		_io_thread = Thread.new()
		_io_thread.start(Callable(self, "_io_thread_main"), Thread.PRIORITY_LOW)

	func _validate_dir(dir_path: String) -> Variant:
		if not (dir_path.is_absolute_path() or dir_path.is_relative_path()):
			printerr("DirSink: dir_path must be an absolute or relative path. '%s'" % dir_path)
			return null
		var dir = DirAccess.open(".")
		dir.make_dir_recursive(dir_path)
		if not dir.dir_exists(dir_path):
			printerr("DirSink: dir_path does not exist. '%s'" % dir_path)
			return null
		return dir_path

	func _is_log_file(filename: String) -> bool:
		var prefix: String = "log_%s_" % _log_name
		if not filename.begins_with(prefix):
			return false
		if not filename.ends_with(".log"):
			return false
		return true

	func _io_thread_update_dir_listing() -> void:
		_io_thread_last_dir_listing = []
		var dir_list: DirAccess = DirAccess.open(_dir_path)
		if not dir_list:
			return
		dir_list.list_dir_begin()
		while true:
			var filename = dir_list.get_next()
			if filename == "":
				break
			if _is_log_file(filename):
				_io_thread_last_dir_listing.append(filename)
		_io_thread_last_dir_listing.sort_custom(Callable(self, "_compare_file_modification_time"))
		dir_list.list_dir_end()

	## Descending order: oldest last
	func _compare_file_modification_time(a: String, b: String) -> int:
		var a_path = _dir_path + "/" + a
		var b_path = _dir_path + "/" + b
		var a_time = FileAccess.get_modified_time(a_path)
		var b_time = FileAccess.get_modified_time(b_path)
		return a_time > b_time

	func _io_thread_generate_filename() -> String:
		var filename = "log_%s_%s_%d_%d.log" % [
			_log_name,
			Log.format_time_for_filename(Time.get_unix_time_from_system()),
			_session_id,
			_io_thread_file_count
		]
		filename = filename.replace(" ", "_").replace("/", "-").replace(":", "-")
		return filename

	func _io_thread_cleanup_old_files() -> void:
		var last_dir_listing = _io_thread_last_dir_listing
		var file_count = last_dir_listing.size()
		if file_count <= _max_file_count:
			return
		var files_to_delete = file_count - _max_file_count
		for i in range(files_to_delete):
			var filename = last_dir_listing[-1]
			var path = _dir_path + "/" + filename
			# OS.move_to_trash(path) # completely blocks the main thread
			var dir = DirAccess.open(".")
			dir.remove(path)
			last_dir_listing.remove_at(last_dir_listing.size() - 1)

	func flush_buffer() -> void:
		_io_thread_flush_buffer = true
		_io_thread_work_semaphore.post()

	func _io_thread_flush_file() -> void:
		# flush file
		if _io_thread_flush_buffer:
			_io_thread_flush_buffer = false
			if _io_thread_current_file:
				_io_thread_current_file.flush()

	func _io_thread_main() -> void:
		while not _io_thread_exit:
			_io_thread_work_semaphore.wait()
			_io_thread_log_lock.lock()
			var log_block: String
			if _io_thread_formatted_messages.size() > 0:
				log_block = "\n".join(_io_thread_formatted_messages) + "\n"
				_io_thread_formatted_messages.clear()
			else:
				log_block = ""
			_io_thread_log_lock.unlock()
			# write formatted message
			if not _io_thread_current_file:
				_io_thread_open_new_file()
			if _io_thread_current_file_size >= _max_file_size:
				_io_thread_open_new_file()
			# only approximate size utf8
			_io_thread_current_file_size += log_block.length()
			_io_thread_current_file.store_string(log_block)
			_io_thread_flush_file()
		# thread exit
		_io_thread_flush_file()
		if _io_thread_current_file:
			_io_thread_current_file.close()

	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		if _io_thread_log_lock.try_lock():
			_io_thread_formatted_messages.append_array(formatted_messages)
			_io_thread_log_lock.unlock()
			_io_thread_work_semaphore.post()

	func _io_thread_open_new_file() -> void:
		if not _dir_path:
			return

		if _io_thread_current_file:
			_io_thread_current_file.close()

		_io_thread_update_dir_listing()
		_io_thread_cleanup_old_files()

		var filename = _io_thread_generate_filename()
		var path = _dir_path + "/" + filename
		_io_thread_current_file = FileAccess.open(path, FileAccess.WRITE)
		_io_thread_current_file_size = 0

		if not _io_thread_current_file:
			printerr("DirSink: Failed to open new log file '%s'." % path)
			return
		_io_thread_file_count += 1

	func close() -> void:
		_io_thread_exit = true
		while _io_thread.is_alive():
			_io_thread_work_semaphore.post()
			OS.delay_msec(10)
		_io_thread.wait_to_finish()

class MemoryWindowSink extends LogSink:
	var _max_lines: int
	var _formatted_messages: Array = []
	var _log_records: Array = []

	func _init(max_lines: int = 100) -> void:
		_max_lines = max_lines

	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		_formatted_messages.append_array(formatted_messages)
		_log_records.append_array(log_records)
		while _formatted_messages.size() > _max_lines:
			_formatted_messages.remove_at(0)
			_log_records.remove_at(0)

	func flush_buffer() -> void:
		pass

	func get_buffer() -> Dictionary:
		return {
			"formatted_messages": _formatted_messages,
			"log_records": _log_records,
		}

## Left pads a string with a character to a given length.
static func pad_string(string: String, length: int, pad_char: String = " ") -> String:
	var pad_length = length - string.length()
	if pad_length <= 0:
		return string
	var pad = ""
	for i in range(pad_length):
		pad += pad_char
	return pad + string

class LogRecordFormatter:
	func format(log_record: Dictionary, raw_message: String) -> String:
		var tag = log_record["tag"]
		var time_unix = log_record["time_unix"]
		var level = log_record["level"]

		var time_str = Log.format_time(time_unix)
		var level_str = Log.get_short_level_name(level)
		var formatted_message = "[%s] [%s] [%s] %s" % [
			time_str,
			Log.pad_string(tag, 15),
			level_str,
			raw_message
		]
		if log_record.has("stack"):
			var stack: Array[Dictionary] = log_record["stack"]
			for frame in stack:
				var source = frame["source"]
				var line = frame["line"]
				var function = frame["function"]
				formatted_message += "\n\tAt: %s:%d:%s()" % [
					source,
					line,
					function
				]
		return formatted_message

class LocalLogger extends LogSink:
	var _tag: String
	var _log_record_formatter: LogRecordFormatter
	var _level: LogLevel
	var _sink: LogSink

	func _init(
		tag: String,
		level: LogLevel = LogLevel.TRACE,
		log_record_formatter: LogRecordFormatter = Log._global_logger._log_record_formatter,
		sink: LogSink = Log._global_logger
	) -> void:
		_tag = tag
		_log_record_formatter = log_record_formatter
		_level = level
		_sink = sink

	# Write will not format the message, it will just pass it to the underlying sink.
	func write_bulks(log_records: Array[Dictionary], formatted_messages: PackedStringArray) -> void:
		_sink.write_bulks(log_records, formatted_messages)

	func flush_buffer() -> void:
		_sink.flush_buffer()

	func get_tag() -> String:
		return _tag

	func set_level(level: LogLevel) -> void:
		_level = level

	func get_level() -> LogLevel:
		return _level

	func set_log_record_formatter(log_record_formatter: LogRecordFormatter) -> void:
		_log_record_formatter = log_record_formatter

	func log(level: LogLevel, message: String, log_record: Dictionary = {}) -> void:
		if level < _level:
			return
		log_record["level"] = level
		log_record["tag"] = _tag
		log_record["time_unix"] = Time.get_unix_time_from_system()
		log_record["unformatted_message"] = message
		var formatted_message = _log_record_formatter.format(log_record, message)
		_sink.write_bulks([log_record], [formatted_message])

	func trace(message: String, stack_depth: int = 1, stack_hint: int = 1) -> void:
		var log_record: Dictionary = {}
		if OS.is_debug_build():
			var stack: Array[Dictionary] = get_stack()
			var stack_slice = stack.slice(stack_hint, stack_depth + stack_hint)
			log_record["stack"] = stack_slice
		self.log(LogLevel.TRACE, message, log_record)

	func debug(message: String) -> void:
		self.log(LogLevel.DEBUG, message)

	func info(message: String) -> void:
		self.log(LogLevel.INFO, message)

	func warning(message: String) -> void:
		self.log(LogLevel.WARNING, message)

	func error(message: String) -> void:
		self.log(LogLevel.ERROR, message)

	func close() -> void:
		_sink.close()

class LogTimer:
	var _start_time_usec: int
	var _end_time_usec: int

	var _threshold_msec: int = 0

	var _logger: LocalLogger
	var _message: String
	var _level: LogLevel = LogLevel.INFO

	func _init(message: String, threshold_msec: int = 0, logger: LocalLogger = Log._global_logger) -> void:
		_logger = logger
		_message = message
		_threshold_msec = threshold_msec
		_start_time_usec = Time.get_ticks_usec()

	func set_level(level: LogLevel) -> void:
		_level = level

	func set_threshold_msec(threshold_msec: int) -> void:
		_threshold_msec = threshold_msec

	func start() -> void:
		_start_time_usec = Time.get_ticks_usec()

	func stop() -> void:
		_end_time_usec = Time.get_ticks_usec()
		var elapsed_time_usec = _end_time_usec - _start_time_usec
		var elapsed_time_sec = elapsed_time_usec / 1000000.0

		if _threshold_msec == 0:
			_logger.log(_level, "%s took %f seconds." % [_message, elapsed_time_sec])
			return

		if _threshold_msec < elapsed_time_usec / 1000:
			_logger.log(_level, "%s exceeded threshold of %d msec: took %f seconds." % [_message, _threshold_msec, elapsed_time_sec])

var _global_broadcast_sink: BroadcastSink
var _global_logger: LocalLogger

func _init() -> void:
	_global_broadcast_sink = BroadcastSink.new()
	_global_logger = LocalLogger.new("Global", LogLevel.TRACE, LogRecordFormatter.new(), _global_broadcast_sink)
	if Engine.is_editor_hint():
		add_sink(ConsoleSink.new())

func _exit_tree() -> void:
	flush_buffer()
	_global_logger.close()

func trace(message: String, stack_depth: int = 1, stack_hint: int = 2) -> void:
	_global_logger.trace(message, stack_depth, stack_hint)

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

func set_log_record_formatter(log_record_formatter: LogRecordFormatter) -> void:
	_global_logger.set_log_record_formatter(log_record_formatter)

func add_sink(sink: LogSink) -> void:
	_global_broadcast_sink.add_sink(sink)

func remove_sink(sink: LogSink) -> void:
	_global_broadcast_sink.remove_sink(sink)

func flush_buffer() -> void:
	_global_logger.flush_buffer()

# https://github.com/KOBUGE-Games/godot-logger/blob/c7e0a3bb8957dfff8dfd3b2f7db511e66360ca1e/logger.gd#L256C1-L310C1
# BEGIN LICENSE MIT: `LICENSE-godot-logger.md`
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
