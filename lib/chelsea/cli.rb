# frozen_string_literal: true

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

require 'slop'
require 'pastel'
require 'tty-font'

require_relative 'version'
require_relative 'gems'
require_relative 'iq_client'
require_relative 'config'

module Chelsea
  ##
  # This class provides an interface to the oss index, gems and deps
  class CLI # rubocop:disable Metrics/ClassLength
    def initialize(opts)
      @opts = opts
      @pastel = Pastel.new
      _validate_arguments
      _show_logo # Move to formatter
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def process! # rubocop:disable Metrics/AbcSize, Metrics/MethodLength,  Metrics/PerceivedComplexity
      if @opts.config?
        _set_config # move to init
      elsif @opts.clear?
        require_relative 'db'
        Chelsea::DB.new.clear_cache
        puts 'OSS Index cache cleared'
      elsif @opts.file? && @opts.iq?
        dependencies = _process_file_iq
        _submit_sbom(dependencies)
      elsif !@opts.file? && @opts.iq?
        abort 'Missing the --file argument. It is required with the --iq argument.'
      elsif @opts.file?
        _process_file
      elsif @opts.help? # quit on opts.help earlier
        puts _cli_flags # this doesn't exist
      else
        abort 'Missing arguments! Chelsea did nothing. Try providing the --file <Gemfile.lock> argument.'
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def self.version
      Chelsea::VERSION
    end

    private

    def _submit_sbom(gems) # rubocop:disable Metrics/MethodLength
      iq = Chelsea::IQClient.new(
        options: {
          public_application_id: @opts[:application],
          server_url: @opts[:server],
          username: @opts[:iquser],
          auth_token: @opts[:iqpass],
          stage: @opts[:stage]
        }
      )
      bom = Chelsea::Bom.new(gems.deps.dependencies).collect

      status_url = iq.post_sbom(bom)

      return unless status_url

      msg, color, exit_code = iq.poll_status(status_url)
      show_status(msg, color)
      # this may not be very ruby-esque, but `return exit_code` and `exit_code` didn't result in the desired exit status
      exit exit_code
    end

    def show_status(msg, color)
      case color
      when Chelsea::IQClient::COLOR_FAILURE
        puts @pastel.red.bold(msg)
      when Chelsea::IQClient::COLOR_WARNING
        # want yellow, but that doesn't print
        # puts @pastel.color.bold(msg, color)
        puts @pastel.blue.blue(msg)
      when Chelsea::IQClient::COLOR_NONE
        # want yellow, but that doesn't print
        puts @pastel.green.bold(msg)
      else
        puts @pastel.bold(msg)
      end
    end

    def _process_file
      gems = Chelsea::Gems.new(
        file: @opts[:file],
        verbose: @opts[:verbose],
        options: @opts
      )
      gems.execute ? (exit 1) : (exit 0)
    end

    def _process_file_iq
      gems = Chelsea::Gems.new(
        file: @opts[:file],
        verbose: @opts[:verbose],
        options: @opts
      )
      gems.collect_iq
      gems
    end

    def _flags_error
      switches = _flags.collect { |f| "--#{f}" }
      abort "please set one of #{switches}"
    end

    def _validate_arguments
      return unless !_flags_set? && !@opts.file?

      _flags_error
    end

    def _flags_set?
      # I'm still unsure what this is trying to express
      valid_flags = _flags.collect { |arg| @opts[arg] }.compact
      valid_flags.count > 1
    end

    def _flags
      # Seems wrong, should all be handled by bin
      %i[file help config]
    end

    def _show_logo
      font = TTY::Font.new(:doom)
      puts @pastel.green(font.write('Chelsea'))
      puts @pastel.green("Version: #{CLI.version}")
    end

    def _load_config
      config = Chelsea::Config.new
      config.oss_index_config
    end

    def _set_config
      Chelsea.read_oss_index_config_from_command_line
    end
  end
end
