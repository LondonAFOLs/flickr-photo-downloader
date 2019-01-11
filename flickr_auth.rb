require "launchy"
require "flickraw"

FlickRaw.api_key       = ENV['FLICKR_API_KEY']       || fail "Environment variable FLICKR_API_KEY is required"
FlickRaw.shared_secret = ENV['FLICKR_SHARED_SECRET'] || fail "Environment variable FLICKR_SHARED_SECRET is required"

token = flickr.get_request_token
auth_url = flickr.get_authorize_url(token['oauth_token'], :perms => 'read')

puts "Open this url in your process to complete the authication process : #{auth_url}"
Launchy.open(auth_url)
puts "Paste here the number given when you complete the process:"
verify = gets.strip

begin
  flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
  login = flickr.test.login

  export = if Gem.win_platform? then "set" else "export" end

  puts <<-eos
You are now authenticated as #{login.username} with token #{flickr.access_token}
and secret #{flickr.access_secret}".

You will next need to set the following environment variables on the current command line before running
flickr_download.rb. This ensures the script authenticates as you and can retrieve any photos you have permission to view
when talking to the Flickr API.

  #{export} FLICKR_API_KEY="#{FlickRaw.api_key}"
  #{export} FLICKR_SHARED_SECRET="#{FlickRaw.shared_secret}"
  #{export} FLICKR_ACCESS_TOKEN="#{flickr.access_token}"
  #{export} FLICKR_ACCESS_SECRET="#{flickr.access_secret}"

eos
rescue FlickRaw::FailedResponse => e
  puts "Authentication failed : #{e.msg}"
end
