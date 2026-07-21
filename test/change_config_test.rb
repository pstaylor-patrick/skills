# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../scripts/change_config"

class ChangeConfigTest < Minitest::Test
  # Writes a CHANGE.md whose frontmatter carries the given change_config hash
  # (dumped as YAML) plus a prose body, then loads it. YAML.dump emits the
  # leading `---`, so appending the closing fence yields valid frontmatter.
  def with_config(config)
    Dir.mktmpdir do |root|
      path = File.join(root, "CHANGE.md")
      File.write(path, "#{YAML.dump("change_config" => config)}---\n\nbody\n")
      yield ChangeConfig.load(path), root
    end
  end

  def test_enabled_lanes_in_fixed_order_and_skips_disabled
    config = { "project" => "app", "lanes" => {
      "browserless" => { "enabled" => true },
      "k6" => { "enabled" => true },
      "zap" => { "enabled" => false }
    } }
    with_config(config) do |loaded, _root|
      assert_equal %w[k6 browserless], loaded.enabled_lanes
    end
  end

  def test_unknown_lane_is_rejected
    error = assert_raises(ChangeConfig::ConfigError) do
      with_config("lanes" => { "bogus" => { "enabled" => true } }) { |_c| }
    end
    assert_match(/unknown lane/, error.message)
  end

  def test_no_enabled_lanes_is_rejected
    assert_raises(ChangeConfig::ConfigError) do
      with_config("lanes" => { "k6" => { "enabled" => false } }) { |_c| }
    end
  end

  def test_repo_root_is_the_change_md_directory
    with_config("lanes" => { "k6" => {} }) do |config, root|
      assert_equal root, config.repo_root
    end
  end

  def test_lane_paths_resolve_against_repo_root
    with_config("lanes" => { "k6" => { "script" => "apps/load/smoke.js" } }) do |config, root|
      assert_equal File.join(root, "apps", "load", "smoke.js"), config.lane("k6").path("script")
    end
  end

  def test_missing_change_config_block_raises
    Dir.mktmpdir do |root|
      path = File.join(root, "CHANGE.md")
      File.write(path, "---\nchange_policy:\n  protected_branches: [production]\n---\n\nbody\n")
      error = assert_raises(ChangeConfig::ConfigError) { ChangeConfig.load(path) }
      assert_match(/no change_config/, error.message)
    end
  end

  def test_missing_file_raises
    assert_raises(ChangeConfig::ConfigError) { ChangeConfig.load("/no/such/CHANGE.md") }
  end
end
