#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative 'change_frontmatter'
require_relative 'change_schema'

# Parses and validates a project's change-fabric config. There is one
# change-fabric file per repo, `CHANGE.md` at the repo root: its YAML
# frontmatter carries a `change_config:` block (the mechanical target-app
# details this class reads) alongside a `change_policy:` block (read by the merge
# gate), and its prose body is the human governance FAQ. Keeping everything in
# one file was a deliberate call: a repo declares how it is audited and how it is
# governed in a single place a person already opens.
#
# YAML frontmatter over a separate JSON file is deliberate: a human edits this by
# hand and wants comments, and the same block already holds the policy the gate
# reads. Validation fails loud with a ConfigError naming the offending key. A
# lane the project does not want is omitted or `enabled: false`; only lanes
# present and enabled run, so a repo can adopt one lane at a time.
class ChangeConfig
  class ConfigError < StandardError; end

  DEFAULT_PATH = 'CHANGE.md'
  # The accepted lanes come from the schema registry, so the validator and the
  # documented schema can never name a different set.
  LANES = ChangeSchema::LANES

  def self.load(path)
    raise ConfigError, "CHANGE.md not found: #{path}" unless File.exist?(path)

    front = ChangeFrontmatter.parse_file(path)
    config = front['change_config']
    unless config.is_a?(Hash)
      raise ConfigError, "CHANGE.md has no change_config: frontmatter block (or it is not a mapping): #{path}"
    end

    new(config, File.dirname(path))
  end

  # `dir` is the CHANGE.md directory, i.e. the repo root, used to resolve
  # repo-relative paths (a k6 script) the lanes reference.
  def initialize(raw, dir)
    @raw = raw
    @dir = dir
    validate
  end

  def project = @raw.fetch('project', 'project').to_s
  def boot = Boot.new(@raw['boot'] || {})

  # The repo root: the directory holding CHANGE.md.
  def repo_root = @dir

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
