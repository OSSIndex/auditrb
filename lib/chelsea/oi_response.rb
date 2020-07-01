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
require 'json'
require_relative 'oi_coord'
module Chelsea
  # Class for parsing OSS response and giving some methods
  class OIResponse
    attr_reader :coords

    def initialize(response)
      @coords = \
        response.sort! { |x| x['vulnerabilities'].count }
                .each_with_object([]) do |coord, arr|
          arr.append(OICoord.new(coord))
        end
    end

    def dep_count
      @coords.count
    end

    def vuln_count
      @vuln_count ||= @coords.count(&:vulnerable)
    end
  end
end
  #  def self.parse_response(r)
  #    response = ''
  #    name, version = r['coordinates'].sub('pkg:gem/', '').split('@')
  #    if r['vulnerabilities'].length.positive?
  #      response += @pastel.red(
  #        "[#{idx}/#{server_response.count}] - #{r['coordinates']} "
  #      )
  #      response += @pastel.red.bold("Vulnerable.\n")
  #      r['vulnerabilities'].each do |k, _|
  #        response += _format_vuln(k)
  #      end
  #    elsif
  #      response += @pastel.white(
  #        "[#{idx}/#{server_response.count}] - #{r['coordinates']} "
  #      )
  #      response += @pastel.green.bold("No vulnerabilities found!\n")
  #    end
  #  end