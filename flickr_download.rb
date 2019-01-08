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
  puts "You are now authenticated as #{login.username}"
rescue FlickRaw::FailedResponse => e
  puts "Authentication failed : #{e.msg}"
end

options = { :input_file => nil, :output_file => nil,
            :url_list => [], :directory => ENV["HOME"] + "/Pictures"}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage:  #{File.basename(__FILE__)} [OPTIONS] OTHER_ARGS"

  opts.separator ""
  opts.separator "Specific Options:"

  opts.on("-i", "--input-file INPUT-FILE",
          "Import url list from file") do |ifile|
    options[:input_file] = ifile
  end

  opts.on("-o", "--output-file OUTPUT-FILE",
          "Export url list to file") do |ofile|
    options[:output_file] = ofile
  end

  opts.on("-d", "--directory DIRECTORY",
          "Directory to save pictures") do |dir|
    options[:directory] = dir
  end

  opts.separator "Common Options:"

  opts.on("-h", "--help",
          "Show this message." ) do
    puts opts
    exit
  end
end

begin
  optparse.parse!
  options[:url_list] = ARGV
rescue
  puts optparse
  exit
end

$input_file  = options[:input_file]
$output_file = options[:output_file]
$url_list    = options[:url_list]
$directory   = options[:directory]

if $input_file
  input_text = File.open($input_file).read
  input_text.gsub!(/\r\n?/, "\n")
  input_text.each_line do |url|
    $url_list.push(url)
  end
end

if $output_file
  $f_urllist = File.open(File.expand_path($output_file), "a+")
end

def download(photos)
  concurrency = 8

  puts "Downloading #{photos.count} photos from flickr with concurrency=#{concurrency} ..."
  FileUtils.mkdir_p($directory)

  photos.each_slice(concurrency).each do |group|
    threads = []
    group.each do |photo|
      threads << Thread.new {
        attempt = 0

        url = best_url(photo)
        if url.nil?
          puts "Image URL not found for #{photo}"
          return
        end
        date_faved = photo["date_faved"]

        filename = "#{date_faved}@#{File.basename(url.to_s.split('?')[0])}"

        if !File.exists?("#{$directory}/#{filename}-meta.yml")
          puts "Saving metadata for #{url} to #{filename}-meta.yml"
          File.open("#{$directory}/#{filename}-meta.yml","w") do |f|
            f.write(photo.to_yaml)
          end
        end

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
      $f_urllist.write("#{photo[:url]}\n")
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
      user_page_count   = (user_photo_count.to_i / 500.0).ceil
      user_current_page = 1

      while user_current_page <= user_page_count
        photos_page = flickr.people.getPhotos(:user_id => user_id,
                                              :safe_search => "3",
                                              :extras => "url_o,date_upload,date_taken,owner_name,tags",
                                              :page => user_current_page,
                                              :per_page => "500")
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
      photoset_page_count     = (photoset_count.to_i / 500.0).ceil
      photoset_current_page   = 1

      while photoset_current_page <= photoset_page_count
        photos_page = flickr.photosets.getPhotos(:photoset_id => photoset_photoset_id,
                                                :extras => "url_o,date_upload,date_taken,owner_name,tags",
                                                :page => photoset_current_page,
                                                :per_page => "500")
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
      fav_page_count   = (fav_photo_count.to_i / 500.0).ceil
      fav_current_page = 1

      puts "#{fav_photo_count.to_i} favourites"
      while fav_current_page <= fav_page_count
        puts "Getting favourite page #{fav_current_page}"
        photos_page = flickr.favorites.getList(:user_id => user_id,
                                              :extras => "url_o,date_upload,date_taken,owner_name,tags",
                                              :page => fav_current_page,
                                              :per_page => "500")
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
    group_page_count   = (group_photo_count.to_i / 500.0).ceil
    group_current_page = 1

    while group_current_page <= group_page_count
      photos_page = flickr.groups.pools.getPhotos(:group_id => group_id,
                                                  :extras => "url_o,date_upload,date_taken,owner_name,tags",
                                                  :page => group_current_page,
                                                  :per_page => "500")
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
  $f_urllist.close
end

puts "Done."
