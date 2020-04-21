# frozen_string_literal: true
require 'pastel'
require 'bundler'
require 'bundler/lockfile_parser'
require 'rubygems'
require 'rubygems/commands/dependency_command'

require_relative 'version'
require_relative 'formatters/factory'
require_relative 'deps'
require_relative 'bom'
require_relative 'spinner'

module Chelsea
  # Class to collect and audit packages from a Gemfile.lock
  class Gems
    attr_accessor :deps
    def initialize(file:, quiet: false, options: { 'format': 'text' })
      @quiet = quiet
      unless File.file?(file) || file.nil?
        raise 'Gemfile.lock not found, check --file path'
      end

      _silence_stderr if @quiet

      @pastel = Pastel.new
      @formatter = FormatterFactory.new.get_formatter(
        format: options[:format],
        quiet: @quiet)
      @client = Chelsea.client(options)
      @deps = Chelsea::Deps.new(path: Pathname.new(file))
      @spinner = Chelsea::Spinner.new
    end

    # Audits depenencies using deps library and prints results
    # using formatter library

    def execute
      server_response, dependencies, reverse_dependencies = audit
      if dependencies.nil?
        _print_err 'No dependencies retrieved. Exiting.'
        return
      end
      if server_response.nil?
        _print_err 'No vulnerability data retrieved from server. Exiting.'
        return
      end
      results = @formatter.get_results(server_response, reverse_dependencies)
      @formatter.do_print(results)

      server_response.map { |r| r['vulnerabilities'].length.positive? }.any? ? (exit 1) : (exit 0)
    end

    def collect_iq
      dependencies = @deps.dependencies
      dependencies
    end

    # Runs through auditing algorithm, raising exceptions
    # on REST calls made by @deps.get_vulns
    def audit
      # This spinner management is out of control
      # we should wrap a block with start and stop messages,
      # or use a stack to ensure all spinners stop.
      spin = @spinner.spin_msg 'Parsing dependencies'

      begin
        dependencies = @deps.dependencies
        spin.success('...done.')
      rescue StandardError => e
        spin.stop
        _print_err "Parsing dependency line #{gem} failed."
      end

      reverse_dependencies = @deps.reverse_dependencies

      spin = @spinner.spin_msg 'Parsing Versions'
      coordinates = @deps.coordinates
      spin.success('...done.')
      spin = @spinner.spin_msg 'Making request to OSS Index server'

      begin
        server_response = @client.get_vulns(coordinates)
        spin.success('...done.')
      rescue SocketError => e
        spin.stop('...request failed.')
        _print_err 'Socket error getting data from OSS Index server.'
      rescue RestClient::RequestFailed => e
        spin.stop('...request failed.')
        _print_err "Error getting data from OSS Index server:#{e.response}."
      rescue RestClient::ResourceNotFound => e
        spin.stop('...request failed.')
        _print_err 'Error getting data from OSS Index server. Resource not found.'
      rescue Errno::ECONNREFUSED => e
        spin.stop('...request failed.')
        _print_err 'Error getting data from OSS Index server. Connection refused.'
      rescue StandardError => e
        spin.stop('...request failed.')
        _print_err 'UNKNOWN Error getting data from OSS Index server.'
      end
      [server_response, dependencies, reverse_dependencies]
    end

    protected

    def _silence_stderr
      $stderr.reopen('/dev/null', 'w')
    end

    def _print_err(s)
      puts @pastel.red.bold(s)
    end

    def _print_success(s)
      puts @pastel.green.bold(s)
    end
  end
end
