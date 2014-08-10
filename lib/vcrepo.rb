require 'logger'
require 'fileutils'

class RepoError < RuntimeError
  def initialize(msg, status=402)
    @status = status
    super(msg)
  end

  attr_reader 'status'
end

class FileSystemError < RuntimeError
  def initialize(message, status=500)
    @status = status
    super(message)
  end

  attr_reader 'status'
end

class ConfigError < RuntimeError
  def initialize(message, status=500)
    @status = status
    super(message)
  end

  attr_reader 'status'
end

require_relative 'vcrepo/config'
require_relative 'vcrepo/git'
require_relative 'vcrepo/initialize'
require_relative 'vcrepo/repository'
require_relative 'vcrepo/repository/yum'
require_relative 'vcrepo/repository/apt'
require_relative 'vcrepo/api'
