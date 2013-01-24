#!/usr/bin/env ruby

require 'celluloid'
require 'logger'

LOG = Logger.new($stderr)

module Shelling
  def run(cmd, dry_run = false)
    cmd = "cd #{path} && #{cmd}"
    LOG.debug cmd

    if !dry_run
      `#{cmd}`
    end
  end
end

class Repo < Struct.new(:path)
  include Shelling

  def initialize(*)
    super
    
    config_remotes
  end

  def config_remotes
    @remotes = {}

    ret = run "git config --get-regexp remote.*"
    
    # If this fails, then something went wrong; bail
    return unless $?.success?

    config = Hash[*ret.split("\n").map { |l| l.split(/\s/) }.flatten]

    remotes = config.map do |k, v|
      k =~ /remote\.([^.]+)\./; $1
    end.uniq

    # For each remote, figure out if we're a push or fetch mirror
    remotes.each do |r|
      if config["remote.#{r}.mirror"] == 'true'
        @remotes[r] = :push
      else
        @remotes[r] = :fetch
      end
    end
  end

  def mirror_action(remote)
    return unless @remotes.has_key?(remote)

    if @remotes[remote] == :push
      MirrorAction.new(:push, remote, path)
    elsif @remotes[remote] == :fetch
      MirrorAction.new(:fetch, remote, path)
    end
  end
end

class MirrorAction < Struct.new(:action, :remote, :path)
  include Shelling

  ACTION_ORDER = [:fetch, :push]

  def <=>(other)
    a = ACTION_ORDER.index(action)
    b = ACTION_ORDER.index(other.action)

    a <=> b
  end

  def execute
    run("git #{action} #{remote}")
  end
end

class Runner
  include Celluloid

  def run(action)
    action.execute
  end
end

# ---

root = ARGV[0]
remotes = ARGV[1..-1]

abort unless root

# prevent ourselves from being stupid
remotes.reject { |r| r == 'origin' }

MAX_OUTBOUND = 6
R = Runner.pool(:size => MAX_OUTBOUND)

actions = Dir["#{root}/**/*.git"].each_with_object([]) do |path, as|
  repo = Repo.new(File.expand_path(path))

  remotes.each do |remote|
    action = repo.mirror_action(remote)
    if !action
      LOG.info "Nothing to do for repo #{path}, remote #{remote}"
    else
      as << action
    end
  end
end

futures = actions.sort.map { |a| R.future(:run, a) }
ok = futures.all?(&:value)

exit ok
