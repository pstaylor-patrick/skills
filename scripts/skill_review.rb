#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'hook_event'
require_relative 'skill_registry'
require_relative 'review_queue'
require_relative 'review_prompt'

# Stop hook: when the turn ends, if review-enabled files changed this session,
# block once and hand the agent a fixed prompt to run a haiku background review.
# Draining the queue (and honoring stop_hook_active) guarantees it fires once
# per batch, never in a loop. The hook authors the prompt; the agent runs the
# review via Claude Code's real background-agent mechanism.
class SkillReview
  EVENT = 'Stop'

  def initialize(event, skills: nil)
    @event = event
    @skills = skills
  end

  def emit(io = $stdout)
    return if @event['stop_hook_active']

    queue = ReviewQueue.new(@event['session_id'])
    entries = queue.drain
    return if entries.empty?

    queue.mark_reviewed(entries)
    io.puts(JSON.generate(response(queue, entries)))
  end

  private

  def registry = @skills ||= SkillRegistry.load

  # Block to drive a review, unless the round cap is reached: then surface a
  # loud, non-blocking notice rather than silently swallowing further reviews.
  def response(queue, entries)
    return { systemMessage: ReviewPrompt.cap_notice(entries.size) } if queue.capped?

    queue.bump_round
    { decision: 'block', reason: ReviewPrompt.build(entries, registry) }
  end
end

SkillReview.new(HookEvent.read).emit if __FILE__ == $PROGRAM_NAME
