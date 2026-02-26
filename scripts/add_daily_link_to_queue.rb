#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "uri"
require "yaml"

QUEUE_FILE = "_data/daily_links_queue.yml"
DAILY_FILE = "_data/daily_links.yml"
ALLOWED_TYPES = %w[article video tool].freeze

def usage!
  warn "Usage: ruby scripts/add_daily_link_to_queue.rb --title \"...\" --url \"...\" --description \"...\" --type article|video|tool [--date YYYY-MM-DD]"
  exit 1
end

def parse_args(argv)
  args = {}
  i = 0
  while i < argv.length
    key = argv[i]
    val = argv[i + 1]

    unless key.start_with?("--") && !val.nil?
      usage!
    end

    args[key.delete_prefix("--")] = val
    i += 2
  end
  args
end

def validate_url!(url)
  uri = URI.parse(url)
  unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
    raise ArgumentError, "Invalid URL. Use a full http/https URL."
  end
end

def validate_date!(value)
  Date.iso8601(value).strftime("%Y-%m-%d")
rescue Date::Error
  raise ArgumentError, "Invalid date '#{value}'. Use YYYY-MM-DD."
end

def load_items(path)
  return [] unless File.exist?(path)

  raw = YAML.safe_load_file(path, permitted_classes: [Date], aliases: false)
  raw.is_a?(Array) ? raw : []
end

begin
  args = parse_args(ARGV)
  title = args.fetch("title", "").strip
  url = args.fetch("url", "").strip
  description = args.fetch("description", "").strip
  type = args.fetch("type", "").strip.downcase
  date = args["date"]&.strip

  raise ArgumentError, "title is required" if title.empty?
  raise ArgumentError, "url is required" if url.empty?
  raise ArgumentError, "description is required" if description.empty?
  raise ArgumentError, "type is required" if type.empty?

  unless ALLOWED_TYPES.include?(type)
    raise ArgumentError, "type must be one of: #{ALLOWED_TYPES.join(', ')}"
  end

  validate_url!(url)
  date = nil if date&.empty?
  date = validate_date!(date) unless date.nil?

  queue_items = load_items(QUEUE_FILE)
  daily_items = load_items(DAILY_FILE)

  if !date.nil? && daily_items.any? { |item| item["date"].to_s == date }
    raise ArgumentError, "An entry for #{date} already exists in #{DAILY_FILE}."
  end

  if !date.nil? && queue_items.any? { |item| item.is_a?(Hash) && item["date"].to_s == date }
    raise ArgumentError, "A queued entry for #{date} already exists in #{QUEUE_FILE}."
  end

  if queue_items.any? { |item| item.is_a?(Hash) && item["url"].to_s.strip == url }
    raise ArgumentError, "This URL is already queued in #{QUEUE_FILE}."
  end

  new_item = {
    "title" => title,
    "url" => url,
    "description" => description,
    "type" => type
  }
  new_item["date"] = date unless date.nil?

  queue_items << new_item
  File.write(QUEUE_FILE, YAML.dump(queue_items))

  puts "Queued '#{title}' in #{QUEUE_FILE}"
rescue KeyError, ArgumentError => e
  warn e.message
  usage!
end
