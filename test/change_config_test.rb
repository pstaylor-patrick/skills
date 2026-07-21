# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/change_config"

class ChangeConfigTest < Minitest::Test
  def with_config(body)
    Dir.mktmpdir do |root|
      dir = File.join(root, ".pst")
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "change.yml")
      File.write(path, body)
      yield ChangeConfig.load(path), root
    end
  end

  def test_enabled_lanes_in_fixed_order_and_skips_disabled
    body = <<~YAML
      project: app
      lanes:
        browserless: { enabled: true }
        k6: { enabled: true }
        zap: { enabled: false }
    YAML
    with_config(body) do |config, _root|
      assert_equal %w[k6 browserless], config.enabled_lanes
    end
  end

  def test_unknown_lane_is_rejected
    body = "lanes:\n  bogus: { enabled: true }\n"
    error = assert_raises(ChangeConfig::ConfigError) { with_config(body) { |_c| } }
    assert_match(/unknown lane/, error.message)
  end

  def test_no_enabled_lanes_is_rejected
    body = "lanes:\n  k6: { enabled: false }\n"
    assert_raises(ChangeConfig::ConfigError) { with_config(body) { |_c| } }
  end

  def test_change_doc_defaults_to_repo_root
    with_config("lanes:\n  k6: {}\n") do |config, root|
      assert_equal File.join(root, "CHANGE.md"), config.change_doc
    end
  end

  def test_change_doc_honors_relocation
    with_config("change_doc: docs/POLICY.md\nlanes:\n  k6: {}\n") do |config, root|
      assert_equal File.join(root, "docs", "POLICY.md"), config.change_doc
    end
  end

  def test_missing_file_raises
    assert_raises(ChangeConfig::ConfigError) { ChangeConfig.load("/no/such/change.yml") }
  end
end
