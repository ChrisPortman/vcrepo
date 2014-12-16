#!/usr/bin/env ruby
if RUBY_VERSION =~ /^1\.8/
  require 'require_relative'
end

require_relative '../lib/vcrepo'
require 'yaml'

def help
  puts <<-END.gsub(/^\s{4}/, '')
    Usage:
      vcrepo [OPTIONS] <command> [option [, option] ]
      vcrepo [OPTIONS] <command> help
      vcrepo [OPTIONS] help
    
    Options:
      -h | --host : The server hosting the repos server (Default: localhost)
    
    Valid commands:
  END
  
  Vcrepo.commands.sort.each do |c|
    puts "  #{c}"
  end
  exit
end

def find_class(namespace)
  mod = nil
  begin
    namespace.split(/::/).each do |p|
      if mod
        if mod.const_defined?(p)
          mod = mod.const_get(p)
        else
          return nil
        end
      else
        if Module.const_defined?(p)
          mod = Module.const_get(p)
        end
      end
    end
  rescue NameError
    return nil
  end
  return mod
end

if i = ARGV.index('-h') or ARGV.index('--host')
  if host = ARGV[ i + 1]
    Vcrepo.host = host
  end
  ARGV.delete_at(i)
  ARGV.delete_at(i)
end

command = ARGV.shift
if command.nil? or command == 'help'
  help
end

if Vcrepo.commands.include?(command)
  if cmd_class = find_class("Vcrepo::Commands::#{command.capitalize}")
    if ARGV.first == 'help'
      if cmd_class.methods.include?(:help)
        cmd_method = cmd_class.method(:help)
        puts cmd_method.call
      else
        puts "#{command} has no help"
      end
    else
      if cmd_class.methods.include?(:run)
        cmd_method = cmd_class.method(:run)
        result = cmd_method.call(ARGV)
        puts result.is_a?(String) ? result : result.to_yaml
      else
        puts "Failed to invoke command #{command}"
      end
    end
  else
    puts "Failed to invoke command #{command}"
  end
else
  puts "  Invalid command: #{command}\n"
  help
end

exit


