# frozen_string_literal: true
# Minitest tests for the ctx helpers in pst_common.rb
# Run with: ruby skills/pst/scripts/hooks/test/test_ctx.rb
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../pst_common'

module Pst
  # Override HOME for tests so we never touch real ~/.ctx or ~/.claude/pst
  TEST_CTX_ROOT = nil # set per-test via @ctx_root

  # Allow tests to inject a custom resolve_project override
  module_function

  def _write_frontmatter(path, fm_hash, body = '')
    lines = ['---']
    fm_hash.each { |k, v| lines << "#{k}: #{v.inspect}" }
    lines << '---'
    lines << ''
    lines << body unless body.empty?
    File.write(path, lines.join("\n"))
  end
end

class TestParseCtxFrontmatter < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('pst_ctx_test')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_doc(filename, frontmatter_str, body = '')
    path = File.join(@dir, filename)
    File.write(path, "---\n#{frontmatter_str}\n---\n\n#{body}")
    path
  end

  def test_valid_frontmatter
    path = write_doc('doc.md', "org: servant-io\nproject: great-grants\ntype: prd\ndate: 2026-01-15", 'Body here.')
    fm = Pst.parse_ctx_frontmatter(path)
    refute_nil fm
    assert_equal 'servant-io', fm['org']
    assert_equal 'great-grants', fm['project']
    assert_equal 'prd', fm['type']
    assert_equal '2026-01-15', fm['date']
  end

  def test_missing_frontmatter_returns_nil
    path = File.join(@dir, 'no_fm.md')
    File.write(path, "Just plain text, no frontmatter.\n")
    assert_nil Pst.parse_ctx_frontmatter(path)
  end

  def test_malformed_yaml_returns_nil
    path = File.join(@dir, 'bad.md')
    File.write(path, "---\nkey: [unclosed bracket\n---\n\nBody")
    # malformed YAML should rescue and return nil
    result = Pst.parse_ctx_frontmatter(path)
    assert_nil result
  end

  def test_org_md_parses_without_project
    path = File.join(@dir, '_org.md')
    File.write(path, "---\norg: servant-io\ntype: ref\ndate: 2026-01-01\n---\n\nOrg-level notes.")
    fm = Pst.parse_ctx_frontmatter(path)
    refute_nil fm
    assert_equal 'servant-io', fm['org']
    assert_nil fm['project']
  end

  def test_nonexistent_file_returns_nil
    path = File.join(@dir, 'nonexistent.md')
    assert_nil Pst.parse_ctx_frontmatter(path)
  end
end

class TestCtxBodyExcerpt < Minitest::Test
  def setup
    @dir = Dir.mktmpdir('pst_ctx_excerpt_test')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_doc(filename, content)
    path = File.join(@dir, filename)
    File.write(path, content)
    path
  end

  def test_short_body_returned_in_full
    path = write_doc('short.md', "---\norg: x\n---\n\nShort body.")
    result = Pst.ctx_body_excerpt(path)
    assert_equal 'Short body.', result
  end

  def test_long_body_truncated
    body = 'A' * 300
    path = write_doc('long.md', "---\norg: x\n---\n\n#{body}")
    result = Pst.ctx_body_excerpt(path)
    assert result.end_with?('...')
    assert result.length <= 283 # 280 chars + '...'
  end

  def test_body_without_frontmatter
    path = write_doc('nofm.md', 'Plain body text.')
    result = Pst.ctx_body_excerpt(path)
    assert_equal 'Plain body text.', result
  end

  def test_custom_char_limit
    path = write_doc('custom.md', "---\norg: x\n---\n\n#{'B' * 100}")
    result = Pst.ctx_body_excerpt(path, 50)
    assert result.end_with?('...')
    assert result.length <= 53
  end

  def test_nonexistent_file_returns_empty_string
    path = File.join(@dir, 'ghost.md')
    assert_equal '', Pst.ctx_body_excerpt(path)
  end
end

class TestResolveCtx < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('pst_resolve_ctx_test')
    @ctx_root = File.join(@tmpdir, '.ctx')
    @orgs_dir = File.join(@ctx_root, 'orgs')
    @original_home = Dir.home

    # Monkey-patch File.expand_path for '~/.ctx' to use our tmpdir
    # We do this by temporarily redefining HOME env
    @orig_home_env = ENV['HOME']
    ENV['HOME'] = @tmpdir
  end

  def teardown
    ENV['HOME'] = @orig_home_env
    FileUtils.rm_rf(@tmpdir)
  end

  def make_org_dir(org)
    dir = File.join(@orgs_dir, org)
    FileUtils.mkdir_p(dir)
    dir
  end

  def write_doc(org, filename, date, project, type = 'notes', body = 'Content.')
    dir = make_org_dir(org)
    path = File.join(dir, filename)
    File.write(path, "---\norg: #{org}\nproject: #{project}\ntype: #{type}\ndate: #{date}\n---\n\n#{body}")
    path
  end

  def test_returns_empty_when_ctx_root_absent
    # @orgs_dir does not exist yet
    project = { org: 'servant-io', name: 'great-grants', stacks: [] }
    result = Pst.resolve_ctx(project)
    assert_equal [], result
  end

  def test_returns_empty_when_org_empty
    project = { org: '', name: 'great-grants', stacks: [] }
    result = Pst.resolve_ctx(project)
    assert_equal [], result
  end

  def test_returns_empty_when_name_empty
    project = { org: 'servant-io', name: '', stacks: [] }
    result = Pst.resolve_ctx(project)
    assert_equal [], result
  end

  def test_matches_project_docs_sorted_newest_first
    write_doc('servant-io', 'great-grants-20260101-notes.md', '2026-01-01', 'great-grants')
    write_doc('servant-io', 'great-grants-20260215-prd.md',   '2026-02-15', 'great-grants', 'prd')
    write_doc('servant-io', 'great-grants-20260310-sow.md',   '2026-03-10', 'great-grants', 'sow')

    project = { org: 'servant-io', name: 'great-grants', stacks: [] }
    docs = Pst.resolve_ctx(project)

    assert_equal 3, docs.length
    dates = docs.map { |d| d[:fm]['date'] }
    assert_equal ['2026-03-10', '2026-02-15', '2026-01-01'], dates
  end

  def test_excludes_other_project_docs
    write_doc('servant-io', 'great-grants-20260101-notes.md', '2026-01-01', 'great-grants')
    write_doc('servant-io', 'other-project-20260101-notes.md', '2026-01-01', 'other-project')

    project = { org: 'servant-io', name: 'great-grants', stacks: [] }
    docs = Pst.resolve_ctx(project)

    assert_equal 1, docs.length
    assert_equal 'great-grants', docs.first[:fm]['project']
  end

  def test_caps_at_three_project_docs
    (1..5).each do |i|
      write_doc('servant-io', "great-grants-2026010#{i}-notes.md", "2026-01-0#{i}", 'great-grants')
    end

    project = { org: 'servant-io', name: 'great-grants', stacks: [] }
    docs = Pst.resolve_ctx(project)

    # _org.md absent so result is just the 3 most recent project docs
    assert_equal 3, docs.length
  end

  def test_appends_org_md_when_present
    write_doc('servant-io', 'great-grants-20260101-notes.md', '2026-01-01', 'great-grants')

    # Write _org.md
    org_dir = make_org_dir('servant-io')
    org_md  = File.join(org_dir, '_org.md')
    File.write(org_md, "---\norg: servant-io\ntype: ref\ndate: 2026-01-01\n---\n\nOrg notes.")

    project = { org: 'servant-io', name: 'great-grants', stacks: [] }
    docs = Pst.resolve_ctx(project)

    assert_equal 2, docs.length
    assert_equal org_md, docs.last[:path]
  end

  def test_returns_only_org_md_when_no_project_docs
    org_dir = make_org_dir('servant-io')
    org_md  = File.join(org_dir, '_org.md')
    File.write(org_md, "---\norg: servant-io\ntype: ref\ndate: 2026-01-01\n---\n\nOrg notes.")

    project = { org: 'servant-io', name: 'great-grants', stacks: [] }
    docs = Pst.resolve_ctx(project)

    assert_equal 1, docs.length
    assert_equal org_md, docs.first[:path]
  end

  def test_date_tiebreaker_sorts_by_filename
    make_org_dir('servant-io')
    org = 'servant-io'
    # Two docs with the same date -- should sort by filename (alphabetically, reversed)
    write_doc(org, 'great-grants-20260101-aaa.md', '2026-01-01', 'great-grants', 'notes', 'A')
    write_doc(org, 'great-grants-20260101-zzz.md', '2026-01-01', 'great-grants', 'notes', 'Z')

    project = { org: org, name: 'great-grants', stacks: [] }
    docs = Pst.resolve_ctx(project)

    assert_equal 2, docs.length
    # After reverse, 'zzz' should come before 'aaa' (higher filename sorts first)
    assert File.basename(docs.first[:path]) > File.basename(docs.last[:path])
  end

  def test_graceful_when_ctx_root_absent_no_raise
    project = { org: 'nonexistent-org', name: 'nonexistent-project', stacks: [] }
    # Should not raise, returns []
    result = Pst.resolve_ctx(project)
    assert_equal [], result
  end
end

class TestCtxWhichOutput < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('pst_which_test')
    @orig_home_env = ENV['HOME']
    ENV['HOME'] = @tmpdir
  end

  def teardown
    ENV['HOME'] = @orig_home_env
    FileUtils.rm_rf(@tmpdir)
  end

  def test_which_returns_compact_index_format
    org_dir = File.join(@tmpdir, '.ctx', 'orgs', 'acme')
    FileUtils.mkdir_p(org_dir)
    doc_path = File.join(org_dir, 'widgets-20260101-prd.md')
    File.write(doc_path, "---\norg: acme\nproject: widgets\ntype: prd\ndate: 2026-01-01\n---\n\nThe widgets PRD.")

    project = { org: 'acme', name: 'widgets', stacks: ['typescript'] }
    docs = Pst.resolve_ctx(project)

    refute_empty docs
    assert_equal 'prd', docs.first[:fm]['type']
    assert_equal '2026-01-01', docs.first[:fm]['date']

    excerpt = Pst.ctx_body_excerpt(docs.first[:path])
    assert_includes excerpt, 'widgets PRD'
  end
end
