#!/usr/bin/env ruby
require 'em-http'
require 'json'

# https://github.com/igrigorik/em-http-request/wiki/Issuing-Requests

class Engine
  include EM::Deferrable
  
  def initialize(params)
    EM.add_periodic_timer(params[:request_delay]) {
      request = EM::HttpRequest.new(params[:url]).get
      
      request.callback {
        status = request.response_header.status
        $stats[:codes][status] = ($stats[:codes][status].nil?) ? 1 : $stats[:codes][status] + 1
        if status < 400
          $stats[:pass] += 1 
        else
          $stats[:errors] += 1 
        end
      }
      
      request.errback {
        $stats[:errors] += 1
      }
    }
  end
end

params = {
  url: "http://studio-staging/system",
  request_delay: 0.5, 
  pattern: {
    start_count: 1,
    end_count: 1000, 
    duration: 60
  },
  duration: 60
}

step_size = (params[:pattern][:end_count] - params[:pattern][:start_count])/params[:pattern][:duration].to_f
if step_size < 1
  step_delay = 1/step_size
  step_size = 1
else
  step_delay = 1
  step_size = step_size.to_i
end
params[:duration] ||= params[:pattern][:duration]

start_time = Time.now.to_f 
EM.run {
  $stats = {volume: 0, pass: 0, errors: 0, codes:{}}
  EM.add_periodic_timer(step_delay) {
    remaining = params[:pattern][:end_count] - $stats[:volume]
    step_size = (remaining < step_size) ? remaining : step_size
    step_size.times do
      e = Engine.new(params)
    end
    $stats[:volume] += step_size
    $stats[:duration] = Time.now.to_f - start_time
    puts $stats.to_json
    
    exit if $stats[:duration] >= params[:duration]
  }
}
