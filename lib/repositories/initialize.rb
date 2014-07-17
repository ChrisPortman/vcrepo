require_relative 'repo'

module Repositories
  class << self
    def config
      @@config ||= Config.new
    end

    def log(msg, file='general.log')
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

    @@logdir ||= Repositories.config['logdir'] || './logs'
    unless File.directory? @@logdir
      FileUtils.mkpath(@@logdir)
    end

    Repositories.config['repositories'].each do |repo, settings|
      Repositories::Repo.create(settings['type'], repo, settings['source'])
    end
  end
end
