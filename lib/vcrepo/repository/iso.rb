require 'fileutils'

# Repositories from ISO images such as RHEL and Centos DVDs
# This module will override a lot of the Vcrepo::Repository methods as
# none of the GIT stuff applies.  It is after all a read-only medium and
# not prone to change.

module Vcrepo
  class Repository::Iso < Vcrepo::Repository
    attr_reader :name, :settings, :source, :type, :dir, :enabled, :logger

    def initialize(name, settings)
      @name     = name
      @settings = settings
      @source   = settings['source']
      @type     = settings['type']
      @enabled  = (@source and @type) ? true : false

      #Progress through setting up the repo as log as enabled remains true
      (@enabled = (@logger = create_log ) ? true : false) if @enabled
      (@enabled = (@dir    = mount_dir  ) ? true : false) if @enabled
      (@enabled = (execute_sync         ) ? true : false) if @enabled
    end

    def iso
      if isofile = source.match(/^iso:\/\/(\/.+)$/)
        isofile[1]
      end
    end

    def mount_dir
      directory = File.join(Vcrepo.config['repo_base_dir'], type, name)
      begin
        File.directory?(directory) || FileUtils.mkdir_p(directory)
      rescue Exception => e
        logger.error("Can not create mount point for this repository it will be disabled: #{e.message}")
        return nil
      end
      directory
    end

    def execute_sync
      # (Re)Mount the iso...
      logger.info("Mounting #{iso} to #{dir}")
      if iso
        if File.readable?(iso)
          @enabled = umount  if     mounted?
          @enabled = mount   unless mounted?
        else
          logger.error("ISO file #{iso} is not readable.  Disabling repository")
          @enabled = false
        end
      end
      logger.info("Mounting #{iso} to #{dir} #{mounted? ? 'successful' : 'failed'}")
    end

    def mounted?
      if match = %x{mount}.match(/^#{iso} on #{dir}/)
        true
      else
        false
      end
    end

    def in_fstab?
      fstab = File.join('/', 'etc', 'fstab')
      if File.readable?(fstab)
        logger.info("Checking fstab for #{iso}")
        File.open(fstab, 'r') do |f|
          if f.read.match(/^#{iso}\s+#{dir}.+user/)
            logger.info("IS in fstab")
            return true
          else
            logger.info("NOT in fstab")
            return false
          end
        end
      else
        logger.info("Cant read #{fstab}")
        false
      end
    end

    def umount
      command = []
      
      unless Vcrepo::Util.root_user?
        unless in_fstab?
          Vcrepo::Util::can_sudo?('umount') or
            raise RepoError, "Not running as root, therefore, Iso files either need to be in /etc/fstab or I need to be able to run umount via sudo to unmount isos"
          command << 'sudo'
        end
      end
      
      command << [ 'umount', iso ]
      command.flatten!

      logger.info( "Unmount command: #{command.join(' ')}" )

      if system(*command)
        true
      else
        logger.error("Could not unmount #{iso} from #{dir}.  Disabling repository")
        false
      end
    end

    def mount
      command = []
      
      unless Vcrepo::Util.root_user?
        unless in_fstab?
          Vcrepo::Util::can_sudo?('mount') or
            raise RepoError, "Not running as root, therefore, Iso files either need to be in /etc/fstab or I need to be able to run mount via sudo to mount isos"
          command << 'sudo'
        end
      end

      command << [ 'mount', iso ]
      command.flatten!
      
      logger.info("Mount command: #{command.join(' ')}")

      if system(*command)
        true
      else
        logger.error("Could not mount #{iso} to #{dir}. Disabling repository")
        false
      end
    end

    def file?(file, release='na')
      file = File.join(dir, file)
      File.file?(file)
    end

    def link?(file, release='na')
      file = File.join(dir, file)
      File.symlink?(file)
    end

    def dir?(file, release='na')
      file = File.join(dir, file)
      File.directory?(file)
    end

    def file(file, release='na')
      file = File.join(dir, file)
      File.open(file, 'r'){ |f| f.read }
    end
    
    def contents(path=nil, release='master')
      path     = path ? File.join(dir, path) : dir
      contents = Dir.glob(File.join(path, '*'))
      contents.collect do |obj|
        {
          :name => File.basename(obj),
          :type => File.directory?(obj) ? :tree : :blob,
        }
      end
    end

    def locked?
      # It should always be available for sync given that the sync process
      # is just to remount the ISO.
      false
    end
    
    def git_repo
      #Stub returns nil as git is not applicable to ISO based repos
      nil
    end
  end
end
