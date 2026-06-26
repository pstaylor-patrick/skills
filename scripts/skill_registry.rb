#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

# Loads auto-firing skills from a skills directory and answers which ones apply
# to a changed file or to the current project. A skill opts into auto-firing by
# carrying an `auto:` block in its SKILL.md frontmatter; skills without one (the
# plain user-invocable kind) are ignored here. Everything fails silent: a bad
# manifest yields no skill, never a crash, because this runs inside hooks.
module SkillRegistry
  # What `all_code: true` matches. Centralized so a code-wide skill declares
  # intent (`all_code`) instead of re-listing extensions in its frontmatter.
  CODE_EXTENSIONS = %w[
    rb rake gemspec ru py js jsx mjs cjs ts tsx mts cts go rs java kt kts c h cc cpp hpp
    cs php swift scala clj cljs ex exs erl hs ml sh bash zsh sql lua dart groovy
    r jl vue svelte
  ].freeze

  # fnmatch flags for `paths` rules. PATHNAME keeps * and ? inside one path
  # segment (so `.github/workflows/*.yml` cannot leak across directories);
  # EXTGLOB enables `{yml,yaml}`; DOTMATCH lets a glob cross dot-dirs like
  # `.github`. Centralized so per-file glob matching stays consistent.
  PATH_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

  # The runtime install lives at ~/.claude/skills; from a hook in
  # ~/.claude/pst/bin that is two levels up. Tests pass an explicit dir.
  def self.default_dir = File.expand_path('../../skills', __dir__)

  def self.load(dir = default_dir)
    Dir.glob(File.join(dir, '*', 'SKILL.md')).filter_map { |path| Skill.parse(path) }
  end

  # One auto-firing skill: its match rules plus the body to surface.
  class Skill
    def self.parse(path)
      front, body = Frontmatter.split(File.read(path))
      meta = front && YAML.safe_load(front)
      return unless meta.is_a?(Hash) && meta['auto'].is_a?(Hash)

      new(meta, body)
    rescue StandardError
      nil
    end

    def initialize(meta, body)
      @meta = meta
      @auto = meta['auto']
      @body = body.to_s.strip
    end

    def name = @meta['name'].to_s
    def all_code? = @auto['all_code'] == true
    def all_files? = @auto['all_files'] == true
    def body = @body

    # `root`, when given, is the project root used to evaluate `exclude`. It is
    # optional so callers without project context (the CLI, unit tests) match
    # exactly as before; only the per-edit hook passes it, and only there can a
    # conflicting stack suppress a skill.
    def matches?(path, root: nil)
      return false if root && excluded?(root)
      return true if all_files?

      base = File.basename(path.to_s)
      ext = File.extname(base).delete_prefix('.').downcase
      return true if all_code? && CODE_EXTENSIONS.include?(ext)

      extensions.include?(ext) || basenames.include?(base) || path_match?(path.to_s)
    end

    def detected?(dir)
      return false if excluded?(dir)
      return true if all_files? || all_code?

      detect.any? { |pattern| Dir.glob(File.join(dir, pattern)).any? }
    end

    private

    # A `paths` glob fires if it matches the path directly or as a suffix; the
    # "**/" prefix anchors it to any segment boundary, so one rule works for the
    # absolute paths the hook passes and the repo-relative paths the CLI passes.
    def path_match?(path)
      paths.any? do |glob|
        g = normalize(glob)
        File.fnmatch?(g, path, PATH_FLAGS) || File.fnmatch?("**/#{g}", path, PATH_FLAGS)
      end
    end

    # Ruby's fnmatch treats a trailing `**` as a single segment (unlike
    # Dir.glob), so `drizzle/**` would miss nested files; rewrite it to the
    # recursive form so the glob means what it reads as.
    def normalize(glob)
      glob.end_with?('/**') ? "#{glob}/*" : glob
    end

    # Suppression signal: any project file matching an `exclude` glob means a
    # conflicting stack is present, so this skill does not apply. An empty
    # `exclude` (every skill today) is always false, preserving behavior.
    def excluded?(dir)
      exclude.any? { |pattern| Dir.glob(File.join(dir, pattern)).any? }
    end

    def extensions = Array(@auto['extensions']).map { |e| e.to_s.downcase }
    def basenames  = Array(@auto['basenames']).map(&:to_s)
    def detect     = Array(@auto['detect']).map(&:to_s)
    def paths      = Array(@auto['paths']).map(&:to_s)
    def exclude    = Array(@auto['exclude']).map(&:to_s)
  end

  # Splits a `---\n...\n---\n` YAML frontmatter block off the document body.
  module Frontmatter
    PATTERN = /\A---\s*\n(.*?\n)---\s*\n?(.*)\z/m

    def self.split(text)
      match = text.match(PATTERN)
      match ? [ match[1], match[2] ] : [ nil, text ]
    end
  end
end
