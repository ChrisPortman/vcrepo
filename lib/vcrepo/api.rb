module Vcrepo
  class Api
    def self.sub_collections
      [ :repository ]
    end
    
    def self.collect(*args)
      [ :repository ]
    end
    
    def self.find(*args)
      collect
    end
  end
end

require_relative 'api/repository'
