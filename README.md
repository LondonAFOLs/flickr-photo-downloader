Flickr Photo Downloader
=======================

Ruby script to download all the photos from a flickr: group pool, user's
photostream, photosets and favorites.

A fork of https://github.com/thuandt/flickr-photo-downloader with modifications to:
* allow input of Flickr API tokens etc and other settings via environment variables
* allow capture of image metadata in separate .yml files along side the images themselves
* substantial speed and bandwidth improvments in cases where images have already been downloaded
* retries when image downloading fails (compensating for intermittent Flickr server problems - 500s etc)
* file names for images are prefixed with the timestamp of when the photo was liked so alphanumeric
  ordering is roughly consistent with like order   

Usage
-----

Checkout the code:

    git clone git://github.com/LondonAFOLs/flickr-photo-downloader.git
    cd flickr-photo-downloader

Install bundler:

    gem install bundler
    bundle install

Set FLICKR_API_KEY and FLICKR_SHARED_SECRET environment variables with your
[API key and shared secret](https://secure.flickr.com/services/apps/create/apply)

    export FLICKR_API_KEY="... Your API key ..."
    export FLICKR_SHARED_SECRET="... Your shared secret ..."

Set FLICKR_ACCESS_TOKEN and FLICKR_ACCESS_SECRET environment variables with your
with your `access_token` and `access_secret` (you get these with
[flickr_auth.rb](flickr_auth.rb))

    # Get your access_token & access_secret by running ruby flick_auth.rb
    export FLICKR_ACCESS_TOKEN="... Your access token ..."
    export FLICKR_ACCESS_SECRET="... Your access secret ..."

Run the script, specifying your photostream, photoset or favorites URLs as the argument:

    ruby flickr_download.rb http://www.flickr.com/groups/LondonAFOLs/pool

By default, images will be saved in folder `Pictures` on `user directory`
(eg /home/mstudman/Pictures). If you want them to be saved to a
different directory, you can pass its name as an optional `-d` argument:

    ruby flickr_download.rb http://www.flickr.com/groups/LondonAFOLs/pool -d ~/Pictures/LondonAFOLs

Instead of downloading Flickr images returned live from querying the Flickr API, you can instead
write them to an output file (one URL per line) with the `-o` argument. This allows you to edit and 
amend the URLs before downloading them. 

    ruby flickr_download.rb -o urllist.txt

To use this amended file to drive downloading of images, you can specify it via the `-i` argument. 

    ruby flickr_download.rb -i urllist.txt

More help and options

    ruby flickr_download.rb --help

Enjoy!


License
-------

Source code released under an [MIT license](http://en.wikipedia.org/wiki/MIT_License)

Pull requests welcome.


Contributing
------------

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request


Authors
-------

* **Dương Tiến Thuận** ([@mrtuxhdb](https://github.com/mrtuxhdb))
* **Michael Studmabn** ([@mrbaboo](https://github.com/mrbaboo))
