#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

# Enforces the size budgets Anthropic publishes for SKILL.md in "Skill authoring
# best practices" (platform.claude.com/docs/en/agents-and-tools/agent-skills/
# best-practices). Each limit is checked in the unit the doc states it in:
#
#   - body:        under 500 lines  ("Keep SKILL.md body under 500 lines")
#   - name:        <= 64 characters
#   - description: <= 1024 characters
#
# Lines is the documented metric for the body and what we gate on. It is gameable
# by packing many words onto one line, but a SKILL.md authored that way fails the
# rubocop/glyph passes and review long before it reaches here, so a second
# token/word budget would be an unsourced "voodoo constant". When Anthropic
# publishes a token figure, add it here.
class SkillLengthTest < Minitest::Test
  REPO_SKILLS = File.expand_path("../skills", __dir__)

  MAX_BODY_LINES = 500
  MAX_NAME_CHARS = 64
  MAX_DESCRIPTION_CHARS = 1024

  def skill_files
    Dir.glob(File.join(REPO_SKILLS, "*", "SKILL.md")).sort
  end

  # Returns [frontmatter_hash, body_string] for a SKILL.md, splitting on the
  # leading `---` fenced YAML block.
  def parse(path)
    text = File.read(path)
    match = text.match(/\A---\n(?<front>.*?)\n---\n(?<body>.*)\z/m)
    refute_nil match, "#{rel(path)}: missing YAML frontmatter fenced by ---"
    [ YAML.safe_load(match[:front]), match[:body] ]
  end

  def rel(path)
    path.delete_prefix("#{File.dirname(REPO_SKILLS)}/")
  end

  # Yields [frontmatter_hash, body_string, relative_path] for every shipped skill.
  def each_skill
    skill_files.each do |path|
      front, body = parse(path)
      yield front, body, rel(path)
    end
  end

  def test_every_skill_has_a_skill_file
    refute_empty skill_files, "no skills/*/SKILL.md found"
  end

  def test_body_under_500_lines
    each_skill do |_, body, rel|
      lines = body.lines.count
      assert_operator lines, :<=, MAX_BODY_LINES,
                      "#{rel}: body is #{lines} lines, over the #{MAX_BODY_LINES}-line budget. " \
                      "Split detail into reference files (progressive disclosure)."
    end
  end

  def test_name_within_64_chars
    each_skill do |front, _, rel|
      name = front["name"].to_s
      assert_operator name.length, :<=, MAX_NAME_CHARS,
                      "#{rel}: name is #{name.length} chars, over the #{MAX_NAME_CHARS}-char limit."
    end
  end

  def test_description_within_1024_chars
    each_skill do |front, _, rel|
      desc = front["description"].to_s
      refute_empty desc, "#{rel}: description is empty"
      assert_operator desc.length, :<=, MAX_DESCRIPTION_CHARS,
                      "#{rel}: description is #{desc.length} chars, over the #{MAX_DESCRIPTION_CHARS}-char limit."
    end
  end
end
