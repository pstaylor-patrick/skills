#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'review_queue'

# The fixed review instructions handed to the agent when review-eligible files
# changed. Extracted from skill_review so both consumers - the Stop-hook driver
# (skill_review) and the pre-PR gate (review_gate) - emit identical text from one
# source.
module ReviewPrompt
  module_function

  def build(entries, registry)
    by_name = registry.to_h { |skill| [ skill.name, skill ] }
    sections = entries.group_by { |entry| entry[:skill] }
                      .map { |name, rows| section(by_name[name], name, rows) }
    <<~TEXT.strip
      [pst review] Before you finish: #{entries.size} file(s) changed this session
      under review-enabled skills. Spawn a background review agent now, then finish.

      Use Agent(subagent_type: "general-purpose", model: "haiku", run_in_background: true),
      giving it exactly the task below. Report only concrete violations as
      `path:line - smell -> smallest behavior-preserving fix`; if none, say "clean".
      This is a one-time review of the current batch and will not fire again.

      #{sections.join("\n\n")}
    TEXT
  end

  def cap_notice(count)
    "[pst review] Round cap (#{ReviewQueue::CAP}) reached; #{count} file(s) " \
      'still changing. Automatic design review is paused for this session; review ' \
      'remaining changes manually or invoke /pst:ruby.'
  end

  def section(skill, name, rows)
    files = rows.map { |row| "- #{row[:path]}" }.join("\n")
    <<~TEXT.strip
      ## Review against the #{name} skill
      #{taxonomy_note(skill)}
      Files:
      #{files}

      #{name} principles:
      #{skill&.body || '(principles unavailable)'}
    TEXT
  end

  # Each scope frames what the reviewer should treat as in-bounds. all_code
  # matches by extension, which can misfire on data or prose that merely looks
  # like code, so judge code-ness first. all_files is deliberately broad, so the
  # reviewer must not skip prose or documentation as "not code".
  def taxonomy_note(skill)
    return code_only_note if skill&.all_code?
    return every_file_note if skill&.all_files?

    ''
  end

  def code_only_note
    "\nFirst confirm each changed file is genuinely code (it may be code embedded " \
      "in another format). Review only real code; mark anything that is not code as clean.\n"
  end

  def every_file_note
    "\nThis skill applies to every changed file, including prose and documentation, " \
      "not just code. Review all of them.\n"
  end
end
