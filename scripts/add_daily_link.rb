#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "uri"
require "yaml"

DATA_FILE = "_data/daily_links.yml"
ALLOWED_TYPES = %w[article video tool].freeze

def usage!
  warn "Usage: ruby scripts/add_daily_link.rb --title \"...\" --url \"...\" --description \"...\" --type article|video|tool [--date YYYY-MM-DD]"
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
  date = date.nil? || date.empty? ? Date.today.strftime("%Y-%m-%d") : validate_date!(date)

  items = load_items(DATA_FILE)
  if items.any? { |item| item["date"].to_s == date }
    raise ArgumentError, "An entry for #{date} already exists in #{DATA_FILE}."
  end

  items.unshift(
    {
      "date" => date,
      "title" => title,
      "url" => url,
      "description" => description,
      "type" => type
    }
  )

  File.write(DATA_FILE, YAML.dump(items))
  puts "Added new link for #{date} in #{DATA_FILE}"
rescue KeyError, ArgumentError => e
  warn e.message
  usage!
end
