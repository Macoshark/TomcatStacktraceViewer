#!/usr/bin/env ruby

STACKTRACE_LENGTH = 20
CONSOLE_WIDTH = 100

# -----------------------------------------------------------------------------
# Main method
# -----------------------------------------------------------------------------

def main
  if (ARGV.size == 0)
    abort "Specify a stacktrace file"
  end

  stacktraces = StacktraceHash.new(ARGV.first)

  stacktraces.menu.show_and_handle_input
end

# -----------------------------------------------------------------------------
# StacktraceHash. Contains all unique stacktraces found from the log file
# -----------------------------------------------------------------------------

class StacktraceHash
  attr_reader :menu

  # Reads stacktraces from the provided file and returns a hash map
  def initialize(filename)
    begin
      file = File.open(filename)
    rescue Exception => e
      abort "Failed to open file #{filename}! Error: " + e.message
    end

    @stacktraces = Hash.new
    stacktrace_begins = false
    current_stacktrace = nil
    line_num = 0

    check_and_add_current_stacktrace = lambda {
      if (current_stacktrace)
        current_stacktrace.end_line_num = line_num - 1
        other_stacktraces = @stacktraces[current_stacktrace.exception]
        other_stacktraces.each do |other|
          if (current_stacktrace.is_identical(other))
            other.add_message current_stacktrace.messages.first
            return
          end
        end

        @stacktraces[current_stacktrace.exception].push(current_stacktrace)
        current_stacktrace = nil
      end
    }

    file.each_line do |line|
      line_num += 1
      line.gsub!(/\r\n?/, "\n")

      if (stacktrace_begins)
        exception = ""
        regex_match = line.match(/(^.+?)\:/i)
        if (!regex_match)
          exception = line
        else
          exception = regex_match.captures[0]
        end

        if (!@stacktraces[exception])
            @stacktraces[exception] = Array.new
        end

        current_stacktrace = Stacktrace.new line_num, exception, line
      elsif (current_stacktrace != nil && !current_stacktrace.is_full)
        current_stacktrace.add_line(line)
      end

      if (line =~ /Full Stack Trace\:/)
        stacktrace_begins = true
        check_and_add_current_stacktrace.call
      else
        stacktrace_begins = false
      end
    end

    file.close

    check_and_add_current_stacktrace.call

    if (@stacktraces.size == 0)
      puts "No exceptions found from the log file. Exiting."
      exit 0
    end

    @stacktraces = Hash[@stacktraces.sort]

    init_menu
  end

  # Initializes the menu commands based on the stacktraces
  def init_menu
    header = "Showing exceptions from ".lightblue + ARGV.first.red
    @menu = Menu.new header, "Choose an exception type to view its occurrences:"
    @stacktraces.each do |exception, stacktrace_array|
      label = exception + ": " + "#{stacktrace_array.size} times".red
      command = ShowTracesCommand.new label, stacktrace_array
      @menu.add_command command
    end

      @menu.add_command BackCommand.new "Exit"
  end
end

# -----------------------------------------------------------------------------
# Stacktrace. Contains data from a single stack trace
# -----------------------------------------------------------------------------

class Stacktrace
  attr_reader :line_num, :exception, :messages, :traces, :end_line_num
  attr_writer :end_line_num

  def initialize(line_num, exception, first_line)
    @line_num = line_num
    @end_line_num = -1
    @exception = exception
    @messages = Array.new
    @messages.push first_line.gsub(exception, "").gsub(/^[ \:]+/, "")
    @traces = Array.new
  end

  def add_line(line)
    @traces.push(line)
  end

  def is_full
    @traces.length >= STACKTRACE_LENGTH
  end

  def pretty_messages
    ret = Array.new
    @messages.each do |message|
      if (message.length > CONSOLE_WIDTH)
        parts = message.chars.each_slice(CONSOLE_WIDTH).map(&:join)
        ret.push parts.join("\n    ")
      else
        ret.push message
      end
    end
    ret.join("")
  end

  def show
    trace_count = @traces.size
    puts "Amount of stack traces: #{trace_count}".lightblue

    first = @traces.first
    puts "firsti " + first.class.to_s

    trace = first['trace']

    trace.each do |line|
      puts "line: " + line
    end
  end

  def is_identical(other)
     @exception === other.exception && @traces.eql?(other.traces)
  end

  def has_message(msg)
    @messages.include? msg
  end

  def add_message(message)
    if (message && message.length > 1 && !has_message(message))
      @messages.push message
    end
  end
end

# -----------------------------------------------------------------------------
# Menu
# -----------------------------------------------------------------------------

class Menu
  attr_writer :exit_requested

  def initialize(header, prompt = "Enter command:")
    @header = header
    @prompt = prompt
    @commands = Hash.new
    @command_index = 1
    @exit_requested = false
  end

  def add_command(command)
    if (@commands[command.id])
      raise ArgumentError "Command with id #{command.id} already exists in the menu!"
    end

    if (command.id === "-1")
      command.id = @command_index.to_s
      @command_index += 1
    end

    command.menu = self
    @commands[command.id] = command
  end

  def show_and_handle_input
    while (!@exit_requested)

      puts "\n#{@header}\n\n"
      @commands.each do |id, command|
        command.print_command
      end
      puts

      print "#{@prompt} ".lightblue
      input = STDIN.gets.chomp

      if (input === '')
        input = "0"
      end

      command = @commands[input]
      if (!command)
        puts "Command not found"
        next
      end

      command.execute
    end
  end
end

# -----------------------------------------------------------------------------
# Command base class
# -----------------------------------------------------------------------------

class Command
  attr_reader :label, :id
  attr_writer :id, :menu

  def initialize(label, id = -1)
    @id = id.to_s
    @label = label
    @menu = nil
  end

  def print_command
        puts "#{@id}) ".green + @label
  end

  def execute
  end
end

# -----------------------------------------------------------------------------
# Back command
# -----------------------------------------------------------------------------

class BackCommand < Command
  def initialize(label = "Back")
    super("or Enter ) #{label}".green, 0)
  end

  def execute
    @menu.exit_requested = true
  end
end

# -----------------------------------------------------------------------------
# Show traces command
# -----------------------------------------------------------------------------

class ShowTracesCommand < Command
  def initialize(label, stacktrace_array)
    super(label)
    @stacktrace_array = stacktrace_array
  end

  def execute
    if (@stacktrace_array.length > 1)
      header = "Instances of exception ".lightblue + @stacktrace_array.first.exception.red
      menu = Menu.new header, "Choose an exception instance to view it in an external viewer:"
      @stacktrace_array.each do |stacktrace|
        menu.add_command(ShowSingleTraceCommand.new(stacktrace.pretty_messages, stacktrace))
      end
      menu.add_command ShowLineNumbersCommand.new @stacktrace_array
      menu.add_command ExportToFileCommand.new @stacktrace_array
      menu.add_command BackCommand.new

      menu.show_and_handle_input
    else
      stacktrace = @stacktrace_array.first
      ShowSingleTraceCommand.open_trace_in_viewer stacktrace.line_num
    end
  end
end

# -----------------------------------------------------------------------------
# Show single trace command
# -----------------------------------------------------------------------------

class ShowSingleTraceCommand < Command
  def initialize(label, stacktrace)
    super(label)
    @stacktrace = stacktrace
  end

  def execute
    ShowSingleTraceCommand.open_trace_in_viewer @stacktrace.line_num
  end

  def self.open_trace_in_viewer(line_num)
    system "less -N +#{line_num}g #{ARGV.first}"
  end
end

class ShowLineNumbersCommand < Command
  def initialize(stacktraces)
    super "Show line numbers".green
    @stacktraces = stacktraces
  end

  def execute
    exception = @stacktraces.first.exception
    puts "\nLine numbers for the ccurrences of ".lightblue + exception.red
    puts @stacktraces.collect{|it| it.line_num}.join(', ')
    puts "Press enter to continue..."
    STDIN.gets
  end
end

# -----------------------------------------------------------------------------
# Export to file command
# -----------------------------------------------------------------------------

class ExportToFileCommand < Command
  def initialize(stacktraces)
    super "Export occurrences to file(s)".green
    @stacktraces = stacktraces
  end

  def execute
    print "Enter file name: "
    filename = STDIN.gets.chomp
    if (filename === "")
      puts "Nothing entered, canceling"
      return
    end

    (basename, extension) = filename.match(/^(.+)\.(.+?)$/i).captures

    export_to_file = lambda {|filename, stacktrace|
      system "sed -n '#{stacktrace.line_num},#{stacktrace.end_line_num}p' #{ARGV.first} > #{filename}"
    }

    if (@stacktraces.length == 1)
      export_to_file.call filename, @stacktraces.first
    else
      @stacktraces.each_with_index do |stacktrace, index|
        name = basename + (index + 1).to_s + "." + extension
        export_to_file.call name, stacktrace
      end
    end

    puts "Occurrences exported. Press enter to continue..."
    STDIN.gets
  end
end

# -----------------------------------------------------------------------------
# Add colorization to strings
# -----------------------------------------------------------------------------

class String
  def colorize(color_code)
    "\e[#{color_code}m#{self}\e[0m"
  end

  def red
    colorize(31)
  end

  def lightblue
    colorize(36)
  end

  def blue
    colorize(34)
  end

  def green
    colorize(32)
  end

  def yellow
    colorize(33)
  end

  def pink
    colorize(35)
  end
end

# -----------------------------------------------------------------------------
# End of class declarations. Call the main method
# -----------------------------------------------------------------------------

main
