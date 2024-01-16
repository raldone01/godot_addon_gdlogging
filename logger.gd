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

## Returns the full name of a log level.
static func format_log_level_name(p_level: LogLevel) -> String:
	return LEVEL_NAMES[p_level]

const LEVEL_NAMES_SHORT = [
	"TRC",
	"DBG",
	"INF",
	"WRN",
	"ERR",
]

## Returns a three letter abbreviation of a log level.
static func format_log_level_name_short(p_level: LogLevel) -> String:
	return LEVEL_NAMES_SHORT[p_level]

## Returns a three letter abbreviation of a month.
static func format_month_short(p_month: int) -> String:
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
	return month_names[p_month - 1]

## Formats the session id number to a string truncated to 4 digits.
static func format_session_id(p_session_id: int)	-> String:
	return "%04d" % p_session_id

## Formats a unix timestamp to a string.
## The default formatter uses this format.
static func format_time_default(p_unix_time: float) -> String:
	var time := Time.get_datetime_dict_from_unix_time(p_unix_time)
	var time_str := "%02d/%s/%02d %02d:%02d:%02d" % [
		time["year"] % 100,
		format_month_short(time["month"]),
		time["day"],
		time["hour"],
		time["minute"],
		time["second"],
	]
	return time_str

## Formats a unix timestamp to a string.
## The [DirSink] uses this format.
static func format_time_default_for_filename(p_unix_time: float) -> String:
	var time := Time.get_datetime_dict_from_unix_time(p_unix_time)
	var time_str := "%04d-%s-%02d_%02dH-%02dM-%02dS" % [
		time["year"],
		format_month_short(time["month"]),
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
	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		Log._logger_direct_console.warning("LogSink: write_bulks() not implemented.")
	## Flushes the buffer of the sink if it has one.
	func flush_buffer() -> void:
		Log._logger_direct_console.warning("LogSink: flush_buffer() not implemented.")
	## Cleans up resources used by the sink.
	func close() -> void:
		pass

class FilteringSink extends LogSink:
	var _sink: LogSink
	var _level: LogLevel

	func _init(p_sink: LogSink, p_level: LogLevel) -> void:
		_sink = p_sink
		_level = p_level

	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		var filtered_log_records: Array[Dictionary] = []
		var filtered_formatted_messages := PackedStringArray()
		for i in range(p_log_records.size()):
			var log_record := p_log_records[i]
			var formatted_message := p_formatted_messages[i]
			var level: LogLevel = log_record["level"]
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
	var _sinks: Array[LogSink] = []

	func add_sink(p_sink: LogSink) -> void:
		_sinks.append(p_sink)

	func remove_sink(p_sink: LogSink) -> void:
		_sinks.erase(p_sink)

	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		for sink in _sinks:
			sink.write_bulks(p_log_records, p_formatted_messages)

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
	var _buffer_formatted_messages := PackedStringArray()
	var _buffer_size: int = 0
	var _last_buffer_write_out_time_usec: int = 0

	# At most 1 second between buffer flushes
	var _buffer_flush_interval_usec: int = 1000 * 1000 * 1

	## Creates a new BufferedSink.
	##
	## [param sink]: The sink to write to.
	## [param buffer_size]: The size of the buffer. If 0, the buffer will be disabled.
	##
	## The buffer size is the number of messages that will be buffered before being flushed to the sink.
	func _init(p_sink: LogSink, p_buffer_size: int = 42) -> void:
		if p_buffer_size < 0:
			p_buffer_size = 0
			Log._logger_direct_console.warning("BufferedSink: Buffer size must be equal or greater than 0.")
		_buffer_size = p_buffer_size
		_sink = p_sink

	func _write_bulks_buffered() -> void:
		_sink.write_bulks(_buffer_log_records, _buffer_formatted_messages)
		_buffer_log_records.clear()
		_buffer_formatted_messages.clear()
		_last_buffer_write_out_time_usec = Time.get_ticks_usec()

	func flush_buffer() -> void:
		_write_bulks_buffered()
		_sink.flush_buffer()

	## Set to 0 to disable interval flushing.
	func set_buffer_flush_interval_msec(p_buffer_flush_interval_msec: int) -> void:
		_buffer_flush_interval_usec = p_buffer_flush_interval_msec * 1000

	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		if _buffer_size == 0:
			_sink.write_bulks(p_log_records, p_formatted_messages)
			return
		_buffer_log_records.append_array(p_log_records)
		_buffer_formatted_messages.append_array(p_formatted_messages)
		var max_wait_exceeded := _buffer_flush_interval_usec != 0 and Time.get_ticks_usec() - _last_buffer_write_out_time_usec > _buffer_flush_interval_usec
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

	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		for i in range(p_formatted_messages.size()):
			var log_record := p_log_records[i]
			var formatted_message := p_formatted_messages[i]
			var level: LogLevel = log_record["level"]
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

	## Can't use PackableStringArray because `sort_custom` is not implemented.
	var _io_thread_last_dir_listing: Array[String] = []

	var _io_thread_current_file: FileAccess
	var _io_thread_current_file_size: int
	var _io_thread_file_count: int = 0

	static var _last_session_id: int = randi() % 1000 + roundi(Time.get_unix_time_from_system() * 1000) % 1000
	var _session_id: int = _last_session_id + 1

	var _io_thread: Thread
	var _io_thread_formatted_messages := PackedStringArray()
	var _io_thread_log_lock := Mutex.new()
	var _io_thread_work_semaphore := Semaphore.new()
	var _io_thread_exit := false
	var _io_thread_flush_buffer := false

	func _init(p_log_name: String, p_dir_path: String, p_max_file_size: int = 4042, p_max_file_count: int = 10) -> void:
		_log_name = p_log_name
		if p_dir_path.begins_with("user://") or p_dir_path.begins_with("res://"):
			p_dir_path = ProjectSettings.globalize_path(p_dir_path)
		if _is_dir_valid(p_dir_path):
			_dir_path = p_dir_path
		self._max_file_size = p_max_file_size
		self._max_file_count = p_max_file_count

		_io_thread = Thread.new()
		_io_thread.start(self._io_thread_main, Thread.PRIORITY_LOW)

	func _is_dir_valid(p_dir_path: String) -> bool:
		if not (p_dir_path.is_absolute_path() or p_dir_path.is_relative_path()):
			Log._logger_direct_console.error("DirSink: p_dir_path must be an absolute or relative path. '%s'" % p_dir_path)
			return false
		var dir := DirAccess.open(".")
		dir.make_dir_recursive(p_dir_path)
		if not dir.dir_exists(p_dir_path):
			Log._logger_direct_console.error("DirSink: p_dir_path does not exist. '%s'" % p_dir_path)
			return false
		return true

	func _is_log_file(p_filename: String) -> bool:
		var prefix := "log_%s_" % _log_name
		if not p_filename.begins_with(prefix):
			return false
		if not p_filename.ends_with(".log"):
			return false
		return true

	func _io_thread_update_dir_listing() -> void:
		_io_thread_last_dir_listing.clear()
		var dir_list := DirAccess.open(_dir_path)
		if not dir_list:
			return
		dir_list.list_dir_begin()
		while true:
			var filename := dir_list.get_next()
			if filename == "":
				break
			if _is_log_file(filename):
				_io_thread_last_dir_listing.append(filename)
		_io_thread_last_dir_listing.sort_custom(self._compare_file_modification_time)
		dir_list.list_dir_end()

	## Descending order: oldest last
	func _compare_file_modification_time(p_filename_a: String, p_filename_b: String) -> int:
		var a_path := _dir_path + "/" + p_filename_a
		var b_path := _dir_path + "/" + p_filename_b
		var a_time := FileAccess.get_modified_time(a_path)
		var b_time := FileAccess.get_modified_time(b_path)
		return a_time > b_time

	func _io_thread_generate_filename() -> String:
		var filename := "log_%s_%s_%d_%d.log" % [
			_log_name,
			Log.format_time_default_for_filename(Time.get_unix_time_from_system()),
			_session_id,
			_io_thread_file_count
		]
		filename = filename.replace(" ", "_").replace("/", "-").replace(":", "-")
		return filename

	func _io_thread_cleanup_old_files() -> void:
		var last_dir_listing := _io_thread_last_dir_listing
		var file_count := last_dir_listing.size()
		if file_count <= _max_file_count:
			return
		var files_to_delete := file_count - _max_file_count
		for i in range(files_to_delete):
			var filename := last_dir_listing[-1]
			var path := _dir_path + "/" + filename
			# OS.move_to_trash(path) # completely blocks the main thread
			var dir := DirAccess.open(".")
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

	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		if _io_thread_log_lock.try_lock():
			_io_thread_formatted_messages.append_array(p_formatted_messages)
			_io_thread_log_lock.unlock()
			_io_thread_work_semaphore.post()

	func _io_thread_open_new_file() -> void:
		if not _dir_path:
			return

		if _io_thread_current_file:
			_io_thread_current_file.close()

		_io_thread_update_dir_listing()
		_io_thread_cleanup_old_files()

		var filename := _io_thread_generate_filename()
		var path := _dir_path + "/" + filename
		_io_thread_current_file = FileAccess.open(path, FileAccess.WRITE)
		_io_thread_current_file_size = 0

		if not _io_thread_current_file:
			Log._logger_direct_console.error("DirSink: Failed to open new log file '%s'." % path)
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
	var _formatted_messages := PackedStringArray()
	var _log_records: Array[Dictionary] = []

	func _init(p_max_lines: int = 100) -> void:
		_max_lines = p_max_lines

	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		_formatted_messages.append_array(p_formatted_messages)
		_log_records.append_array(p_log_records)
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

class FormattingSink extends LogSink:
	var _sink: LogSink
	var _log_record_formatter: LogRecordFormatter

	func _init(p_sink: LogSink, p_log_record_formatter: LogRecordFormatter) -> void:
		_sink = p_sink
		_log_record_formatter = p_log_record_formatter

	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		var formatted_messages := PackedStringArray()
		for i in range(p_log_records.size()):
			var log_record := p_log_records[i]
			var formatted_message := _log_record_formatter.format(log_record)
			formatted_messages.append(formatted_message)
		_sink.write_bulks(p_log_records, formatted_messages)

	func flush_buffer() -> void:
		_sink.flush_buffer()

	func close() -> void:
		flush_buffer()
		_sink.close()

## Left pads a string with a character to a given length.
static func pad_string(p_string: String, p_length: int, p_pad_char: String = " ") -> String:
	var pad_length := p_length - p_string.length()
	if pad_length <= 0:
		return p_string
	var pad := ""
	for i in range(pad_length):
		pad += p_pad_char
	return pad + p_string

class LogRecordFormatter:
	func format(p_log_record: Dictionary) -> String:
		var tag: String = p_log_record["tag"]
		var time_unix: float = p_log_record["time_unix"]
		var level: LogLevel = p_log_record["level"]
		var unformatted_message: String = p_log_record["unformatted_message"]

		var time_str := Log.format_time_default(time_unix)
		var level_str := Log.format_log_level_name_short(level)
		var formatted_message := "[%s] [%s] [%s] %s" % [
			time_str,
			Log.pad_string(tag, 15),
			level_str,
			unformatted_message
		]
		if p_log_record.has("stack"):
			var stack: Array[Dictionary] = p_log_record["stack"]
			for frame in stack:
				var source: String = frame["source"]
				var line: String = frame["line"]
				var function: String = frame["function"]
				formatted_message += "\n\tAt: %s:%d:%s()" % [
					source,
					line,
					function
				]
		return formatted_message

class Logger extends LogSink:
	var _tag: String
	var _log_record_formatter: LogRecordFormatter
	var _level: LogLevel
	var _sink: LogSink

	func _init(
		p_tag: String,
		p_level: LogLevel = LogLevel.TRACE,
		p_log_record_formatter: LogRecordFormatter = Log._global_logger._log_record_formatter,
		p_sink: LogSink = Log._global_logger
	) -> void:
		_tag = p_tag
		_log_record_formatter = p_log_record_formatter
		_level = p_level
		_sink = p_sink

	## Write will not format the message, it will just pass it to the underlying sink.
	func write_bulks(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray) -> void:
		_sink.write_bulks(p_log_records, p_formatted_messages)

	func flush_buffer() -> void:
		_sink.flush_buffer()

	func get_tag() -> String:
		return _tag

	func set_level(p_level: LogLevel) -> void:
		_level = p_level

	func get_level() -> LogLevel:
		return _level

	func set_log_record_formatter(p_log_record_formatter: LogRecordFormatter) -> void:
		_log_record_formatter = p_log_record_formatter

	func log(p_level: LogLevel, p_message: String, p_log_record: Dictionary = {}) -> void:
		if p_level < _level:
			return
		p_log_record["level"] = p_level
		p_log_record["tag"] = _tag
		p_log_record["time_unix"] = Time.get_unix_time_from_system()
		p_log_record["unformatted_message"] = p_message
		var formatted_message := _log_record_formatter.format(p_log_record)
		_sink.write_bulks([p_log_record], [formatted_message])

	func trace(p_message: String, p_stack_depth: int = 1, p_stack_hint: int = 1) -> void:
		var log_record := {}
		if OS.is_debug_build():
			var stack: Array[Dictionary] = get_stack()
			var stack_slice: Array[Dictionary] = stack.slice(p_stack_hint, p_stack_depth + p_stack_hint)
			log_record["stack"] = stack_slice
		self.log(LogLevel.TRACE, p_message, log_record)

	func debug(p_message: String) -> void:
		self.log(LogLevel.DEBUG, p_message)

	func info(p_message: String) -> void:
		self.log(LogLevel.INFO, p_message)

	func warning(p_message: String) -> void:
		self.log(LogLevel.WARNING, p_message)

	func error(p_message: String) -> void:
		self.log(LogLevel.ERROR, p_message)

	func close() -> void:
		_sink.close()

class LogTimer:
	var _start_time_usec: int
	var _end_time_usec: int

	var _threshold_msec: int = 0

	var _logger: Logger
	var _message: String
	var _level: LogLevel = LogLevel.INFO

	func _init(p_message: String, p_threshold_msec: int = 0, p_logger: Logger = Log._global_logger) -> void:
		_logger = p_logger
		_message = p_message
		_threshold_msec = p_threshold_msec
		_start_time_usec = Time.get_ticks_usec()

	func set_level(p_level: LogLevel) -> void:
		_level = p_level

	func set_threshold_msec(p_threshold_msec: int) -> void:
		_threshold_msec = p_threshold_msec

	func start() -> void:
		_start_time_usec = Time.get_ticks_usec()

	func stop() -> void:
		_end_time_usec = Time.get_ticks_usec()
		var elapsed_time_usec := _end_time_usec - _start_time_usec
		var elapsed_time_sec := elapsed_time_usec / 1000000.0

		if _threshold_msec == 0:
			_logger.log(_level, "%s took %f seconds." % [_message, elapsed_time_sec])
			return

		if _threshold_msec < elapsed_time_usec / 1000:
			_logger.log(_level, "%s exceeded threshold of %d msec: took %f seconds." % [_message, _threshold_msec, elapsed_time_sec])

var _global_broadcast_sink: BroadcastSink
var _global_logger: Logger
var _logger_direct_console: Logger

func _init() -> void:
	_global_broadcast_sink = BroadcastSink.new()
	var log_formatter := LogRecordFormatter.new()
	_global_logger = Logger.new("Global", LogLevel.TRACE, log_formatter, _global_broadcast_sink)
	_logger_direct_console = Logger.new("gdlogging", LogLevel.TRACE, log_formatter, ConsoleSink.new())
	if Engine.is_editor_hint():
		add_sink(ConsoleSink.new())

func _exit_tree() -> void:
	flush_buffer()
	_global_logger.close()

func trace(p_message: String, p_stack_depth: int = 1, p_stack_hint: int = 2) -> void:
	_global_logger.trace(p_message, p_stack_depth, p_stack_hint)

func debug(p_message: String) -> void:
	_global_logger.debug(p_message)

func info(p_message: String) -> void:
	_global_logger.info(p_message)

func warning(p_message: String) -> void:
	_global_logger.warning(p_message)

func error(p_message: String) -> void:
	_global_logger.error(p_message)

func set_level(p_level: LogLevel) -> void:
	_global_logger.set_level(p_level)

func get_level() -> LogLevel:
	return _global_logger.get_level()

func set_log_record_formatter(p_log_record_formatter: LogRecordFormatter) -> void:
	_global_logger.set_log_record_formatter(p_log_record_formatter)

func add_sink(p_sink: LogSink) -> void:
	_global_broadcast_sink.add_sink(p_sink)

func remove_sink(p_sink: LogSink) -> void:
	_global_broadcast_sink.remove_sink(p_sink)

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

static func format_error(p_error: int) -> String:
	if ERROR_MESSAGES.has(p_error):
		return ERROR_MESSAGES[error]
	return "Unknown p_error (%d)." % p_error
