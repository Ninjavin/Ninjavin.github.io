#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "uri"
require "yaml"

QUEUE_FILE = "_data/daily_links_queue.yml"
DAILY_FILE = "_data/daily_links.yml"
ALLOWED_TYPES = %w[article video tool].freeze

def load_items(path)
  return [] unless File.exist?(path)

  raw = YAML.safe_load_file(path, permitted_classes: [Date], aliases: false)
  raw.is_a?(Array) ? raw : []
end

def write_items(path, items)
  File.write(path, YAML.dump(items))
end

def validate_url!(url)
  uri = URI.parse(url)
  unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
    raise ArgumentError, "Invalid URL '#{url}'. Use full http/https URL."
  end
end

def valid_date(value)
  Date.iso8601(value).strftime("%Y-%m-%d")
rescue Date::Error
  raise ArgumentError, "Invalid date '#{value}'. Use YYYY-MM-DD."
end

def set_output(key, value)
  output_file = ENV["GITHUB_OUTPUT"]
  return if output_file.nil? || output_file.empty?

  File.open(output_file, "a") { |f| f.puts("#{key}=#{value}") }
end

queue = load_items(QUEUE_FILE)
daily = load_items(DAILY_FILE)

if queue.empty?
  puts "Queue is empty. Nothing to publish."
  set_output("changed", "false")
  exit 0
end

candidate = queue.first
unless candidate.is_a?(Hash)
  raise ArgumentError, "First queue entry is not a map/object."
end

title = candidate.fetch("title", "").to_s.strip
url = candidate.fetch("url", "").to_s.strip
description = candidate.fetch("description", "").to_s.strip
type = candidate.fetch("type", "").to_s.strip.downcase
date = candidate["date"].to_s.strip

raise ArgumentError, "Queue entry title is required." if title.empty?
raise ArgumentError, "Queue entry url is required." if url.empty?
raise ArgumentError, "Queue entry description is required." if description.empty?
raise ArgumentError, "Queue entry type is required." if type.empty?
raise ArgumentError, "Queue entry type must be one of: #{ALLOWED_TYPES.join(', ')}" unless ALLOWED_TYPES.include?(type)

validate_url!(url)
date = date.empty? ? Date.today.strftime("%Y-%m-%d") : valid_date(date)

if daily.any? { |item| item["date"].to_s == date }
  raise ArgumentError, "A daily entry for #{date} already exists in #{DAILY_FILE}. Queue was not changed."
end

new_entry = {
  "date" => date,
  "title" => title,
  "url" => url,
  "description" => description,
  "type" => type
}

queue.shift
daily.unshift(new_entry)

write_items(QUEUE_FILE, queue)
write_items(DAILY_FILE, daily)

puts "Published '#{title}' for #{date}."
set_output("changed", "true")
set_output("published_date", date)
set_output("published_title", title.gsub("\n", " "))
