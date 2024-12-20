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
static func format_session_id(p_session_id: int) -> String:
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

## Base class to be inherited by log pipes.
## The messages have not yet been formatted.
class LogPipe extends RefCounted:
	## Write many log records to the pipe
	func write_bulks(p_log_records: Array[Dictionary]) -> void:
		Log._logger_direct_console.warning("LogPipe: write_bulks() not implemented.")
	## Flushes the buffer of the pipe if it has one.
	func flush_buffer() -> void:
		Log._logger_direct_console.warning("LogPipe: flush_buffer() not implemented.")
	## Cleans up resources used by the pipe.
	func close() -> void:
		pass

class FilteringPipe extends LogPipe:
	var _pipe: LogPipe
	var _level: LogLevel

	func _init(p_pipe: LogPipe, p_level: LogLevel) -> void:
		_pipe = p_pipe
		_level = p_level

	func write_bulks(p_log_records: Array[Dictionary]) -> void:
		var filtered_log_records: Array[Dictionary] = []
		for i in range(p_log_records.size()):
			var log_record := p_log_records[i]
			var level: LogLevel = log_record["level"]
			if level >= _level:
				filtered_log_records.append(log_record)
		_pipe.write_bulks(filtered_log_records)

	func flush_buffer() -> void:
		_pipe.flush_buffer()

	func close() -> void:
		flush_buffer()
		_pipe.close()

class BroadcastPipe extends LogPipe:
	var _pipes: Array[LogPipe] = []

	func add_pipe(p_pipe: LogPipe) -> void:
		_pipes.append(p_pipe)

	func remove_pipe(p_pipe: LogPipe) -> void:
		_pipes.erase(p_pipe)

	func write_bulks(p_log_records: Array[Dictionary]) -> void:
		for pipe in _pipes:
			pipe.write_bulks(p_log_records)

	func flush_buffer() -> void:
		for pipe in _pipes:
			pipe.flush_buffer()

	func close() -> void:
		flush_buffer()
		for pipe in _pipes:
			pipe.close()

class BufferedPipe extends LogPipe:
	var _pipe: LogPipe

	var _buffer_log_records: Array[Dictionary] = []
	var _buffer_size: int = 0
	var _last_buffer_write_out_time_usec: int = 0

	# At most 1 second between buffer flushes
	var _buffer_flush_interval_usec: int = 1000 * 1000 * 1

	## Creates a new BufferedPipe.
	##
	## [param p_pipe]: The pipe to write to.
	## [param p_buffer_size]: The size of the buffer. If 0, the buffer will be disabled.
	##
	## The buffer size is the number of messages that will be buffered before being flushed to the pipe.
	func _init(p_pipe: LogPipe, p_buffer_size: int = 42) -> void:
		if p_buffer_size < 0:
			p_buffer_size = 0
			Log._logger_direct_console.warning("BufferedPipe: Buffer size must be equal or greater than 0.")
		_buffer_size = p_buffer_size
		_pipe = p_pipe

	func _write_bulks_buffered() -> void:
		_pipe.write_bulks(_buffer_log_records)
		_buffer_log_records.clear()
		_last_buffer_write_out_time_usec = Time.get_ticks_usec()

	func flush_buffer() -> void:
		_write_bulks_buffered()
		_pipe.flush_buffer()

	## Set to 0 to disable interval flushing.
	func set_buffer_flush_interval_msec(p_buffer_flush_interval_msec: int) -> void:
		_buffer_flush_interval_usec = p_buffer_flush_interval_msec * 1000

	func write_bulks(p_log_records: Array[Dictionary]) -> void:
		if _buffer_size == 0:
			_pipe.write_bulks(p_log_records)
			return
		_buffer_log_records.append_array(p_log_records)
		var max_wait_exceeded := _buffer_flush_interval_usec != 0 and Time.get_ticks_usec() - _last_buffer_write_out_time_usec > _buffer_flush_interval_usec
		if (_buffer_log_records.size() >= _buffer_size) \
			or max_wait_exceeded:
			_write_bulks_buffered()
			if max_wait_exceeded:
				# flush the underlying pipe every second
				_pipe.flush_buffer()

	func close() -> void:
		flush_buffer()
		_pipe.close()

class LogSink extends LogPipe:
	## Sets the log record formatter.
	func set_log_record_formatter(p_log_record_formatter: LogRecordFormatter) -> void:
		Log._logger_direct_console.warning("LogSink: set_log_record_formatter() not implemented.")
	## Gets the log record formatter.
	func get_log_record_formatter() -> LogRecordFormatter:
		Log._logger_direct_console.warning("LogSink: get_log_record_formatter() not implemented.")
		return null

class ThreadedLogSink extends LogSink:
	var _io_thread: Thread

	var _log_record_formatter: LogRecordFormatter
	var _sink_capabilties: Dictionary

	var _work_semaphore := Semaphore.new()
	var _io_thread_exit := false
	var _io_thread_flush_buffer := false

	var _log_records_inbox_lock := Mutex.new()
	var _log_records_inbox: Array[Dictionary] = []

	var _io_thread_log_records: Array[Dictionary] = []
	var _io_thread_formatted_logs := PackedStringArray()

	func _init(
		p_sink_capabilties: Dictionary = {},
		p_log_record_formatter: LogRecordFormatter = Log._global_log_record_formatter,
		p_thread_priority: int = Thread.PRIORITY_LOW
	) -> void:
		_log_record_formatter = p_log_record_formatter
		_sink_capabilties = p_sink_capabilties

		_io_thread = Thread.new()
		_io_thread.start(self._io_thread_main, p_thread_priority)

	func write_bulks(p_log_records: Array[Dictionary]) -> void:
		_log_records_inbox_lock.lock()
		_log_records_inbox.append_array(p_log_records)
		_log_records_inbox_lock.unlock()
		_work_semaphore.post()

	func flush_buffer() -> void:
		_io_thread_flush_buffer = true
		_work_semaphore.post()

	## This function should be implemented by the derived class to actually output the formatted log messages.
	func _io_thread_output_logs(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray, flush_buffer: bool) -> void:
		Log._logger_direct_console.warning("ThreadedLogSink: _io_thread_output_logs() not implemented.")

	## This function should be implemented by the derived class to handle the exit of the sink.
	func _io_thread_exit_sink() -> void:
		pass

	func _io_thread_main() -> void:
		while not _io_thread_exit:
			_work_semaphore.wait()
			_log_records_inbox_lock.lock()
			_io_thread_log_records.assign(_log_records_inbox)
			_log_records_inbox.clear()
			_log_records_inbox_lock.unlock()

			_io_thread_formatted_logs.clear()
			for log_record in _io_thread_log_records:
				var formatted_message := _log_record_formatter.format(log_record, _sink_capabilties)
				_io_thread_formatted_logs.append(formatted_message)

			var flush_buffer := _io_thread_flush_buffer
			if flush_buffer:
				_io_thread_flush_buffer = false
			_io_thread_output_logs(_io_thread_log_records, _io_thread_formatted_logs, flush_buffer)

	  # thread exit

		# flush
		_io_thread_output_logs([], [], true)
		# close
		_io_thread_exit_sink()

	func close() -> void:
		_io_thread_exit = true
		while _io_thread.is_alive():
			_work_semaphore.post()
			OS.delay_msec(10)
		_io_thread.wait_to_finish()

class ConsoleSink extends ThreadedLogSink:

	func _init(p_log_record_formatter: LogRecordFormatter = null) -> void:
		var sink_capabilities := {}

		if not p_log_record_formatter:
			p_log_record_formatter = Log._global_log_record_formatter

		super._init(sink_capabilities, p_log_record_formatter)

	func _io_thread_output_logs(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray, flush_buffer: bool) -> void:
		for i in range(p_formatted_messages.size()):
			var log_record := p_log_records[i]
			var formatted_message := p_formatted_messages[i]
			var level: LogLevel = log_record["level"]

			if level <= LogLevel.INFO:
				print(formatted_message)
			else:
				printerr(formatted_message)

class ConsoleRichSink extends ThreadedLogSink:
	func _init() -> void:
		var sink_capabilities := {
			"bbcode": true,
		}
		super._init(sink_capabilities)

	func _io_thread_output_logs(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray, flush_buffer: bool) -> void:
		for formatted_message in p_formatted_messages:
			print_rich(formatted_message)

class DirSink extends ThreadedLogSink:
	var _log_name: String
	var _dir_path: String
	var _max_file_size: int
	var _max_file_count: int

	## Can't use PackableStringArray because `sort_custom` is not implemented.
	var _last_dir_listing: Array[String] = []

	var _current_file: FileAccess
	var _current_file_size: int
	var _file_count: int = 0

	static var _last_session_id: int = randi() % 1000 + roundi(Time.get_unix_time_from_system() * 1000) % 1000
	var _session_id: int = _last_session_id + 1

	func _init(p_log_name: String, p_dir_path: String, p_max_file_size: int = 4042, p_max_file_count: int = 10) -> void:
		_log_name = p_log_name
		if p_dir_path.begins_with("user://") or p_dir_path.begins_with("res://"):
			p_dir_path = ProjectSettings.globalize_path(p_dir_path)
		if _is_dir_valid(p_dir_path):
			_dir_path = p_dir_path
		self._max_file_size = p_max_file_size
		self._max_file_count = p_max_file_count

		var sink_capabilities := {}
		super._init(sink_capabilities)

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

	func _update_dir_listing() -> void:
		_last_dir_listing.clear()
		var dir_list := DirAccess.open(_dir_path)
		if not dir_list:
			return
		dir_list.list_dir_begin()
		while true:
			var filename := dir_list.get_next()
			if filename == "":
				break
			if _is_log_file(filename):
				_last_dir_listing.append(filename)
		_last_dir_listing.sort_custom(self._compare_file_modification_time)
		dir_list.list_dir_end()

	## Descending order: oldest last
	func _compare_file_modification_time(p_filename_a: String, p_filename_b: String) -> int:
		var a_path := _dir_path + "/" + p_filename_a
		var b_path := _dir_path + "/" + p_filename_b
		var a_time := FileAccess.get_modified_time(a_path)
		var b_time := FileAccess.get_modified_time(b_path)
		return a_time > b_time

	func _generate_filename() -> String:
		var filename := "log_%s_%s_%d_%d.log" % [
			_log_name,
			Log.format_time_default_for_filename(Time.get_unix_time_from_system()),
			_session_id,
			_file_count
		]
		filename = filename.replace(" ", "_").replace("/", "-").replace(":", "-")
		return filename

	func _cleanup_old_files() -> void:
		var last_dir_listing := _last_dir_listing
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

	func _flush_file() -> void:
		# flush file
		if _current_file:
			_current_file.flush()

	func _io_thread_output_logs(p_log_records: Array[Dictionary], p_formatted_messages: PackedStringArray, flush_buffer: bool) -> void:
		var log_block: String
		if p_formatted_messages.size() > 0:
			log_block = "\n".join(p_formatted_messages) + "\n"
		else:
			log_block = ""
		# write formatted message
		if (not _current_file) or (_current_file_size >= _max_file_size):
			_open_new_file()
		# only approximate size because of utf8
		_current_file_size += log_block.length()
		_current_file.store_string(log_block)
		if flush_buffer:
			_flush_file()

	func _io_thread_exit_sink() -> void:
		_flush_file()
		if _current_file:
			_current_file.close()

	func _open_new_file() -> void:
		if not _dir_path:
			return

		if _current_file:
			_current_file.close()

		_update_dir_listing()
		_cleanup_old_files()

		var filename := _generate_filename()
		var path := _dir_path + "/" + filename
		_current_file = FileAccess.open(path, FileAccess.WRITE)
		_current_file_size = 0

		if not _current_file:
			Log._logger_direct_console.error("DirSink: Failed to open new log file '%s'." % path)
			return
		_file_count += 1

class MemoryWindowSink extends LogSink:
	var _max_lines: int
	var _log_buffer_formatted := PackedStringArray()
	var _log_buffer_records: Array[Dictionary] = []
	var _capabilties := {}
	var _log_record_formatter: LogRecordFormatter

	func _init(p_max_lines: int = 100) -> void:
		_max_lines = p_max_lines
		_log_record_formatter = Log._global_log_record_formatter

	func set_log_record_formatter(p_log_record_formatter: LogRecordFormatter) -> void:
		_log_record_formatter = p_log_record_formatter

	func get_log_record_formatter() -> LogRecordFormatter:
		return _log_record_formatter

	func set_buffered_lines(p_max_lines: int) -> void:
		_max_lines = p_max_lines

	func get_buffered_lines() -> int:
		return _max_lines

	func set_bbcode_support(p_enable: bool) -> void:
		_capabilties["bbcode"] = p_enable

	func write_bulks(p_log_records: Array[Dictionary]) -> void:
		for log_record in p_log_records:
			var formatted_message := _log_record_formatter.format(log_record, _capabilties)
			_log_buffer_formatted.append(formatted_message)
		_log_buffer_records.append_array(p_log_records)
		while _log_buffer_formatted.size() > _max_lines:
			_log_buffer_formatted.remove_at(0)
			_log_buffer_records.remove_at(0)

	func flush_buffer() -> void:
		pass

	func get_buffer() -> Dictionary:
		return {
			"formatted_messages": _log_buffer_formatted,
			"log_records": _log_buffer_records,
		}

## Left pads a string with a character to a given length.
static func pad_string(p_string: String, p_length: int, p_pad_char: String = " ") -> String:
	var pad_length := p_length - p_string.length()
	if pad_length <= 0:
		return p_string
	var pad := ""
	for i in range(pad_length):
		pad += p_pad_char
	return pad + p_string

## SupportedBBColors:
## BLACK,
## RED,
## GREEN,
## YELLOW,
## BLUE,
## MAGENTA,
## PINK,
## CYAN,
## WHITE,
## ORANGE,
## GRAY,
## TRANSPARENT, (for bgcolor only)
class BBCodeFormatter extends RefCounted:
	var _do_format: bool

	func _init(p_do_format: bool = true) -> void:
		_do_format = p_do_format

	func set_formatting_enabled(p_enable: bool = true) -> void:
		_do_format = p_enable

	func get_formatting_enabled() -> bool:
		return _do_format

	func _color_generic(p_text: String, p_color: Color, p_color_type: String) -> String:
		if not _do_format:
			return p_text
		var color_string: String
		var unsupported_color := false
		match p_color:
			Color.BLACK:
				color_string = "black"
			Color.RED:
				color_string = "red"
			Color.GREEN:
				color_string = "green"
			Color.YELLOW:
				color_string = "yellow"
			Color.BLUE:
				color_string = "blue"
			Color.MAGENTA:
				color_string = "magenta"
			Color.PINK:
				color_string = "pink"
			Color.CYAN:
				color_string = "cyan"
			Color.WHITE:
				color_string = "white"
			Color.ORANGE:
				color_string = "orange"
			Color.GRAY:
				color_string = "gray"
			_:
				color_string = "unsupported color '%s'" % p_color
				unsupported_color = true
		var message := "[%s=%s]%s[/%s]" % [p_color_type, color_string, p_text, p_color_type]
		if unsupported_color:
			message = BBCodeFormatter.escape_bbcode(message)
			return "[color=pink]%s[/color]" % message
		return message

	func color_fg(p_text: String, p_color: Color) -> String:
		if not _do_format:
			return p_text
		return _color_generic(p_text, p_color, "color")
	func color_bg(p_text: String, p_color: Color) -> String:
		if not _do_format or p_color == Color.TRANSPARENT:
			return p_text
		return _color_generic(p_text, p_color, "bgcolor")
	func color(p_text: String, p_fg_color: Color, p_bg_color: Color) -> String:
		if not _do_format:
			return p_text
		return color_bg(color_fg(p_text, p_fg_color), p_bg_color)
	func bold(p_text: String) -> String:
		if not _do_format:
			return p_text
		return "[b]%s[/b]" % p_text
	func italic(p_text: String) -> String:
		if not _do_format:
			return p_text
		return "[i]%s[/i]" % p_text
	func strike(p_text: String) -> String:
		if not _do_format:
			return p_text
		return "[s]%s[/s]" % p_text
	func code(p_text: String) -> String:
		if not _do_format:
			return p_text
		return "[code]%s[/code]" % p_text
	func center(p_text: String) -> String:
		if not _do_format:
			return p_text
		return "[center]%s[/center]" % p_text
	func right(p_text: String) -> String:
		if not _do_format:
			return p_text
		return "[right]%s[/right]" % p_text
	func url(p_text: String, p_url: String) -> String:
		if not _do_format:
			return p_text
		return "[url=%s]%s[/url]" % [p_url, p_text]

	static func escape_bbcode(p_bbcode_text: String) -> String:
		# We only need to replace opening brackets to prevent tags from being parsed.
		return p_bbcode_text.replace("[", "[lb]")

class BBCodeBuilder extends RefCounted:
	var _bbcode_formatter := BBCodeFormatter.new()
	var _bbcode_text: PackedStringArray

	func _init(p_backing_array: PackedStringArray = PackedStringArray()) -> void:
		_bbcode_text = p_backing_array

	func set_formatting_enabled(p_enable: bool = true) -> void:
		_bbcode_formatter.set_formatting_enabled(p_enable)

	func get_formatting_enabled() -> bool:
		return _bbcode_formatter.get_formatting_enabled()

	func color_fg(p_text: String, p_color: Color) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.color_fg(p_text, p_color))
		return self

	func color_bg(p_text: String, p_color: Color) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.color_bg(p_text, p_color))
		return self

	func color(p_text: String, p_fg_color: Color, p_bg_color: Color) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.color(p_text, p_fg_color, p_bg_color))
		return self

	func bold(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.bold(p_text))
		return self

	func italic(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.italic(p_text))
		return self

	func strike(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.strike(p_text))
		return self

	func code(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.code(p_text))
		return self

	func center(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.center(p_text))
		return self

	func right(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.right(p_text))
		return self

	func url(p_text: String, p_url: String) -> BBCodeBuilder:
		_bbcode_text.append(_bbcode_formatter.url(p_text, p_url))
		return self

	func raw(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(p_text)
		return self

	func escaped(p_text: String) -> BBCodeBuilder:
		_bbcode_text.append(BBCodeFormatter.escape_bbcode(p_text))
		return self

	func get_text(p_clear: bool) -> String:
		var text := "".join(_bbcode_text)
		if p_clear:
			clear()
		return text

	func join(p_separator: String) -> String:
		return p_separator.join(_bbcode_text)

	func clear() -> void:
		_bbcode_text.clear()

class LogRecordFormatter extends RefCounted:
	func format(p_log_record: Dictionary, p_sink_capabilties: Dictionary) -> String:
		return "LogRecordFormatter: format() not implemented."

class DefaultLogRecordFormatter extends LogRecordFormatter:
	func format(p_log_record: Dictionary, p_sink_capabilties: Dictionary) -> String:
		var bbcode_enabled: bool = p_sink_capabilties.has("bbcode") and p_sink_capabilties["bbcode"]

		var bbcode_formatter := BBCodeFormatter.new(bbcode_enabled)

		var tag: String = p_log_record["tag"]
		var time_unix: float = p_log_record["time_unix"]
		var level: LogLevel = p_log_record["level"]
		var unformatted_message: String = p_log_record["unformatted_message"]

		var time_str := Log.format_time_default(time_unix)
		var level_str := Log.format_log_level_name_short(level)

		var message_color_fg := Color.WHITE
		var message_color_bg := Color.TRANSPARENT

		var level_color: Color
		match level:
			LogLevel.TRACE:
				level_color = Color.CYAN
			LogLevel.DEBUG:
				level_color = Color.MAGENTA
			LogLevel.INFO:
				level_color = Color.GREEN
			LogLevel.WARNING:
				level_color = Color.ORANGE
			LogLevel.ERROR:
				level_color = Color.RED
				message_color_fg = Color.RED
				#message_color_bg = Color.WHITE

		var formatted_message := "[%s] [%s] [%s] %s" % [
			bbcode_formatter.color_fg(time_str, Color.GRAY),
			Log.pad_string(tag, 15),
			bbcode_formatter.color_fg(level_str, level_color),
			bbcode_formatter.color(unformatted_message, message_color_fg, message_color_bg),
		]
		if p_log_record.has("stack"):
			var stack: Array[Dictionary] = p_log_record["stack"]
			for frame in stack:
				var source: String = frame["source"]
				var line: int = frame["line"]
				var function: String = frame["function"]

				var url_target := "file://%s:%d" % [source, line]
				var url_text := "%s:%d:%s()" % [source, line, function]

				formatted_message += "\n\tAt: %s" % [
					bbcode_formatter.url(url_text, url_target),
				]
		return formatted_message

class Logger extends LogPipe:
	var _tag: String
	var _level: LogLevel
	var _pipe: LogPipe

	func _init(
		p_tag: String,
		p_level: LogLevel = LogLevel.TRACE,
		p_pipe: LogPipe = Log._global_logger
	) -> void:
		_tag = p_tag
		_level = p_level
		_pipe = p_pipe

	func write_bulks(p_log_records: Array[Dictionary]) -> void:
		_pipe.write_bulks(p_log_records)

	func flush_buffer() -> void:
		_pipe.flush_buffer()

	func get_tag() -> String:
		return _tag

	func set_level(p_level: LogLevel) -> void:
		_level = p_level

	func get_level() -> LogLevel:
		return _level

	func log(p_level: LogLevel, p_message: String, p_log_record: Dictionary = {}) -> void:
		if p_level < _level:
			return
		p_log_record["level"] = p_level
		p_log_record["tag"] = _tag
		p_log_record["time_unix"] = Time.get_unix_time_from_system()
		p_log_record["unformatted_message"] = p_message
		_pipe.write_bulks([p_log_record])

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
		_pipe.close()

class FormatTimeUsecResult:
	var elapsed: float
	var unit: String
	var color: Color
	var scale: int

	func _init(p_elapsed: float, p_unit: String, p_color: Color, p_scale: int) -> void:
		elapsed = p_elapsed
		unit = p_unit
		color = p_color
		scale = p_scale

	# TODO: COLOR SUPPORT depending on the sink capabilities
	func to_string() -> String:
		return "%.4f %s" % [elapsed, unit]

func format_time_usec(p_time_usec: int) -> FormatTimeUsecResult:
	var elapsed: int
	var unit: String
	var color: Color
	var scale: int
	if p_time_usec >= 1_000_000:
		scale = 1_000_000
		elapsed = p_time_usec / 1_000_000
		unit = "s"
		color = Color.RED
	elif p_time_usec >= 1_000:
		scale = 1_000
		elapsed = p_time_usec / 1_000
		unit = "ms"
		color = Color.BLUE
	else:
		scale = 1
		elapsed = p_time_usec
		unit = "µs"
		color = Color.GREEN
	return FormatTimeUsecResult.new(elapsed, unit, color, scale)


class LogTimer:
	var _start_time_usec: int
	var _end_time_usec: int

	var _total_time_usec: int

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
		_total_time_usec += elapsed_time_usec

		if _threshold_msec == 0:
			_logger.log(_level, "%s took %s." % [_message, format_time_usec(elapsed_time_usec).to_string()])
			return

		if _threshold_msec < elapsed_time_usec / 1000:
			_logger.log(_level, "%s exceeded threshold of %s: took %s." % [_message, format_time_usec(_threshold_msec * 1000).to_string(), format_time_usec(elapsed_time_usec).to_string()])

	func log_total_time() -> void:
		_logger.log(_level, "%s took %s in total." % [_message, format_time_usec(_total_time_usec).to_string()])

	func get_total_time_usec() -> int:
		return _total_time_usec

	func reset_total_time() -> void:
		_total_time_usec = 0

var _global_broadcast_pipe: BroadcastPipe
var _global_logger: Logger
var _logger_direct_console: Logger
var _global_log_record_formatter: LogRecordFormatter

func _init() -> void:
	_global_log_record_formatter = DefaultLogRecordFormatter.new()
	_global_broadcast_pipe = BroadcastPipe.new()
	_global_logger = Logger.new("Global", LogLevel.TRACE, _global_broadcast_pipe)
	_logger_direct_console = Logger.new("gdlogging", LogLevel.TRACE, ConsoleSink.new(_global_log_record_formatter))
	if Engine.is_editor_hint():
		add_pipe(ConsoleSink.new(_global_log_record_formatter))

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

func set_default_log_record_formatter(p_log_record_formatter: LogRecordFormatter) -> void:
	_global_log_record_formatter = p_log_record_formatter

func get_default_log_record_formatter() -> LogRecordFormatter:
	return _global_log_record_formatter

func add_pipe(p_pipe: LogPipe) -> void:
	_global_broadcast_pipe.add_pipe(p_pipe)

func remove_pipe(p_pipe: LogSink) -> void:
	_global_broadcast_pipe.remove_pipe(p_pipe)

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

func format_error(p_error: int) -> String:
	## removed static because of a an annoying hint to use the import statement instead of the singleton

	if ERROR_MESSAGES.has(p_error):
		return ERROR_MESSAGES[p_error]
	return "Unknown p_error (%d)." % p_error
