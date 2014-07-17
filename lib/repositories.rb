require 'logger'
require 'rugged'
require 'fileutils'

class RepoError < RuntimeError
  def initialize(msg, status=402)
    @status = status
    super(msg)
  end

  attr_reader 'status'
end

require_relative 'repositories/config'
require_relative 'repositories/initialize'
require_relative 'repositories/repo'
require_relative 'repositories/repo/yum'
require_relative 'repositories/repo/apt'
