# frozen_string_literal: true

require_relative "test_helpers"
require_relative "../scripts/review_gate"

class ReviewGateTest < Minitest::Test
  include SkillTempHome
  include SkillFactory

  def setup
    super
    @skills = Dir.mktmpdir
    skill_dir("ruby", auto: { "extensions" => [ "rb" ] }, body: "POODR-PRINCIPLES")
  end

  def teardown
    FileUtils.remove_entry(@skills)
    super
  end

  def gate(command, session: "s1", tool: "Bash")
    io = StringIO.new
    event = { "session_id" => session, "tool_name" => tool, "tool_input" => { "command" => command } }
    ReviewGate.new(event, skills: SkillRegistry.load(@skills)).emit(io)
    io.string.empty? ? nil : JSON.parse(io.string)
  end

  def enqueue(session: "s1", path: "/p/user.rb", hash: "h1")
    ReviewQueue.new(session).add("ruby", path, hash)
  end

  def decision(out)
    out&.dig("hookSpecificOutput", "permissionDecision")
  end

  def test_denies_push_when_batch_unreviewed
    enqueue
    out = gate("git push -u origin feat/x")
    assert_equal "deny", decision(out)
    reason = out.dig("hookSpecificOutput", "permissionDecisionReason")
    assert_includes reason, "/p/user.rb"
    assert_includes reason, "POODR-PRINCIPLES"
  end

  def test_denies_pr_create_when_batch_unreviewed
    enqueue
    assert_equal "deny", decision(gate("gh pr create --fill"))
  end

  def test_allows_when_queue_empty
    assert_nil gate("git push")
  end

  def test_allows_non_trigger_command
    enqueue
    assert_nil gate("git status")
    assert_nil gate("git commit -m x")
  end

  def test_allows_non_bash_tool
    enqueue
    assert_nil gate("git push", tool: "Edit")
  end

  def test_fires_once_per_batch_then_allows_retry
    enqueue
    assert_equal "deny", decision(gate("git push")), "first push blocks for review"
    assert_nil gate("git push"), "batch drained and marked; retry passes"
  end

  def test_capped_surfaces_notice_instead_of_denying
    ReviewQueue::CAP.times do |i|
      enqueue(path: "/p/f#{i}.rb", hash: "h#{i}")
      assert_equal "deny", decision(gate("git push")), "round #{i + 1} blocks"
    end
    enqueue(path: "/p/extra.rb", hash: "hx")
    out = gate("git push")
    assert_nil decision(out), "must not deny once capped"
    assert_includes out["systemMessage"], "Round cap"
  end

  def test_does_not_double_review_with_stop_hook
    enqueue
    assert_equal "deny", decision(gate("git push")), "gate drains the batch"
    stop = StringIO.new
    SkillReview.new({ "session_id" => "s1" }, skills: SkillRegistry.load(@skills)).emit(stop)
    assert_empty stop.string, "Stop finds an empty queue after the gate drained it"
  end
end
