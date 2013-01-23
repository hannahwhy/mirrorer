#!/usr/bin/env ruby

require 'celluloid'

class Repo < Struct.new(:path)
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

  def mirror(remote)
    if !@remotes.has_key?(remote)
      puts "Nothing to do for remote #{remote} on repo #{path}"
      return true
    end

    if @remotes[remote] == :push
      run "git push #{remote}"
    elsif @remotes[remote] == :fetch
      run "git fetch #{remote}"
    end

    $?.success?
  end

  def run(cmd, dry_run = false)
    cmd = "cd #{path} && #{cmd}"
    puts cmd

    if !dry_run
      `#{cmd}`
    end
  end
end

class Mirror
  include Celluloid

  def mirror_to_remote(repo, remote)
    repo.mirror(remote)
  end
end

# ---

mirror = Mirror.pool(:size => 4)
root = ARGV[0]
remotes = ARGV[1..-1]

abort unless root

# prevent ourselves from being stupid
remotes.reject { |r| r == 'origin' }

futures = Dir["#{root}/**/*.git"].each_with_object([]) do |path, fs|
  repo = Repo.new(File.expand_path(path))

  remotes.each do |remote|
    fs << mirror.future(:mirror_to_remote, repo, remote)
  end
end

ok = futures.all?(&:value)

exit ok
