require_relative 'repository'

module Vcrepo
  class << self
    def config
      @@config ||= Config.new
    end
    
    def log(msg, file='general.log')
      logdir ||= Vcrepo.config['logdir'] || './logs'
      logfile = File.join(logdir, file)

      time = Time.new

      timeobj = Time.now
      date = ["%04d" % time.year, "%02d" % time.month, "%02d" % time.mday].join('/')
      time = ["%02d" % timeobj.hour, "%02d" % timeobj.min, "%02d" % timeobj.sec].join(':')
      timestamp = [date,time].join('-')

      File.open(logfile, 'a') do |io|
        io.puts(timestamp+': '+msg)
      end
    end
    
    def testdirwrite(dir)
      begin
        file = File.join(dir,'testwrite')
        f = File.open(file, 'w')
        f.close
        File.delete(file)
      rescue Exception => e
        raise FileSystemError, "Can not write in directory #{dir}: #{e.message}"
      end
      true
    end

    logdir ||= Vcrepo.config['logdir'] || './logs'
    unless File.directory? logdir
      begin
        FileUtils.mkpath(logdir)
      rescue Exception => e
        raise FileSystemError, e.message
      end
    end
    Vcrepo.testdirwrite(logdir)    

    if repo_base_dir = Vcrepo.config['repo_base_dir']
      unless File.directory? repo_base_dir
        begin
          FileUtils.mkpath(repo_base_dir)
        rescue Exception => e
          raise FileSystemError, e.message
        end
      end
    else
      raise ConfigError, "repo_base_dir must be set in the configuration"
    end
    Vcrepo.testdirwrite(repo_base_dir)

    Vcrepo.config['repositories'].each do |repo, settings|
      Vcrepo::Repository.create(repo, settings)
    end
  end
end
