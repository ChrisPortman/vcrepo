require_relative 'repo'

module Repositories
  class << self
    def config
      @@config ||= Config.new
    end

    def log(msg, file='general.log')
      @@logdir ||= Repositories.config['logdir'] || './logs'
      logfile = File.join(@@logdir, file)

      time = Time.new

      timeobj = Time.now
      date = ["%04d" % time.year, "%02d" % time.month, "%02d" % time.mday].join('/')
      time = ["%02d" % timeobj.hour, "%02d" % timeobj.min, "%02d" % timeobj.sec].join(':')
      timestamp = [date,time].join('-')  

      File.open(logfile, 'a') do |io|
        io.puts(timestamp+': '+msg)      
      end
    end

    Repositories.config['repositories'].each do |repo, settings|
      Repositories::Repo.new(settings['type'], settings['os'], settings['name'], settings['version'], settings['arch'], settings['source'])
    end
  end
end
