#!/usr/bin/env ruby
require 'em-http-request'
require 'json'
require 'ruby-prof'

# https://github.com/igrigorik/em-http-request/wiki/Issuing-Requests

class Engine
  include EM::Deferrable
  
  def initialize(params)
    options = {
      :connect_timeout =>30,        # default connection setup timeout
      :inactivity_timeout => 30,    # default connection inactivity (post-setup) timeout
    }
    EM.add_periodic_timer(params[:request_delay]) {
      bm = realtime do
        request = EM::HttpRequest.new(params[:url], options).get
        request.callback {
          status = request.response_header.status
          $stats[:codes][status] = ($stats[:codes][status].nil?) ? 1 : $stats[:codes][status] + 1
          if status < 400
            $stats[:pass] += 1 
          else
            puts "Error: #{status}"
            $stats[:errors] += 1 
          end
        }
      
        request.errback {
          $stats[:errors] += 1
          puts "errback: #{request.error}"
        }
      end
      $stats[:total] += 1
      $stats[:response_time] = bm
    }
  end
  
  def realtime
    r0 = Time.now
    yield
    Time.now - r0
  end
end

params = {
  poll_interval: 1,
  url: "http://localhost",
  request_delay: 1.0, 
  pattern: {
    start_count: 1,
    end_count: 1000, 
    duration: 120
  },
  duration: 120
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

RubyProf.start

start_time = Time.now.to_f 
EM.run {
  $stats = {volume: 0, total: 0, response_time: 0.0, pass: 0, errors: 0, codes:{}}
  EM.add_periodic_timer(step_delay) {
    remaining = params[:pattern][:end_count] - $stats[:volume]
    step_size = (remaining < step_size) ? remaining : step_size
    step_size.times do
      e = Engine.new(params)
    end
    $stats[:volume] += step_size
    $stats[:duration] = Time.now.to_f - start_time
  }
  
  EM.add_periodic_timer(params[:poll_interval]) { 
    puts $stats.to_json
    EM.stop_event_loop if $stats[:duration] >= params[:duration]
  }
}

result = RubyProf.stop

# Print a flat profile to text
printer = RubyProf::FlatPrinter.new(result)
printer.print(STDOUT)