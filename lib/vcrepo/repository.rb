module Vcrepo
  class Repository
    ### Class Variables ###
    #Stores the repository object for each repository
    @@repositories = {}

    ### Class Methods
    def self.create(name, settings)
      unless @@repositories[name]
        if type = settings['type']
          case type
            when 'yum'
              @@repositories[name] = Vcrepo::Repository::Yum.new(name, settings)
            when 'apt'
              @@repositories[name] = Vcrepo::Repository::Apt.new(name, settings)
            else
          end
        else
          raise ArgumentError, "Type for repo #{name} must be suplied"
        end
      end
    end

    def self.all
      @@repositories
    end

    def self.find(name)
      ret = nil
      @@repositories.each do |n,repo|
        if name == n
          ret = repo
        end
      end
      ret
    end

    def self.sync_all
      @repositories.each do |name, repo|
        repo.sync
      end
    end

    def sync
      if locked?
        return [ 402, "Sync is already in progress" ]
      end

      pid = fork do
        @logger.info('Starting Sync')

        lock

        #For non local sources, we will create a temporary working dir to sync to.  This avoids complications
        #when someone has been messing about in the regular workdir (playing with tags or branching or something)
        #For locally sourced repos though, its expected that the admin knows what theyre doing.
        if source =~ /^local/
          #This should make the repo look like the last commit on Master without clobering any manual adds since (we want to add those)
          @git_repo.safe_checkout("master")
          prepare_repo()
          @git_repo.commit
          @logger.info('Sync complete')
        else
          tmp_work_dir = File.join(Vcrepo.config['repo_base_location'], ".#{@name}-#{Time.new.to_i}")

          #create and use a temporary work dir so manual stuff in the normal work dir doesnt get in the way
          unless File.directory?(tmp_work_dir)
            FileUtils.mkdir_p(tmp_work_dir)
          end

          #Check the master branch out to the temp work dir.
          @git_repo.hard_checkout("master", tmp_work_dir)

          #Run the sync source method which is defined in the repositories type class
          begin
            sync_source()
          rescue RepoError => e
            @logger.error("Sync of repository #{@name} failed: #{e.message}")
          else
            #Move the packages to the cache and generate metadata then commit
            prepare_repo()
            @git_repo.commit
            @logger.info('Sync complete')
          end

          #remove the temporary work dir
          FileUtils.rm_rf(tmp_work_dir) if tmp_work_dir
        end

        #Set the workdir of the GIT repo back to the real one
        @git_repo.reset_workdir

        unlock
      end
      Process.detach(pid)
      [ 200, "Sync of #{@name} has been started." ]
    end

    def http_sync
      if system('which lftp > /dev/null 2>&1')
        http_sync_includes = self.class.http_sync_include.collect { |inc| "-I #{inc}" }.join(' ')
        http_sync_excludes = (self.class.http_sync_exclude).flatten.collect { |exc| "-X \"#{exc}\"" }.join(' ')

        sync_cmd = "#{`which lftp`.chomp} -c '; mirror -P -c -e -L -vvv #{http_sync_includes} #{http_sync_excludes} #{@source} #{repo_dir}'"

        IO.popen(sync_cmd).each do |line|
          @logger.info( line.chomp )
        end
      else
        raise RepoError, "Failed to run sync.  Processes required lftp but it does not appear to be installed"
      end
    end

    def lock
      FileUtils.touch(File.join(@git_repo.path, '.locked'))
    end

    def unlock
      FileUtils.rm_f(File.join(@git_repo.path, '.locked'))
    end

    def locked?
      File.exist?(File.join(@git_repo.path, '.locked'))
    end

    def check_dir
      base = Vcrepo.config['repo_base_location']
      dir  = File.join(base, @type, @name)
      File.directory?(dir) || FileUtils.mkdir_p(dir)
      dir
    end

    def repo_dir
      dir = File.join(@git_repo.workdir, 'repo')
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      dir
    end

    def package_cache_dir
      dir = File.join(Vcrepo.config['repo_base_location'], 'package_cache')
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
      end
      dir
    end

    def create_log
      log_dir  = Vcrepo.config['logdir'] || './logs'
      log_file = File.join(log_dir, @name)

      unless File.directory?(log_dir)
        FileUtils.mkdir_p(log_dir)
      end

      if File.file?(log_file)
        unless File.writable?(log_file)
          begin 
            File.chmod(0666, log_file)
          rescue
            (1..10).each do |i|
              log_file = log_file + i.to_s
              if File.file?(log_file)
                break if File.writable?(log_file)
              else
                File.open(log_file, "w").close
                File.chmod(0666, log_file)
                break
              end
            end
          end
        end
      else
        File.open(log_file, "w").close
        File.chmod(0666, log_file)
      end
      
      Logger.new(log_file)
    end

    def prepare_repo
      package_files = []
      self.class.package_patterns.each do |pattern|
        package_files << Dir.glob(File.join(@git_repo.workdir, '**', pattern))
      end

      package_files.flatten.each do |file|
        link_package(file)
      end

      generate_repo
    end

    def link_package(file)
      packages_dir = package_cache_dir()

      newfile = File.join(packages_dir, File.basename(file))
      File.exists?(newfile) ? FileUtils.rm(file) : FileUtils.mv(file, newfile)

      FileUtils.ln_s(newfile, file)
    end

    def file?(file, release='master')
      file = "repo/#{file}"
      @git_repo.file?(file, release)
    end

    def link?(file, release='master')
      file = "repo/#{file}"
      @git_repo.link?(file, release)
    end

    def file(file, release='master')
      file = "repo/#{file}"
      @git_repo.file(file, release)
    end

    def contents(path=nil, release='master')
      path = path ? File.join('repo', path) : 'repo'
      @git_repo.tree_contents(path, release)
    end

    def find_commit(release)
      @git_repo.find_commit(release)
    end
  end
end

require_relative 'repository/yum'
require_relative 'repository/apt'
