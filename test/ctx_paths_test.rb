# frozen_string_literal: true

require_relative "test_helpers"
require_relative "#{SKILL_SCRIPTS}/ctx_paths"

# The dashed-cwd key and the home-prefix invariant are the foundation of the
# store keying, so they get a focused test even though the module is small.
class CtxPathsTest < Minitest::Test
  HOME = "/Users/pst"
  CWD = "/Users/pst/code/pst/pstaylor-patrick/skills"

  def test_dashed_replaces_every_slash
    assert_equal "-Users-pst-code-pst-pstaylor-patrick-skills", CtxPaths.dashed(CWD)
  end

  def test_store_dir_keys_under_home
    assert_equal "#{HOME}/.claude/pst/ctx/-Users-pst-code-x",
                 CtxPaths.store_dir("/Users/pst/code/x", home: HOME)
  end

  def test_class_index_and_roadmap_paths
    base = CtxPaths.store_dir(CWD, home: HOME)
    assert_equal File.join(base, "active"), CtxPaths.class_dir("active", CWD, home: HOME)
    assert_equal File.join(base, "INDEX.md"), CtxPaths.index(CWD, home: HOME)
    assert_equal File.join(base, "ROADMAP.md"), CtxPaths.roadmap(CWD, home: HOME)
    assert_equal File.join(base, ".ctx-meta", "device"), CtxPaths.meta("device", CWD, home: HOME)
  end

  def test_klass_predicate_excludes_archive
    assert CtxPaths.klass?("truth")
    assert CtxPaths.klass?("active")
    refute CtxPaths.klass?(CtxPaths::ARCHIVE)
    refute CtxPaths.klass?("nonsense")
  end

  def test_assert_home_passes_on_expected
    assert CtxPaths.assert_home!(CtxPaths::EXPECTED_HOME)
  end

  def test_assert_home_raises_on_divergent
    assert_raises(CtxPaths::HomeMismatch) { CtxPaths.assert_home!("/home/ci") }
  end

  def test_project_cwd_accepts_a_path_under_home
    assert CtxPaths.project_cwd?(CWD)
    assert CtxPaths.project_cwd?("/Users/pst/workspace/areas/foo")
  end

  def test_project_cwd_rejects_cwd_outside_home
    refute CtxPaths.project_cwd?("/private/var/folders/sk/abc/T/tmp.X1/demo")
    refute CtxPaths.project_cwd?("/tmp/scratch")
    refute CtxPaths.project_cwd?("/Volumes/ext/repo")
    refute CtxPaths.project_cwd?(CtxPaths::EXPECTED_HOME), "bare home is not a project"
  end

  def test_assert_project_raises_outside_home
    assert CtxPaths.assert_project!(CWD)
    assert_raises(CtxPaths::NotAProject) { CtxPaths.assert_project!("/private/tmp/x") }
  end
end
