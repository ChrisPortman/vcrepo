#!/bin/env ruby
if RUBY_VERSION =~ /^1\.8/
  require 'require_relative'
end

require_relative '../lib/repositories'

repo_name = ARGV.shift

def print_valid_repos
  puts "Valid repos are:"

  Repositories::Repo.all.keys.each do |name|
    puts "  - #{name}"
  end
  puts ""
end

if repo_name
  if repo = Repositories::Repo.repo(repo_name)
    begin
      result  = repo.sync
      status  = result.shift
      message = result.shift
    rescue RepoError => e
      status  = e.status
      message = e.message
    end
    
    status = status == 200 ? 'Success' : 'Error'
    puts "#{status}: #{message}"
    
    if status == 'Success'
      logdir = Repositories.config['log_dir'] || File.join(File.dirname(__FILE__), "../logs")
      logfile = File.join(logdir, repo_name)
      puts "You can track the sync task with `tail -f #{logfile}`"
    end
  else
    puts "Error: Repo #{repo_name} does not exist"
    puts ""
    print_valid_repos
  end
else
  print_valid_repos
end

exit
