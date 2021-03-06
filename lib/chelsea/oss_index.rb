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

require_relative 'config'
require 'rest-client'
require_relative 'db'

module Chelsea
  # OSS Index audit operations
  class OSSIndex
    DEFAULT_OPTIONS = {
      oss_index_username: '',
      oss_index_user_token: ''
    }.freeze
    def initialize(options: DEFAULT_OPTIONS)
      @oss_index_user_name = options[:oss_index_user_name]
      @oss_index_user_token = options[:oss_index_user_token]
      @db = DB.new
    end

    # Makes REST calls to OSS for vulnerabilities 128 coordinates at a time
    # Checks cache and stores results in cache

    def get_vulns(coordinates)
      remaining_coordinates, cached_server_response = _cache(coordinates)
      return cached_server_response unless remaining_coordinates['coordinates'].count.positive?

      remaining_coordinates['coordinates'].each_slice(128).to_a.each do |coords|
        res_json = JSON.parse(call_oss_index({ 'coordinates' => coords }))
        cached_server_response.concat(res_json)
        @db.save_values_to_db(res_json)
      end

      cached_server_response
    end

    def call_oss_index(coords)
      r = _resource.post coords.to_json, _headers
      r.code == 200 ? r.body : {}
    end

    private

    def _cache(coordinates) # rubocop:disable Metrics/MethodLength
      new_coords = { 'coordinates' => [] }
      cached_server_response = []
      coordinates['coordinates'].each do |coord|
        record = @db.get_cached_value_from_db(coord)
        if record.nil?
          new_coords['coordinates'].push(coord)
        else
          cached_server_response << record
        end
      end
      [new_coords, cached_server_response]
    end

    def _headers
      { :content_type => :json, :accept => :json, 'User-Agent' => _user_agent }
    end

    def _resource
      if !@oss_index_user_name.empty? && !@oss_index_user_token.empty?
        RestClient::Resource.new(
          _api_url,
          user: @oss_index_user_name,
          password: @oss_index_user_token
        )
      else
        RestClient::Resource.new(_api_url)
      end
    end

    def _api_url
      'https://ossindex.sonatype.org/api/v3/component-report'
    end

    def _user_agent
      "chelsea/#{Chelsea::VERSION}"
    end
  end
end
