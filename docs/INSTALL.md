# Install gem deps
export  http_proxy=http://127.0.0.1:2020
bundle install --path vendor/bundle
bundle exec jekyll s  --incremental
