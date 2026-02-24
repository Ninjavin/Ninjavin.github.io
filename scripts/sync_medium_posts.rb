#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "open-uri"
require "rss"
require "set"
require "time"
require "uri"
require "yaml"

POSTS_DIR = "_posts"
CONFIG_FILE = "_config.yml"
DEFAULT_MAX_POSTS = 5

def usage!
  warn "Usage: ruby scripts/sync_medium_posts.rb [--username <medium-username>] [--feed-url <rss-url>] [--max-posts <number>]"
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

def set_output(key, value)
  output_file = ENV["GITHUB_OUTPUT"]
  return if output_file.nil? || output_file.empty?

  File.open(output_file, "a") { |f| f.puts("#{key}=#{value}") }
end

def load_medium_username_from_config
  return nil unless File.exist?(CONFIG_FILE)

  config = YAML.safe_load_file(CONFIG_FILE, aliases: false)
  author = config.is_a?(Hash) ? config["author"] : nil
  return nil unless author.is_a?(Hash)

  username = author["medium"].to_s.strip
  username.empty? ? nil : username
end

def validate_positive_integer!(value, key)
  num = Integer(value)
  raise ArgumentError, "#{key} must be greater than 0." if num <= 0

  num
rescue ArgumentError
  raise ArgumentError, "#{key} must be a positive integer."
end

def validate_feed_url!(url)
  uri = URI.parse(url)
  unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
    raise ArgumentError, "Invalid --feed-url. Use a full http/https URL."
  end
end

def strip_html(text)
  raw = text.to_s
  plain = raw.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  CGI.unescapeHTML(plain)
end

def truncate(text, max_length)
  return text if text.length <= max_length

  "#{text[0, max_length - 1].rstrip}…"
end

def slug_from_url(url)
  uri = URI.parse(url)
  segments = uri.path.to_s.split("/").reject(&:empty?)
  candidate = segments.last.to_s
  candidate = candidate.split("?").first
  candidate = candidate.downcase.gsub(/[^a-z0-9-]+/, "-").gsub(/-+/, "-").gsub(/\A-|-+\z/, "")
  candidate.empty? ? "medium-post" : candidate
rescue URI::InvalidURIError
  "medium-post"
end

def extract_existing_keys
  external_urls = Set.new
  medium_guids = Set.new

  Dir.glob(File.join(POSTS_DIR, "*.md")).each do |path|
    content = File.read(path)

    if (url_match = content.match(/^\s*external_url:\s*(.+)\s*$/))
      value = url_match[1].to_s.strip.sub(/\A["']/, "").sub(/["']\z/, "")
      external_urls << value unless value.empty?
    end

    if (guid_match = content.match(/^\s*medium_guid:\s*(.+)\s*$/))
      value = guid_match[1].to_s.strip.sub(/\A["']/, "").sub(/["']\z/, "")
      medium_guids << value unless value.empty?
    end
  end

  [external_urls, medium_guids]
end

def to_time(item)
  value = if item.respond_to?(:pubDate) && !item.pubDate.nil?
            item.pubDate
          elsif item.respond_to?(:dc_date) && !item.dc_date.nil?
            item.dc_date
          end

  return Time.now if value.nil?
  return value if value.is_a?(Time)

  Time.parse(value.to_s)
rescue ArgumentError
  Time.now
end

def yaml_quote(value)
  escaped = value.to_s.gsub("\\", "\\\\").gsub('"', '\"')
  "\"#{escaped}\""
end

def build_post_content(item, url, guid)
  title = strip_html(item.title)
  title = "Untitled Medium Post" if title.empty?

  description_raw = if item.respond_to?(:description) && !item.description.nil?
                      item.description.to_s
                    else
                      ""
                    end
  description = truncate(strip_html(description_raw), 240)
  description = "Read this post on Medium." if description.empty?

  categories = if item.respond_to?(:categories) && item.categories
                 item.categories.map { |cat| strip_html(cat.respond_to?(:content) ? cat.content : cat.to_s) }
               else
                 []
               end
  tags = categories.reject(&:empty?).uniq
  tags = ["medium"] if tags.empty?

  <<~POST
    ---
    title: #{yaml_quote(title)}
    tags: [#{tags.map { |tag| yaml_quote(tag) }.join(", ")}]
    style: border
    color: warning
    description: #{yaml_quote(description)}
    external_url: #{yaml_quote(url)}
    medium_guid: #{yaml_quote(guid)}
    ---
  POST
end

args = parse_args(ARGV)
username = args["username"]&.strip
feed_url = args["feed-url"]&.strip
max_posts = args["max-posts"] ? validate_positive_integer!(args["max-posts"], "--max-posts") : DEFAULT_MAX_POSTS

if feed_url.nil? || feed_url.empty?
  username = load_medium_username_from_config if username.nil? || username.empty?
  raise ArgumentError, "Medium username not found. Pass --username or set author.medium in _config.yml." if username.nil? || username.empty?

  feed_url = "https://medium.com/feed/@#{username}"
else
  validate_feed_url!(feed_url)
end

xml = URI.open(feed_url, "User-Agent" => "ninjavin-medium-sync/1.0").read
feed = RSS::Parser.parse(xml, false)
items = feed.respond_to?(:items) ? feed.items : []
raise ArgumentError, "No items found in feed: #{feed_url}" if items.empty?

existing_urls, existing_guids = extract_existing_keys
imported_count = 0

items.sort_by { |item| to_time(item) }.each do |item|
  break if imported_count >= max_posts

  url = item.respond_to?(:link) ? item.link.to_s.strip : ""
  next if url.empty?

  guid = if item.respond_to?(:guid) && !item.guid.nil?
           item.guid.respond_to?(:content) ? item.guid.content.to_s.strip : item.guid.to_s.strip
         else
           url
         end

  next if existing_urls.include?(url) || (!guid.empty? && existing_guids.include?(guid))

  post_time = to_time(item)
  date = post_time.utc.to_date.strftime("%Y-%m-%d")
  base_slug = slug_from_url(url)
  filename = "#{date}-#{base_slug}.md"
  path = File.join(POSTS_DIR, filename)
  suffix = 2

  while File.exist?(path)
    filename = "#{date}-#{base_slug}-#{suffix}.md"
    path = File.join(POSTS_DIR, filename)
    suffix += 1
  end

  File.write(path, build_post_content(item, url, guid))
  existing_urls << url
  existing_guids << guid unless guid.empty?
  imported_count += 1
  puts "Imported #{filename}"
end

changed = imported_count.positive?
set_output("changed", changed ? "true" : "false")
set_output("imported_count", imported_count.to_s)

if changed
  puts "Imported #{imported_count} Medium post(s)."
else
  puts "No new Medium posts to import."
end
