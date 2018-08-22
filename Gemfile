source 'https://rubygems.org'

git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end

gem 'rails', '~> 5.2.0'

# Use PostgreSQL database
gem 'pg', '>= 0.18', '< 2.0'

# Use Puma as the app server
gem 'puma', '~> 3.11'

# Cross-Origin HTTP request
gem 'rack-cors'

gem 'aws-sdk-s3', '~> 1'

gem 'whenever', require: false
gem 'dotenv-rails'
gem 'radiator'
gem 'will_paginate'
gem 'bugsnag'

group :development do
  gem 'listen', '>= 3.0.5', '< 3.2'
  # Spring speeds up development by keeping your application running in the background
  # gem 'spring'
  # gem 'spring-watcher-listen', '~> 2.0'

  gem 'pry'

  # Utility for managing multiple processes
  gem 'foreman'

  gem 'capistrano'
  gem 'capistrano3-puma'
  gem 'capistrano-rails'
  gem 'capistrano-rbenv'
end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
