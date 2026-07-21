#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

# Parses and validates a project's change-fabric config, the single file that
# lets a repo be audited by the platform without carrying any of the tools as its
# own dependencies. The default location is `.pst/change.yml` at the repo root.
#
# YAML over JSON is deliberate: every authored contract in this repo already
# reads as YAML (each SKILL.md frontmatter), a human edits this file by hand, and
# it wants comments (which JSON cannot carry). settings.json is machine-wired by
# install.rb and is a different audience.
#
# Validation fails loud with a ConfigError naming the offending key. A lane the
# project does not want is simply omitted or `enabled: false`; only the lanes
# present and enabled run, so a repo can adopt one lane at a time.
class ChangeConfig
  class ConfigError < StandardError; end

  DEFAULT_PATH = '.pst/change.yml'
  LANES = %w[k6 a11y zap browserless].freeze

  def self.load(path)
    raise ConfigError, "config not found: #{path}" unless File.exist?(path)

    raw = YAML.safe_load(File.read(path)) || {}
    raise ConfigError, "config root must be a mapping: #{path}" unless raw.is_a?(Hash)

    new(raw, File.dirname(path))
  rescue Psych::SyntaxError => e
    raise ConfigError, "config is not valid YAML: #{e.message}"
  end

  # `dir` is the config file's directory, used to resolve repo-relative paths
  # (a k6 script) the lanes reference.
  def initialize(raw, dir)
    @raw = raw
    @dir = dir
    validate
  end

  def project = @raw.fetch('project', 'project').to_s
  def boot = Boot.new(@raw['boot'] || {})

  # The repo root, inferred from the conventional `.pst/change.yml` location so
  # the narrative policy doc can be found beside it. A config kept elsewhere
  # treats its own directory as the root.
  def repo_root
    File.basename(@dir) == '.pst' ? File.expand_path('..', @dir) : @dir
  end

  # Absolute path to the repo's narrative change-management doc (CHANGE.md by
  # default), the human-and-agent policy layer that the config's mechanical
  # target-app details deliberately do not carry. `change_doc:` relocates it.
  def change_doc
    File.expand_path(@raw.fetch('change_doc', 'CHANGE.md'), repo_root)
  end

  # The enabled lanes, in the fixed LANES order so a report's lane sequence is
  # stable across runs regardless of the file's key order.
  def enabled_lanes
    LANES.select { |name| lane_enabled?(name) }
  end

  def lane(name) = LaneConfig.new(name.to_s, @raw.dig('lanes', name.to_s) || {}, @dir)

  private

  def lane_enabled?(name)
    section = @raw.dig('lanes', name)
    section.is_a?(Hash) && section.fetch('enabled', true) != false
  end

  def validate
    lanes = @raw['lanes']
    raise ConfigError, "'lanes' must be a mapping" unless lanes.nil? || lanes.is_a?(Hash)

    unknown = (lanes || {}).keys - LANES
    raise ConfigError, "unknown lane(s): #{unknown.join(', ')}" unless unknown.empty?
    raise ConfigError, 'no lanes enabled' if enabled_lanes.empty?
  end

  # How to bring the target app up and confirm it is ready before any lane runs.
  # `network` is an existing docker network the runners join (the app's own
  # compose network); when absent the runner creates an ephemeral one. `health`
  # is polled from the host, so its url must be host-reachable even though the
  # lane `base_url`s address services by their in-network name.
  class Boot
    def initialize(raw) = @raw = raw

    def up = @raw['up'].to_s
    def down = @raw['down'].to_s
    def network = @raw['network']&.to_s
    def target_url = @raw['target_url'].to_s
    def health_url = @raw.dig('health', 'url').to_s
    def health_status = Integer(@raw.dig('health', 'expect_status') || 200)
    def health_timeout = Integer(@raw.dig('health', 'timeout_seconds') || 120)
    def up? = !up.empty?
  end

  # One lane's settings, read through named accessors so a lane script never digs
  # into the raw hash. Absent keys fall back to per-lane defaults the lane script
  # supplies, keeping this a thin typed view rather than a place for policy.
  class LaneConfig
    def initialize(name, raw, dir)
      @name = name
      @raw = raw
      @dir = dir
    end

    def name = @name
    def [](key) = @raw[key.to_s]
    def fetch(key, default) = @raw.fetch(key.to_s, default)
    def env = (@raw['env'] || {}).transform_keys(&:to_s).transform_values(&:to_s)

    # Resolves a repo-relative path (e.g. a k6 script) against the config dir, or
    # nil when the key is absent so the lane can fall back to a built-in default.
    def path(key)
      value = @raw[key.to_s]
      value && File.expand_path(value.to_s, @dir)
    end

    def base_url(fallback) = (@raw['base_url'] || fallback).to_s
  end
end
