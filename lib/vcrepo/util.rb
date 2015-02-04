module Vcrepo
  class Util
    def self.root_user?
      Process.uid == 0
    end

    def self.command_available?(exe)
      system("which #{exe} > /dev/null 2>&1")
    end

    def self.can_sudo?(command, user='root')
      #add a leading / to command
      command = "/#{command}"  #may result in leading //
      command.gsub!('//', '/') #replace any // with /

      if command_available?('sudo')
        sudo_rules = %x{ sudo -l }

        sudo_rules.split("\n").each do |l|
          next unless /NOPASSWD/.match(l)
          l.split(/\s*,\s*/).each do |c|
            c.strip!
            next unless /^\((root|ALL)\)/.match(c) #as root or ALL users
            return true if /(#{command}|ALL)$/.match(c) #the command or ALL
          end
        end
      end

      false
    end
  end
end
