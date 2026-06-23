# frozen_string_literal: true
# Shared helpers for the PST session-scoped hooks. Installed alongside the hook
# bodies in ~/.claude/pst/bin and loaded with require_relative. Keep this free of
# the literal em dash glyph (use Pst::EM).
require 'json'
require 'fileutils'
require 'open3'
require 'timeout'
require 'yaml'

module Pst
  EM = [0x2014].pack('U') # em dash (long dash); built so no literal glyph appears
  HOME = File.expand_path('~/.claude/pst')

  module_function

  # Parse the hook JSON payload from stdin once, memoized. Empty hash on error.
  def payload
    @payload ||= begin
      JSON.parse($stdin.read)
    rescue StandardError
      {}
    end
  end

  def session_id
    payload['session_id'].to_s
  end

  def armed?(sid = session_id)
    !sid.empty? && File.exist?(File.join(HOME, 'armed', sid))
  end

  def allow!
    exit 0
  end

  # Signal a PreToolUse deny and exit. Reason must not contain an em dash.
  # exit 2 blocks the tool call; stderr is surfaced to Claude as the error.
  def deny!(reason)
    $stderr.puts reason
    exit 2
  end

  def reviewed_dir
    File.join(HOME, 'reviewed')
  end

  def reviewed?(sha)
    !sha.to_s.empty? && File.exist?(File.join(reviewed_dir, sha))
  end

  def mark_reviewed(sha)
    return if sha.to_s.empty?

    FileUtils.mkdir_p(reviewed_dir)
    FileUtils.touch(File.join(reviewed_dir, sha))
  end

  def local_dir
    File.join(HOME, 'local')
  end

  # Merge mode 4: this session may not mutate remote GitHub state.
  def local_only?(sid = session_id)
    !sid.to_s.empty? && File.exist?(File.join(local_dir, sid))
  end

  # Run a git command in `dir` with a 10-second timeout.
  # Returns the trimmed stdout/stderr string on success, or `default:` on any
  # failure (non-zero exit, timeout, StandardError).
  def git_capture(dir, *git_args, default:)
    resolved = dir && File.directory?(dir) ? dir : Dir.pwd
    out, st = Timeout.timeout(10) { Open3.capture2e('git', '-C', resolved, *git_args) }
    st.success? ? out.strip : default
  rescue StandardError
    default
  end

  # Default branch for the repo at `dir`, resolved from origin/HEAD.
  # Falls back to "main" on any failure.
  def default_branch(dir)
    ref = git_capture(dir, 'symbolic-ref', 'refs/remotes/origin/HEAD', default: '')
    return 'main' if ref.empty?

    ref.split('/').last
  end

  # Current checked-out branch name at `dir`, or '' on failure/detached HEAD.
  def current_branch(dir)
    git_capture(dir, 'rev-parse', '--abbrev-ref', 'HEAD', default: '')
  end

  # Read an integer counter from a file; return 0 on missing or unreadable file.
  def read_counter(path)
    File.read(path).to_i
  rescue StandardError
    0
  end

  # Reap tracked Docker containers for a session (rule 20).
  # Record format: name<TAB>port<TAB>subdomain (legacy bare names also supported).
  # Skips reaping when PST_KEEP_DOCKER=1.
  def reap_docker(sid)
    return if ENV['PST_KEEP_DOCKER'] == '1'

    docker_file = File.join(HOME, 'docker', sid)
    return unless File.exist?(docker_file)

    records = File.readlines(docker_file, chomp: true).uniq.reject(&:empty?)
    records.each do |rec|
      name = rec.split("\t", 3).first
      system('docker', 'stop', name, out: File::NULL, err: File::NULL)
      system('docker', 'rm',   name, out: File::NULL, err: File::NULL)
    end
    FileUtils.rm_f(docker_file)
  end

  IN_FLIGHT_STATUSES = %w[pending running].freeze

  def ledger_path(sid = session_id)
    File.join(HOME, 'ledger', "#{sid}.json")
  end

  # Read and parse a ledger file by path. Empty array on missing or corrupt file.
  # Single source of ledger-read behavior shared by the CLI and the hooks so
  # neither side reimplements the on-disk schema knowledge.
  def read_entries(path)
    return [] unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue StandardError
    []
  end

  def load_ledger(sid = session_id)
    read_entries(ledger_path(sid))
  end

  def in_flight_count(sid = session_id)
    load_ledger(sid).count { |e| IN_FLIGHT_STATUSES.include?(e['status']) }
  end

  STACK_DEPS = {
    'typescript' => [], 'ruby' => [], 'docker' => [], 'terraform' => [],
    'react' => ['typescript'], 'rails' => ['ruby'],
    'nextjs' => ['react', 'typescript'], 'aws' => ['terraform']
  }.freeze

  VALID_STACKS = STACK_DEPS.keys.freeze

  def topo_sort_stacks(list)
    input = (list & VALID_STACKS).uniq
    with_deps = input.flat_map { |s| [s] + (STACK_DEPS[s] || []) }.uniq
    ordered = []
    remaining = with_deps.dup
    max_iter = remaining.size * remaining.size + 1
    iter = 0
    until remaining.empty?
      iter += 1
      break if iter > max_iter
      node = remaining.find { |n| (STACK_DEPS[n] || []).all? { |d| ordered.include?(d) } }
      break unless node
      ordered << node
      remaining.delete(node)
    end
    ordered
  end

  def normalize_repo(path)
    File.expand_path(path.to_s.sub(/\A~/, Dir.home))
  rescue StandardError
    path.to_s
  end

  def load_global_projects
    path = File.join(HOME, 'projects.json')
    return [] unless File.exist?(path)
    data = JSON.parse(File.read(path))
    Array(data['projects'])
  rescue StandardError
    []
  end

  def find_local_project(dir)
    current = File.expand_path(dir.to_s)
    100.times do
      candidate = File.join(current, '.pst', 'project.json')
      return JSON.parse(File.read(candidate)) if File.exist?(candidate)
      parent = File.dirname(current)
      break if parent == current
      current = parent
    end
    nil
  rescue StandardError
    nil
  end

  def git_root(dir)
    out, st = Timeout.timeout(5) do
      Open3.capture2e('git', '-C', dir.to_s, 'rev-parse', '--git-common-dir')
    end
    return dir unless st.success?
    common_dir = out.strip
    if common_dir.end_with?('/.git') || common_dir == '.git'
      File.dirname(File.expand_path(common_dir, dir))
    else
      dir
    end
  rescue StandardError
    dir
  end

  def resolve_project(dir)
    cwd = File.expand_path(dir.to_s)
    root = git_root(cwd)

    # Repo-local wins
    local = find_local_project(cwd)
    if local && local['name'] && local['stacks']
      return { name: local['name'], org: local['org'].to_s, stacks: topo_sort_stacks(Array(local['stacks'])), source: 'local' }
    end

    # User-global fallback
    load_global_projects.each do |proj|
      repos = Array(proj['repos']).map { |r| normalize_repo(r) }
      if repos.any? { |r| cwd.start_with?(r) || root.start_with?(r) }
        return { name: proj['name'], org: proj['org'].to_s, stacks: topo_sort_stacks(Array(proj['stacks'])), source: 'global' }
      end
    end

    nil
  end

  def detect_stacks(dir)
    stacks = []
    pkg = File.join(dir, 'package.json')
    if File.exist?(pkg)
      stacks << 'typescript'
      begin
        pkg_data = JSON.parse(File.read(pkg))
        deps = (pkg_data['dependencies'] || {}).merge(pkg_data['devDependencies'] || {})
        stacks << 'react' if deps.key?('react')
        stacks << 'nextjs' if deps.key?('next')
      rescue StandardError
      end
    end
    gemfile = File.join(dir, 'Gemfile')
    if File.exist?(gemfile)
      stacks << 'ruby'
      content = File.read(gemfile) rescue ''
      stacks << 'rails' if content.match?(/gem ['"]rails['"]/)
    end
    stacks << 'docker' if File.exist?(File.join(dir, 'Dockerfile')) ||
                          Dir.glob(File.join(dir, 'compose.{yml,yaml}')).any? ||
                          Dir.glob(File.join(dir, 'docker-compose.{yml,yaml}')).any?
    tf_files = Dir.glob(File.join(dir, '*.tf'))
    if tf_files.any?
      stacks << 'terraform'
      tf_content = tf_files.map { |f| File.read(f) rescue '' }.join
      stacks << 'aws' if tf_content.match?(/provider\s+["']aws["']/)
    end
    topo_sort_stacks(stacks.uniq)
  end

  def resolve_ctx(project_config)
    org  = project_config[:org].to_s
    name = project_config[:name].to_s
    return [] if org.empty? || name.empty?

    ctx_root = File.expand_path('~/.ctx')
    org_dir  = File.join(ctx_root, 'orgs', org)
    return [] unless File.directory?(org_dir)

    # Scan live (not index.json) so new files appear without rebuild-index
    docs = []

    # Project-scoped docs: any .md whose frontmatter project matches name
    Dir.glob(File.join(org_dir, '*.md')).each do |path|
      fm = parse_ctx_frontmatter(path)
      next unless fm
      next if File.basename(path) == '_org.md'
      next unless fm['project'].to_s == name
      docs << { path: path, fm: fm }
    end

    # Sort by date desc, filename as tiebreaker for determinism
    docs.sort_by! { |d| [d[:fm]['date'].to_s, File.basename(d[:path])] }
    docs.reverse!

    # Up to 3 most recent project docs
    result = docs.first(3)

    # Append _org.md if present
    org_md = File.join(org_dir, '_org.md')
    if File.exist?(org_md)
      fm = parse_ctx_frontmatter(org_md)
      result << { path: org_md, fm: fm || {} }
    end

    result
  rescue StandardError
    []
  end

  def parse_ctx_frontmatter(path)
    content = File.read(path, encoding: 'utf-8')
    return nil unless content.start_with?('---')
    end_idx = content.index("\n---", 3)
    return nil unless end_idx
    fm = YAML.safe_load(content[3..end_idx], permitted_classes: [Date, Time])
    return nil unless fm.is_a?(Hash)
    # Normalize Date/Time objects to strings so callers get plain strings
    fm.transform_values { |v| v.is_a?(Date) || v.is_a?(Time) ? v.to_s : v }
  rescue StandardError
    nil
  end

  def ctx_body_excerpt(path, chars = 280)
    content = File.read(path, encoding: 'utf-8')
    body = if content.start_with?('---')
      end_idx = content.index("\n---", 3)
      end_idx ? content[(end_idx + 4)..].lstrip : content
    else
      content
    end
    excerpt = body.gsub(/\s+/, ' ').strip
    excerpt.length > chars ? excerpt[0, chars] + '...' : excerpt
  rescue StandardError
    ''
  end

end
