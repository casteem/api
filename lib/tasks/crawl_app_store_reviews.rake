require 'net/http'
require 'uri'
require 'json'

STORES = {
   KR: 143_466, US: 143_441, AR: 143_505, AU: 143_460, BE: 143_446, BR: 143_503, CA: 143_455, CL: 143_483, CN: 143_465, CO: 143_501, CR: 143_495, HR: 143_494, CZ: 143_489, DK: 143_458, DE: 143_443, SV: 143_506, ES: 143_454, FI: 143_447, FR: 143_442, GR: 143_448, GT: 143_504, HK: 143_463, HU: 143_482, IN: 143_467, ID: 143_476, IE: 143_449, IL: 143_491, IR: 143_450, KW: 143_493, LB: 143_497, LU: 143_451, MY: 143_473, MX: 143_468, NL: 143_452, NZ: 143_461, NO: 143_457, AT: 143_445, PK: 143_477, PA: 143_485, PE: 143_507, PH: 143_474, PL: 143_478, PT: 143_453, QA: 143_498, RO: 143_487, RU: 143_469, SA: 143_479, CH: 143_459, SG: 143_464, SK: 143_496, SI: 143_499, ZA: 143_472, LK: 143_486, SE: 143_456, TW: 143_470, TH: 143_475, TR: 143_480, AE: 143_481, UK: 143_444, VE: 143_502, VN: 143_471, JP: 143_462, DO: 143_508, EC: 143_509, EG: 143_516, EE: 143_518, HN: 143_510, JM: 143_511, KZ: 143_517, LV: 143_519, LT: 143_520, MO: 143_515, MT: 143_521, MD: 143_523, NI: 143_512, PY: 143_513
}

SORT_BY = {
  HELPFULL: 1,
  RATE_DESC: 2,
  RATE_ASC: 3,
  NEWEST: 4
}

desc 'Crawl App Store App Reviews'
task :crawl_app_store_reviews => :environment do |t, args|

  def crawl_appstore_reviews(app_id, country)
    url = 'https://itunes.apple.com/WebObjects/MZStore.woa/wa/userReviewsRow?'
    url << "id=#{app_id}&displayable-kind=11&startIndex=0&endIndex=100&sort=4&appVersion=all"

    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = 'iTunes/11.1 (Macintosh; OS X 10.9) AppleWebKit/537.71'
    req['X-Apple-Store-Front'] =  "#{STORES[country]}-2,17"

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http|
      http.request(req)
    }

    data = JSON.parse(res.body)

    reviews = data["userReviewList"].map do |r|
      {
        id: r["userReviewId"],
        user_name: r["name"],
        user_image: nil,
        review_date: r["date"],
        score: r["rating"].to_i,
        url: "https://itunes.apple.com/#{country.downcase}/app/facebook/id#{app_id}",
        text: r["body"].strip,
      }
    end
  end

  puts crawl_appstore_reviews('1100131438', 'KR')
end
