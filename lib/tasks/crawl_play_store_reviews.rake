require 'net/http'
require 'uri'
require 'json'
require 'nokogiri'

desc 'Crawl Google PlayStore App Reviews'
task :crawl_play_store_reviews => :environment do |t, args|
  # REF:
  # - JS: https://github.com/facundoolano/google-play-scraper/blob/dev/lib/reviews.js
  # - Ruby: https://kazucocoa.wordpress.com/2014/05/25/googleplay%E3%81%AE%E3%83%AC%E3%83%93%E3%83%A5%E3%83%BC%E3%82%92%E5%8F%96%E5%BE%97%E3%81%99%E3%82%8B

  SORT_OPTIONS = {
    NEWEST: 0,
    RATING: 1,
    HELPFULNESS: 2
  }

  def crawl_playstore_reviews(app_id, language)
    uri = URI.parse("https://play.google.com/store/getreviews")
    data = {
      pageNum: 0,
      id: app_id,
      reviewSortOrder: SORT_OPTIONS[:NEWEST],
      hl: language,
      reviewType: 0,
      xhr: 1
    }

    # Create the HTTP objects
    https = Net::HTTP.new(uri.host, uri.port)
    https.use_ssl = true
    request = Net::HTTP::Post.new(uri.request_uri)
    request.set_form_data(data)

    # Send the request
    res = https.request(request)

    # obtain response from google play
    res = res.body.split("\n")[2]

    # convert unicode escaped string to "<" and ">"
    res.gsub!(/\\u([0-9a-f]{4})/) { [$1.hex].pack("U") }.gsub!(/\\/, '')
    doc =  Nokogiri::HTML(res, nil, 'UTF-8')

    doc.css('.single-review').map do |r|
      {
        id: r.css('.review-header').first['data-reviewid'],
        user_name: r.css('.author-name').text.strip,
        user_image: r.css('.author-image').attr('style').value[/url\((.+)\)/, 1],
        review_date: r.css('.review-date').text.strip,
        score: r.css('.star-rating-non-editable-container').attr('aria-label').value.gsub(/[^0-5]/, '').to_i,
        url: "https://play.google.com#{r.css('.reviews-permalink').attr('href').to_s}",
        text: r.css('.review-body').children[2].text.strip,
      }
    end
  end

  puts crawl_playstore_reviews('com.bourbonshake.bark', 'en')
end