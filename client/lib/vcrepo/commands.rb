module Vcrepo
  class Commands
    def self.loadall
      commands = []
      
      files = Dir.glob(File.join(File.dirname(__FILE__), 'commands', '*.rb'))
      files.each do |f|
        command = File.basename(f, '.rb')
        require_relative "commands/#{command}"
        commands.push(command)
      end
      commands
    end
  end
end
