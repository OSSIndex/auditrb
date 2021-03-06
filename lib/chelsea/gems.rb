#
# Copyright 2019-Present Sonatype Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

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

    def initialize(file:, verbose:, options: { format: 'text' }) # rubocop:disable Metrics/MethodLength
      @verbose = verbose
      raise 'Gemfile.lock not found, check --file path' unless File.file?(file) || file.nil?

      _silence_stderr unless @verbose

      @pastel = Pastel.new
      @formatter = FormatterFactory.new.get_formatter(
        format: options[:format],
        verbose: verbose
      )
      @client = Chelsea.client(options)
      @deps = Chelsea::Deps.new(path: Pathname.new(file))
      @spinner = Chelsea::Spinner.new
    end

    # Audits depenencies using deps library and prints results
    # using formatter library

    def execute # rubocop:disable Metrics/MethodLength
      server_response, dependencies, reverse_dependencies = audit
      if dependencies.nil?
        _print_err 'No dependencies retrieved. Exiting.'
        return
      end
      if server_response.nil?
        _print_success 'No vulnerability data retrieved from server. Exiting.'
        return
      end
      results = @formatter.fetch_results(server_response, reverse_dependencies)
      @formatter.do_print(results)

      server_response.map { |r| r['vulnerabilities'].length.positive? }.any?
    end

    def collect_iq
      @deps.dependencies
    end

    # Runs through auditing algorithm, raising exceptions
    # on REST calls made by @deps.get_vulns
    def audit # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      # This spinner management is out of control
      # we should wrap a block with start and stop messages,
      # or use a stack to ensure all spinners stop.
      spin = @spinner.spin_msg 'Parsing dependencies'

      begin
        dependencies = @deps.dependencies
        spin.success('...done.')
      rescue StandardError
        spin.stop
        _print_err "Parsing dependency line #{gem} failed."
      end

      reverse_dependencies = @deps.reverse_dependencies

      spin = @spinner.spin_msg 'Parsing Versions'
      coordinates = @deps.coordinates
      spin.success('...done.')
      spin = @spinner.spin_msg 'Making request to OSS Index server'
      spin.stop

      begin
        server_response = @client.get_vulns(coordinates)
        spin.success('...done.')
      rescue SocketError
        spin.stop('...request failed.')
        _print_err 'Socket error getting data from OSS Index server.'
      rescue RestClient::RequestFailed => e
        spin.stop('...request failed.')
        _print_err "Error getting data from OSS Index server:#{e.response}."
      rescue RestClient::ResourceNotFound
        spin.stop('...request failed.')
        _print_err 'Error getting data from OSS Index server. Resource not found.'
      rescue Errno::ECONNREFUSED
        spin.stop('...request failed.')
        _print_err 'Error getting data from OSS Index server. Connection refused.'
      end
      [server_response, dependencies, reverse_dependencies]
    end

    protected

    def _silence_stderr
      $stderr.reopen('/dev/null', 'w')
    end

    def _print_err(msg)
      puts @pastel.red.bold(msg)
    end

    def _print_success(msg)
      puts @pastel.green.bold(msg)
    end
  end
end
