# frozen_string_literal: true
require 'cucumber/step_match'
require 'cucumber/step_argument'
require 'cucumber/core_ext/string'

module Cucumber
  module RbSupport
    # A Ruby Step Definition holds a Regexp pattern and a Proc, and is
    # typically created by calling {RbDsl#register_rb_step_definition Given, When or Then}
    # in the step_definitions Ruby files.
    #
    # Example:
    #
    #   Given /I have (\d+) cucumbers in my belly/ do
    #     # some code here
    #   end
    #
    class RbStepDefinition

      class MissingProc < StandardError
        def message
          'Step definitions must always have a proc or symbol'
        end
      end

      class << self
        def new(rb_language, expression, proc_or_sym, options)
          raise MissingProc if proc_or_sym.nil?
          super rb_language, expression, create_proc(proc_or_sym, options)
        end

        private

        def create_proc(proc_or_sym, options)
          return proc_or_sym if proc_or_sym.is_a?(Proc)
          raise ArgumentError unless proc_or_sym.is_a?(Symbol)
          message = proc_or_sym
          target_proc = parse_target_proc_from(options)
          patch_location_onto lambda { |*args|
            target = instance_exec(&target_proc)
            target.send(message, *args)
          }
        end

        def patch_location_onto(block)
          location = Core::Ast::Location.of_caller(5)
          block.define_singleton_method(:source_location) { [location.file, location.line] }
          block
        end

        def parse_target_proc_from(options)
          return lambda { self } unless options.key?(:on)
          target = options[:on]
          case target
          when Proc
            target
          when Symbol
            lambda { self.send(target) }
          else
            lambda { raise ArgumentError, 'Target must be a symbol or a proc' }
          end
        end
      end

      attr_reader :expression

      def initialize(rb_language, expression, proc)
        @rb_language, @expression, @proc = rb_language, expression, proc
        #@rb_language.available_step_definition(regexp_source, location)
      end

      # @api private
      def to_hash
        type = expression.is_a?(CucumberExpressions::RegularExpression) ? 'regular expression' : 'regular expression'
        regexp = expression.regexp
        flags = ''
        flags += 'm' if (regexp.options & Regexp::MULTILINE) != 0
        flags += 'i' if (regexp.options & Regexp::IGNORECASE) != 0
        flags += 'x' if (regexp.options & Regexp::EXTENDED) != 0
        {
          source: {
            type: type,
            expression: expression.source
          },
          regexp: {
            source: regexp.source,
            flags: flags
          }
        }
      end

      # @api private
      def ==(step_definition)
        expression.source == step_definition.expression.source
      end

      # @api private
      def arguments_from(step_name)
        #args = StepArgument.arguments_from(@regexp, step_name)
        args = @expression.match(step_name)
        #@rb_language.invoked_step_definition(regexp_source, location) if args
        args
      end

      # @api private
      def invoke(args)
        begin
          #args = @rb_language.execute_transforms(args)
          @rb_language.current_world.cucumber_instance_exec(true, @expression.to_s, *args, &@proc)
        rescue Cucumber::ArityMismatchError => e
          e.backtrace.unshift(self.backtrace_line)
          raise e
        end
      end

      # @api private
      def backtrace_line
        "#{location}:in `#{@expression.to_s}'"
      end

      # @api private
      def file_colon_line
        case @proc
        when Proc
          location.to_s
        when Symbol
          ":#{@proc}"
        end
      end

      # The source location where the step defintion can be found
      def location
        @location ||= Cucumber::Core::Ast::Location.from_source_location(*@proc.source_location)
      end

      # @api private
      def file
        @file ||= location.file
      end
    end
  end
end
