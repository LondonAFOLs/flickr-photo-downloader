#!/usr/bin/env ruby
# Filename: flickr_download.rb
# Description: Easily download all the photos from a flickr: group pool,
#              photostream, photosets and favorites

require 'rubygems'
require 'bundler'
require 'yaml'
require 'fileutils'
require 'optparse'
Bundler.require

PHOTO_EXTRAS = "description,license,date_upload,date_taken,owner_name,tags,original_format,last_update,geo,machine_tags,o_dims,views,media,path_alias,url_sq,url_t,url_s,url_q,url_m,url_n,url_z,url_c,url_l,url_o"
PAGE_SIZE = 500

# Get your API Key: https://secure.flickr.com/services/apps/create/apply
FlickRaw.api_key       = ENV['FLICKR_API_KEY']       || fail("Environment variable FLICKR_API_KEY is required")
FlickRaw.shared_secret = ENV['FLICKR_SHARED_SECRET'] || fail("Environment variable FLICKR_SHARED_SECRET is required")
# Get your access_token & access_secret with flick_auth.rb
flickr.access_token    = ENV['FLICKR_ACCESS_TOKEN']  || fail("Environment variable FLICKR_ACCESS_TOKEN is required - run flickr_auth.rb to generate")
flickr.access_secret   = ENV['FLICKR_ACCESS_SECRET'] || fail("Environment variable FLICKR_ACCESS_SECRET is required - run flickr_auth.rb to generate")
# Use a proxy (e.g. for debugging or inspecting the payload)
FlickRaw.proxy = ENV['HTTPS_PROXY']
# Disable cert checking (e.g. when using a proxy with a self-signed cert)
FlickRaw.check_certificate = ENV['HTTPS_CHECK_CERT'].nil? || !ENV['HTTPS_CHECK_CERT'].downcase == "false"

begin
  login = flickr.test.login
  puts "Authentication succeeded: Flickr API requests will be as user #{login.username}"
rescue StandardError => e
  puts "Authentication failed: the specified key, token and secrets were rejected: #{e.msg}"
  exit
end

LICENSE_LIST =
  (begin
    flickr.photos.licenses.getInfo
  rescue StandardError => e
    puts "Warning: lookup of Flickr's supported photo licenses failed. Using a default list"
    [
        { :id => "0",  :name => "All Rights Reserved", :url => nil },
        { :id => "1",  :name => "Attribution-NonCommercial-ShareAlike License", :url => "https://creativecommons.org/licenses/by-nc-sa/2.0/" },
        { :id => "2",  :name => "Attribution-NonCommercial License", :url => "https://creativecommons.org/licenses/by-nc/2.0/" },
        { :id => "3",  :name => "Attribution-NonCommercial-NoDerivs License", :url => "https://creativecommons.org/licenses/by-nc-nd/2.0/" },
        { :id => "4",  :name => "Attribution License", :url => "https://creativecommons.org/licenses/by/2.0/" },
        { :id => "5",  :name => "Attribution-ShareAlike License", :url => "https://creativecommons.org/licenses/by-sa/2.0/" },
        { :id => "6",  :name => "Attribution-NoDerivs License", :url => "https://creativecommons.org/licenses/by-nd/2.0/" },
        { :id => "7",  :name => "No known copyright restrictions", :url => "https://www.flickr.com/commons/usage/" },
        { :id => "8",  :name => "United States Government Work", :url => "http://www.usa.gov/copyright.shtml" },
        { :id => "9",  :name => "Public Domain Dedication (CC0)", :url => "https://creativecommons.org/publicdomain/zero/1.0/" },
        { :id => "10", :name => "Public Domain Mark", :url => "https://creativecommons.org/publicdomain/mark/1.0/" }
    ]
  end).sort_by { |license| license.id.to_i }
LICENSE_IDS = LICENSE_LIST&.map(&:id)&.to_set

options = {
  :input_file => nil,
  :output_file => nil,
  :url_list => [],
  :directory => nil,
  :meta_directory => nil,
  :include_licenses => nil,
  :exclude_licenses => nil
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage:  #{File.basename(__FILE__)} [OPTIONS] OTHER_ARGS"

  opts.separator ""
  opts.separator "Specific Options:"

  opts.on("-i", "--input-file INPUT-FILE",
          "Import url list from file") do |file|
    options[:input_file] = file
  end

  opts.on("-n", "--include-with-licenses license-id1,license-id2,...",
          "Only include photos with a license matching the supplied Flickr license IDs unless excluded by --exclude-with-licenses. Defaults to all license types") do |licenses|
    options[:include_licenses] = licenses.split(",").map(&:strip).to_set
  end

  opts.on("-x", "--exclude-with-licenses license-id1,license-id2,...",
          "Exclude any photos with a license matching the supplied Flickr license IDs") do |licenses|
    options[:exclude_licenses] = licenses.split(",").map(&:strip).to_set
  end

  opts.on("-o", "--output-file OUTPUT-FILE",
          "Export url list to file") do |file|
    options[:output_file] = file
  end

  opts.on("-d", "--directory DIRECTORY",
          "Directory to save pictures") do |dir|
    options[:directory] = dir
  end

  opts.on("-m", "--metadata-directory DIRECTORY",
          "Directory to save photo metadata files to") do |dir|
    options[:meta_directory] = dir
  end

  opts.separator "Common Options:"

  opts.on("-h", "--help",
          "Show this message." ) do
    puts opts
    exit
  end

  opts.separator ""
  opts.separator "Flick photo license IDs:"
  opts.separator ""

  LICENSE_LIST&.each do |license|
    opts.separator "#{license.id}: #{license.name} #{if license.url.nil? then '' else '(' end}#{license.url}#{if license.url.nil? then '' else ')' end}"
  end
end

begin
  optparse.parse!
  options[:url_list] = ARGV
rescue StandardError
  puts "#{$!}"
  puts optparse
  exit
end

if options[:input_file] && options[:output_file]
    puts "Invalid option: an output file is appropriate only when using the Flickr API to direct photo downloads, not when using an input file"
    puts optparse
    exit
end

if options[:input_file] && (options[:include_licenses] || options[:exclude_licenses])
    puts "Invalid option: filtering photos by license is only appropriate when using the Flickr API to direct downloads, not when using an input file"
    puts optparse
    exit
end

$input_file       = options[:input_file]
$output_file      = options[:output_file]
$url_list         = options[:url_list]                    || []
$directory        = options[:directory]                   || ENV["HOME"] + "/Pictures/flickr"
$meta_directory   = options[:meta_directory]              || "#{$directory}/metadata"
$include_licenses = options[:include_licenses]            || LICENSE_IDS
$exclude_licenses = options[:exclude_licenses]            || Set.new
$licenses         = $include_licenses - $exclude_licenses

if !$include_licenses.subset?(LICENSE_IDS) || !$exclude_licenses.subset?(LICENSE_IDS)
    unknown_licenses = ($include_licenses + $exclude_licenses) - LICENSE_IDS
    puts "Invalid option: #{unknown_licenses.join(', ')}: only Flick photo license IDs may be specified when filtering"
    puts optparse
    exit
end

if $licenses.empty?
    puts "Invalid option: the supplied Flickr photo license ID filter will always filter out all photos"
    puts optparse
    exit
end

if $input_file
  input_text = File.open($input_file).read
  input_text.gsub!(/\r\n?/, "\n")
  input_text.each_line do |url|
    $url_list.push(url)
  end
end

if $output_file
  $output_text = File.open(File.expand_path($output_file), "a+")
end

def download(photos)
  if photos.empty?
    return
  end

  concurrency = 8

  puts "Downloading #{photos.count} photos from flickr with concurrency=#{concurrency} ..."
  FileUtils.mkdir_p($meta_directory)

  photos.each_slice(concurrency).each do |group|
    threads = []
    group.each do |photo|
      url, metadata = if photo.is_a?(String)
         [photo, nil]
      else
        [best_url(photo), photo]
      end

      license = metadata&.license
      if !license&.nil? and !$licenses.include?(license) then
        puts "Skipping photo #{url}: license type excluded from results"
        next
      end

      #no URL present in metadata - give up
      if url.nil?
        puts "Skipping photo #{metadata.id}: no URL found for download"
        next
      end

      threads << Thread.new {
        disposition, disposition_date = if metadata.nil? then
          ["", ""]
        elsif metadata["date_faved"].nil?
          ["uploaded@", "#{metadata['dateupload']}-"]
        else
          ["faved@", "#{metadata['date_faved']}-"]
        end

        file_basename = File.basename(url.to_s.split('?')[0])
        filename = "#{disposition}#{disposition_date}#{file_basename}"
        meta_filename = "#{file_basename}-meta.yml"

        if !File.exists?("#{$meta_directory}/#{meta_filename}")
          puts "Saving metadata for #{url}"
          File.open("#{$meta_directory}/#{meta_filename}","w") do |f|
            f.write(photo.to_yaml)
          end
        end

        attempt = 0
        begin
          if attempt > 0
            puts "Retrying..."
          end

          if File.exists?("#{$directory}/#{filename}") and Mechanize.new.head(url)["content-length"].to_i === File.stat("#{$directory}/#{filename}").size.to_i
            puts "Already saved photo #{url}"
          else
            file = Mechanize.new.get(url)
            puts "Saving image #{url} to #{filename}"
            file.save_as("#{$directory}/#{filename}")
          end
        rescue StandardError
          puts "Error getting file #{url}, #{$!}"
          attempt += 1
          retry if attempt <= 3
        end
      }
    end
    threads.each{|t| t.join }
  end
end

def process(photos)
  if $output_file
    photos.each do |photo|
      if photo.is_a? String
        $output_text.write("#{photo}\n")
      else
        $output_text.write("#{photo[:url]}\n")
      end
    end
  else
    download(photos)
  end
  photos.clear
end

def best_url(photo)
  if !photo["url_o"].nil?
      photo["url_o"]
  elsif !FlickRaw.url_b(photo).nil?
      FlickRaw.url_b(photo)
  elsif !FlickRaw.url_c(photo).nil?
      FlickRaw.url_c(photo)
  elsif !FlickRaw.url_z(photo).nil?
      FlickRaw.url_z(photo)
  else
      puts "Image URL not found for photo with ID #{photo.id}"
      nil
  end
end

# Web Page URLs
# https://secure.flickr.com/services/api/misc.urls.html
#
# http://www.flickr.com/people/{user-id}/ - profile
# http://www.flickr.com/photos/{user-id}/ - photostream
# http://www.flickr.com/photos/{user-id}/{photo-id} - individual photo
# http://www.flickr.com/photos/{user-id}/sets/ - all photosets
# http://www.flickr.com/photos/{user-id}/sets/{photoset-id} - single photoset

flickr_regex = /http[s]?:\/\/(?:www|secure).flickr.com\/(groups|photos)\/[\w@-]+(?:\/(\d{11}|sets|pool|favorites)[\/]?)?(\d{17})?(?:\/with\/(\d{11}))?[\/]?$/

# Photostream Regex
# photo_stream_regex  = /http[s]?:\/\/(?:www|secure).flickr.com\/photos\/([\w@]+)[\/]?$/
#
# Single photoset
# photo_sets_regex    = /http[s]?:\/\/(?:www|secure).flickr.com\/photos\/([\w@]+)\/sets\/(\d{17})[\/]?$/
#
# Individual photo
# photo_single_regex0 = /http[s]?:\/\/(?:www|secure).flickr.com\/photos\/([\w@]+)\/sets\/(\d{17})\/with\/(\d{10})[\/]?$/
# photo_single_regex1 = /http[s]?:\/\/(?:www|secure).flickr.com\/photos\/([\w@]+)\/(\d{10})[\/]?$/

photos_outstanding = []

$url_list.each do |url|
  if match = url.match(flickr_regex)
    # match_group1: user photostream or group pool
    # match_group2: individual photo id, "sets", "pool" or "favorites"
    # match_group3: photoset id
    # match_group4: individual photo id
    match_group1, match_group2, match_group3, match_group4 = match.captures
  else
    puts "URL: #{url} don't match with supported flickr url"
    break
  end

  if match_group1.eql?("photos")
    ##### Get photolist of user #####
    if match_group2.nil?
      # flickr.people.lookUpUser(:url => url)
      user         = flickr.people.getInfo(:url => url)
      user_id      = user["id"]
      user_photo_count  = user["photos"]["count"]
      user_page_count   = (user_photo_count.to_i / PAGE_SIZE.to_f).ceil
      user_current_page = 1

      while user_current_page <= user_page_count
        photos_page = flickr.people.getPhotos(:user_id => user_id,
                                              :safe_search => "3",
                                              :extras => PHOTO_EXTRAS,
                                              :page => user_current_page,
                                              :per_page => PAGE_SIZE.to_s)
        photos_page.each do |photo|
          photos_outstanding.push(photo)
        end

        process(photos_outstanding)

        user_current_page += 1
      end

    ##### Get photo list of photoset #####
    elsif match_group2.eql?("sets") and match_group4.nil?
      photoset       = flickr.photosets.getInfo(:photoset_id => match_group3)
      photoset_id    = photoset["id"]
      photoset_count = photoset["photos"]
      photoset_page_count     = (photoset_count.to_i / PAGE_SIZE.to_f).ceil
      photoset_current_page   = 1

      while photoset_current_page <= photoset_page_count
        photos_page = flickr.photosets.getPhotos(:photoset_id => photoset_photoset_id,
                                                :extras => PHOTO_EXTRAS,
                                                :page => photoset_current_page,
                                                :per_page => PAGE_SIZE.to_s)
        photos_page = photos_page["photo"]

        photos_page.each do |photo|
          photos_outstanding.push(photo)
        end

        process(photos_outstanding)

        photoset_current_page += 1
      end

    ##### Get photo list of user favorites #####
    elsif match_group2.eql?("favorites")
      user         = flickr.people.getInfo(:url => url)
      user_id      = user["id"]
      fav_photo_count  = flickr.favorites.getList(:user_id => user_id,
                                                  :per_page => "1",
                                                  :page => "1")["total"]
      fav_page_count   = (fav_photo_count.to_i / PAGE_SIZE.to_f).ceil
      fav_current_page = 1

      puts "#{fav_photo_count.to_i} favourites"
      while fav_current_page <= fav_page_count
        puts "Getting favourite page #{fav_current_page}"
        photos_page = flickr.favorites.getList(:user_id => user_id,
                                              :extras => PHOTO_EXTRAS,
                                              :page => fav_current_page,
                                              :per_page => PAGE_SIZE.to_s)
        photos_page.each do |photo|
            photos_outstanding.push(photo)
        end
        
        process(photos_outstanding)

        fav_current_page += 1
      end

    ##### Get individual photo url #####
    else
      if match_group4.nil?
        photo = flickr.photos.getInfo(:photo_id => match_group2)
      else
        photo = flickr.photos.getInfo(:photo_id => match_group4)
      end
      photos_outstanding.push(photo)
      process(photos_outstanding)
      photos_outstanding.clear
    end
  ##### Get individual photo url #####
  elsif match_group1.eql?("groups")
    group        = flickr.urls.lookupGroup(:url => url)
    group_id     = group["id"]
    group_name   = group["groupname"]
    group_photo_count  = flickr.groups.getInfo(:group_id => group_id)["pool_count"]
    group_page_count   = (group_photo_count.to_i / PAGE_SIZE.to_f).ceil
    group_current_page = 1

    while group_current_page <= group_page_count
      photos_page = flickr.groups.pools.getPhotos(:group_id => group_id,
                                                  :extras => PHOTO_EXTRAS,
                                                  :page => group_current_page,
                                                  :per_page => PAGE_SIZE.to_s)
      photos_page = photos_page["photo"]

      photos_page.each do |photo|
        photos_outstanding.push(photo)
      end

      process(photos_outstanding)

      group_current_page += 1
    end

  end
end

if $output_file
  $output_text.close
end

puts "Done."
