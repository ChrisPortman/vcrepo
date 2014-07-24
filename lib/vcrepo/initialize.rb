require_relative 'repository'

module Vcrepo
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

    @@logdir ||= Vcrepo.config['logdir'] || './logs'
    unless File.directory? @@logdir
      FileUtils.mkpath(@@logdir)
    end

    Vcrepo.config['repositories'].each do |repo, settings|
      Vcrepo::Repository.create(repo, settings)
    end
  end
end
