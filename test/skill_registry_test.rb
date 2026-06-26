# frozen_string_literal: true

require_relative "test_helpers"

class SkillRegistryTest < Minitest::Test
  include SkillFactory

  def setup
    @skills = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@skills)
  end

  def load = SkillRegistry.load(@skills)

  def test_loads_only_skills_with_an_auto_block
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    plain_skill("pst")
    assert_equal [ "ruby" ], load.map(&:name)
  end

  def test_matches_by_extension_case_insensitively
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    skill = load.first
    assert skill.matches?("/proj/lib/foo.RB")
    refute skill.matches?("/proj/README.md")
  end

  def test_matches_by_basename
    skill_dir("ruby", auto: { "extensions" => [ "rb" ], "basenames" => [ "Rakefile" ] })
    assert load.first.matches?("/proj/Rakefile")
  end

  def test_detected_by_marker_file
    skill_dir("ruby", auto: { "detect" => [ "Gemfile", "*.gemspec" ] })
    proj = Dir.mktmpdir
    refute load.first.detected?(proj)
    FileUtils.touch(File.join(proj, "Gemfile"))
    assert load.first.detected?(proj)
  ensure
    FileUtils.remove_entry(proj)
  end

  def test_all_code_matches_code_but_not_prose
    skill_dir("refactoring", auto: { "all_code" => true })
    skill = load.first
    assert skill.matches?("/proj/main.go")
    assert skill.matches?("/proj/app.py")
    refute skill.matches?("/proj/README.md")
    refute skill.matches?("/proj/data.json")
  end

  def test_all_files_matches_every_type
    skill_dir("ai-slop", auto: { "all_files" => true })
    skill = load.first
    assert skill.matches?("/proj/notes.md")
    assert skill.matches?("/proj/app.py")
    assert skill.matches?("/proj/Dockerfile")
    assert skill.matches?("/proj/lib/foo.rb")
  end

  def test_all_code_and_all_files_are_always_detected
    skill_dir("refactoring", auto: { "all_code" => true })
    skill_dir("ai-slop", auto: { "all_files" => true })
    by_name = load.to_h { |s| [ s.name, s ] }
    assert by_name["refactoring"].detected?(Dir.mktmpdir)
    assert by_name["ai-slop"].detected?(Dir.mktmpdir)
  end

  def test_scope_flags_do_not_leak_to_extension_skills
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    refute load.first.matches?("/proj/README.md")
  end

  def test_malformed_skill_is_skipped_not_fatal
    dir = File.join(@skills, "broken")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "SKILL.md"), "---\n: : not yaml :\n---\nbody")
    assert_equal [], load
  end

  def test_shipped_skills_declare_intended_scope
    by_name = SkillRegistry.load(REPO_SKILLS).to_h { |s| [ s.name, s ] }
    assert by_name["pst:ruby"].matches?("app/models/user.rb")
    assert by_name["pst:refactoring"].all_code?
    assert by_name["pst:refactoring"].matches?("src/main.go")
    refute by_name["pst:refactoring"].matches?("docs/notes.md")
    assert by_name["pst:ai-slop"].all_files?
    assert by_name["pst:ai-slop"].matches?("docs/notes.md")
    assert by_name["pst:ai-slop"].matches?("app/models/user.rb")
  end

  # Builds a throwaway project dir holding the given relative files (parents
  # created, contents empty) and returns its path; the caller removes it.
  def project_with(*relpaths)
    dir = Dir.mktmpdir
    relpaths.each do |rel|
      full = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(full))
      FileUtils.touch(full)
    end
    dir
  end

  def test_paths_glob_matches_nested_basename
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ] })
    skill = load.first
    assert skill.matches?("/p/src/db/schema.ts")
    refute skill.matches?("/p/src/db/schema.prisma")
    refute skill.matches?("/p/schemas.ts")
  end

  def test_paths_glob_directory_recursive
    skill_dir("drizzle", auto: { "paths" => [ "drizzle/**" ] })
    skill = load.first
    assert skill.matches?("/p/drizzle/0000.sql")
    assert skill.matches?("/p/drizzle/meta/snap.json")
    refute skill.matches?("/p/src/x.sql")
  end

  def test_paths_glob_anchored_to_directory
    skill_dir("gha", auto: { "paths" => [ ".github/workflows/*.yml" ] })
    skill = load.first
    assert skill.matches?("/p/.github/workflows/ci.yml")
    assert skill.matches?("/p/pkg/.github/workflows/ci.yml")
    refute skill.matches?("/p/docker-compose.yml")
    refute skill.matches?("/p/.github/workflows/sub/ci.yml")
  end

  def test_paths_glob_extglob_brace
    skill_dir("gha", auto: { "paths" => [ ".github/workflows/*.{yml,yaml}" ] })
    skill = load.first
    assert skill.matches?("/p/.github/workflows/ci.yaml")
    assert skill.matches?("/p/.github/workflows/ci.yml")
  end

  def test_paths_glob_matches_relative_path
    skill_dir("drizzle", auto: { "paths" => [ "src/**/db.ts" ] })
    assert load.first.matches?("src/server/db.ts")
  end

  def test_paths_compose_with_extensions_as_or
    skill_dir("drizzle", auto: { "extensions" => [ "sql" ], "paths" => [ "drizzle/**" ] })
    skill = load.first
    assert skill.matches?("/p/migrations/x.sql")
    assert skill.matches?("/p/drizzle/meta.json")
    refute skill.matches?("/p/app.ts")
  end

  def test_paths_absent_is_backward_compatible
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] })
    refute load.first.matches?("/p/README.md")
  end

  def test_exclude_suppresses_match_when_root_given
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ], "exclude" => [ "**/schema.prisma" ] })
    skill = load.first
    proj = project_with("prisma/schema.prisma", "src/schema.ts")
    refute skill.matches?(File.join(proj, "src/schema.ts"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_exclude_is_inert_without_root
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ], "exclude" => [ "**/schema.prisma" ] })
    assert load.first.matches?("/p/src/schema.ts")
  end

  def test_exclude_does_not_suppress_when_marker_absent
    skill_dir("drizzle", auto: { "paths" => [ "**/schema.ts" ], "exclude" => [ "**/schema.prisma" ] })
    skill = load.first
    proj = project_with("src/schema.ts")
    assert skill.matches?(File.join(proj, "src/schema.ts"), root: proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_detected_honors_exclude
    skill_dir("drizzle", auto: { "detect" => [ "drizzle.config.ts" ], "exclude" => [ "**/schema.prisma" ] })
    skill = load.first
    conflict = project_with("drizzle.config.ts", "prisma/schema.prisma")
    clean = project_with("drizzle.config.ts")
    refute skill.detected?(conflict)
    assert skill.detected?(clean)
  ensure
    FileUtils.remove_entry(conflict) if conflict
    FileUtils.remove_entry(clean) if clean
  end

  def test_empty_exclude_leaves_detect_unchanged
    skill_dir("ruby", auto: { "detect" => [ "Gemfile" ] })
    skill = load.first
    proj = project_with("Gemfile")
    assert skill.detected?(proj)
  ensure
    FileUtils.remove_entry(proj) if proj
  end

  def test_shipped_drizzle_fires_on_drizzle_files_only
    by_name = SkillRegistry.load(REPO_SKILLS).to_h { |s| [ s.name, s ] }
    drizzle = by_name["pst:drizzle"]
    assert drizzle.matches?("src/db/schema.ts")
    assert drizzle.matches?("drizzle.config.ts")
    refute drizzle.matches?("src/components/Button.tsx")
  end

  def test_shipped_drizzle_suppressed_in_prisma_project
    drizzle = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:drizzle" }
    prisma = project_with("prisma/schema.prisma", "src/db/schema.ts")
    real = project_with("drizzle.config.ts", "src/db/schema.ts")
    refute drizzle.matches?(File.join(prisma, "src/db/schema.ts"), root: prisma)
    assert drizzle.matches?(File.join(real, "src/db/schema.ts"), root: real)
  ensure
    FileUtils.remove_entry(prisma) if prisma
    FileUtils.remove_entry(real) if real
  end

  def test_shipped_github_actions_fires_on_workflows_only
    gha = SkillRegistry.load(REPO_SKILLS).find { |s| s.name == "pst:github-actions" }
    assert gha.matches?(".github/workflows/ci.yml")
    refute gha.matches?("docker-compose.yml")
    refute gha.matches?("config/app.yaml")
  end
end
