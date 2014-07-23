require 'logger'
require 'fileutils'

class RepoError < RuntimeError
  def initialize(msg, status=402)
    @status = status
    super(msg)
  end

  attr_reader 'status'
end

require_relative 'vcrepo/config'
require_relative 'vcrepo/git'
require_relative 'vcrepo/initialize'
require_relative 'vcrepo/repository'
require_relative 'vcrepo/repository/yum'
require_relative 'vcrepo/repository/apt'
