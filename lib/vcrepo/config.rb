require 'yaml'

module Vcrepo
  class Config
    def initialize
      @file = (File.file?('/etc/vcrepo/config.yaml') and '/etc/vcrepo/config.yaml') ||
        (File.file?('./config.yaml') and './config.yaml')
      begin
        @config = File::open(@file, 'r') { |fh| YAML::load(fh) } || {}
      rescue Errno::ENOENT
        raise RuntimeError, "The config file does not exist"
      rescue Errno::EACCES
        raise RuntimeError, "The config file is not readable"
      end
    end

    def [](key)
      @config[key]
    end
  end
end
