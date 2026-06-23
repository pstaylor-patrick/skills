#!/usr/bin/env ruby
# frozen_string_literal: true
# ctx -- business context CLI for ~/.ctx/
# Usage: ctx <verb> [args]
#   ctx add --org <slug> --project <name> --type <type> [--source <src>]
#   ctx pull
#   ctx list [<project>] [--org <slug>] [--type <type>] [--tag <tag>]
#   ctx which [--dir <path>]
#   ctx cat <file-or-partial-name>
#   ctx rebuild-index
require_relative '../hooks/pst_common'
require 'yaml'
require 'json'
require 'fileutils'
require 'date'

CTX_ROOT   = File.expand_path('~/.ctx')
ORGS_DIR   = File.join(CTX_ROOT, 'orgs')
INDEX_PATH = File.join(CTX_ROOT, 'index.json')

VALID_TYPES   = %w[prd sow retro notes thread-dump decision ref].freeze
VALID_SOURCES = %w[gdoc slack email loom manual confluence].freeze

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def orgs_dir_exists?
  File.directory?(ORGS_DIR)
end

def scan_all_docs
  return [] unless orgs_dir_exists?

  Dir.glob(File.join(ORGS_DIR, '*', '*.md')).filter_map do |path|
    fm = Pst.parse_ctx_frontmatter(path)
    { path: path, fm: fm || {} }
  end
end

def find_doc(partial)
  return partial if File.exist?(partial)
  return nil unless orgs_dir_exists?

  matches = Dir.glob(File.join(ORGS_DIR, '**', '*.md')).select do |f|
    File.basename(f).include?(partial) || f.include?(partial)
  end
  matches.length == 1 ? matches.first : matches.min_by { |f| File.basename(f).length }
end

def open_editor(path)
  editor = ENV['EDITOR'] || ENV['VISUAL'] || 'vi'
  system(editor, path)
end

def table_row(path, fm, excerpt)
  rel = path.sub(File.expand_path('~'), '~')
  type = fm['type'] || '?'
  date = fm['date'] || '?'
  printf "%-55s  %-12s  %-10s  %s\n", rel, type, date, excerpt[0, 80]
end

# ---------------------------------------------------------------------------
# Verbs
# ---------------------------------------------------------------------------

def cmd_add(args)
  opts = {}
  i = 0
  while i < args.length
    case args[i]
    when '--org'     then opts[:org]     = args[i + 1]; i += 2
    when '--project' then opts[:project] = args[i + 1]; i += 2
    when '--type'    then opts[:type]    = args[i + 1]; i += 2
    when '--source'  then opts[:source]  = args[i + 1]; i += 2
    else i += 1
    end
  end

  missing = %i[org project type].reject { |k| opts[k] }
  unless missing.empty?
    warn "ctx add: missing required options: #{missing.map { |k| "--#{k}" }.join(', ')}"
    exit 1
  end

  unless VALID_TYPES.include?(opts[:type])
    warn "ctx add: invalid type '#{opts[:type]}'. Valid: #{VALID_TYPES.join(', ')}"
    exit 1
  end

  if opts[:source] && !VALID_SOURCES.include?(opts[:source])
    warn "ctx add: invalid source '#{opts[:source]}'. Valid: #{VALID_SOURCES.join(', ')}"
    exit 1
  end

  date_str = Date.today.strftime('%Y%m%d')
  filename = "#{opts[:project]}-#{date_str}-#{opts[:type]}.md"
  org_dir  = File.join(ORGS_DIR, opts[:org])
  FileUtils.mkdir_p(org_dir)
  dest = File.join(org_dir, filename)

  fm_lines = [
    '---',
    "org: #{opts[:org]}",
    "project: #{opts[:project]}",
    "type: #{opts[:type]}",
    "date: #{Date.today.iso8601}"
  ]
  fm_lines << "source: #{opts[:source]}" if opts[:source]
  fm_lines += ['source_url: ""', 'stacks: []', 'tags: []', 'confidential: false', '---', '', '']

  File.write(dest, fm_lines.join("\n"))
  puts "ctx: created #{dest}"
  open_editor(dest)
  cmd_rebuild_index
end

def cmd_pull(_args)
  puts 'ctx pull: not yet implemented (planned for a later PR)'
  exit 0
end

def cmd_list(args)
  project_filter = nil
  org_filter     = nil
  type_filter    = nil
  tag_filter     = nil

  i = 0
  while i < args.length
    case args[i]
    when '--org'  then org_filter  = args[i + 1]; i += 2
    when '--type' then type_filter = args[i + 1]; i += 2
    when '--tag'  then tag_filter  = args[i + 1]; i += 2
    else
      project_filter = args[i] unless args[i].start_with?('--')
      i += 1
    end
  end

  unless orgs_dir_exists?
    puts 'ctx: no context found'
    return
  end

  docs = scan_all_docs
  docs.select! { |d| d[:fm]['project'] == project_filter } if project_filter
  docs.select! { |d| d[:fm]['org']     == org_filter     } if org_filter
  docs.select! { |d| d[:fm]['type']    == type_filter    } if type_filter
  docs.select! { |d| Array(d[:fm]['tags']).include?(tag_filter) } if tag_filter

  if docs.empty?
    puts 'ctx: no context found'
    return
  end

  printf "%-55s  %-12s  %-10s  %s\n", 'PATH', 'TYPE', 'DATE', 'EXCERPT'
  puts '-' * 120
  docs.sort_by { |d| [d[:fm]['date'].to_s, File.basename(d[:path])] }.reverse.each do |d|
    excerpt = Pst.ctx_body_excerpt(d[:path], 80)
    table_row(d[:path], d[:fm], excerpt)
  end
end

def cmd_which(args)
  dir = Dir.pwd
  i = 0
  while i < args.length
    if args[i] == '--dir'
      dir = args[i + 1]
      i += 2
    else
      i += 1
    end
  end

  dir = File.expand_path(dir)
  project = Pst.resolve_project(dir)
  unless project
    puts "ctx which: no project configured for #{dir}"
    return
  end

  if project[:org].to_s.empty?
    puts "ctx which: project '#{project[:name]}' has no org field -- context injection disabled"
    return
  end

  docs = Pst.resolve_ctx(project)
  if docs.empty?
    puts "ctx which: no context documents found for project '#{project[:name]}' (org: #{project[:org]})"
    return
  end

  puts "[.ctx] Project: #{project[:name]} (#{project[:org]}) | stacks: #{project[:stacks].join(', ')}"
  docs.each do |doc|
    fm   = doc[:fm] || {}
    type = fm['type'] || (File.basename(doc[:path]) == '_org.md' ? 'org' : 'doc')
    date = fm['date'] || ''
    src  = fm['source'] ? " (#{fm['source']})" : ''
    excerpt = Pst.ctx_body_excerpt(doc[:path])
    puts "\n  #{type.upcase} -- #{date}#{src}\n  \"#{excerpt}\""
  end
  puts "\nRun `ctx cat <filename>` for full text."
end

def cmd_cat(args)
  if args.empty?
    warn 'ctx cat: missing filename argument'
    exit 1
  end

  partial = args.first
  path = find_doc(partial)

  unless path
    warn "ctx cat: no document found matching '#{partial}'"
    exit 1
  end

  puts File.read(path, encoding: 'utf-8')
rescue StandardError => e
  warn "ctx cat: #{e.message}"
  exit 1
end

def cmd_rebuild_index
  unless orgs_dir_exists?
    puts 'ctx rebuild-index: no orgs directory found, nothing to index'
    return
  end

  entries = scan_all_docs.map do |d|
    d[:fm].merge('_path' => d[:path])
  end

  FileUtils.mkdir_p(CTX_ROOT)
  File.write(INDEX_PATH, JSON.pretty_generate(entries))
  puts "ctx rebuild-index: indexed #{entries.length} document(s) -> #{INDEX_PATH}"
end

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

verb = ARGV.shift
case verb
when 'add'           then cmd_add(ARGV)
when 'pull'          then cmd_pull(ARGV)
when 'list'          then cmd_list(ARGV)
when 'which'         then cmd_which(ARGV)
when 'cat'           then cmd_cat(ARGV)
when 'rebuild-index' then cmd_rebuild_index
when nil, '--help', 'help'
  puts <<~USAGE
    ctx -- business context CLI

    Verbs:
      ctx add --org <slug> --project <name> --type <type> [--source <src>]
      ctx pull
      ctx list [<project>] [--org <slug>] [--type <type>] [--tag <tag>]
      ctx which [--dir <path>]
      ctx cat <file-or-partial-name>
      ctx rebuild-index

    Types: #{VALID_TYPES.join(', ')}
    Sources: #{VALID_SOURCES.join(', ')}
  USAGE
else
  warn "ctx: unknown verb '#{verb}'. Run `ctx help` for usage."
  exit 1
end
