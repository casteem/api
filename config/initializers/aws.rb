Aws.config.update({
  region: 'us-west-2',
  credentials: Aws::Credentials.new(ENV["S3_ACCESS_KEY"], ENV["S3_SECRET_KEY"])
})
