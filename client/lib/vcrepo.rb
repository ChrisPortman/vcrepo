require 'net/http'
require 'uri'
require 'json'

require_relative 'vcrepo/commands'

module Vcrepo
  class << self
    @@environment = {}
    
    def commands
      Vcrepo::Commands.loadall
    end
    
    def host=(host)
      unless host.match(/^http/)
        host = "http://#{host}"
      end
      
      @@environment['host'] = host
    end
    
    def host
      @@environment['host'] || 'http://localhost'
    end
    
    def callapi(uri)
      url = URI.join(host, uri)
      response = Net::HTTP.get_response(url)
      begin
        JSON.parse(response.body)
      rescue
        response.body
      end
    end
  end
end
