#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'hook_event'
require_relative 'skill_registry'
require_relative 'review_queue'
require_relative 'review_prompt'
require_relative 'guarded_command'

# PreToolUse hook: when the agent is about to push or open a PR and
# review-eligible files changed this session that have not been reviewed, deny
# the command and hand back the review prompt. This makes design review precede
# PR creation; the Stop hook (skill_review) fires too late, once the PR already
# exists. Local-only sessions never push, so skill_review still covers them at
# Stop; both share one ReviewQueue, and whichever drains first marks the batch
# reviewed, so the retried command passes without a second review.
#
# Like merge_mode_guard, this is a loud guardrail keyed on command text, not a
# sandbox: it is bypassable (git -c, env indirection, a non-Bash path).
class ReviewGate
  EVENT = 'PreToolUse'

  PR_CREATE = /\bgh\b[^&|;]*\bpr\b[^&|;]*\bcreate\b/
  TRIGGER = Regexp.union(GuardedCommand::PUSH, PR_CREATE)

  def initialize(event, skills: nil)
    @event = event
    @skills = skills
  end

  # Mirrors skill_review's order so both consumers behave identically: drain the
  # batch, mark it reviewed (so the retry and the other event find nothing), then
  # block, or surface the cap notice once the round cap is hit.
  def emit(io = $stdout)
    return unless @event['tool_name'] == 'Bash'
    return unless command.match?(TRIGGER)

    queue = ReviewQueue.new(@event['session_id'])
    entries = queue.drain
    return if entries.empty?

    queue.mark_reviewed(entries)
    io.puts(JSON.generate(response(queue, entries)))
  end

  private

  def registry = @skills ||= SkillRegistry.load

  def command
    input = @event['tool_input']
    input.is_a?(Hash) ? input['command'].to_s : ''
  end

  def response(queue, entries)
    return { systemMessage: ReviewPrompt.cap_notice(entries.size) } if queue.capped?

    queue.bump_round
    deny(ReviewPrompt.build(entries, registry))
  end

  def deny(reason)
    {
      hookSpecificOutput: {
        hookEventName: EVENT,
        permissionDecision: 'deny',
        permissionDecisionReason: reason
      }
    }
  end
end

ReviewGate.new(HookEvent.read).emit if __FILE__ == $PROGRAM_NAME
