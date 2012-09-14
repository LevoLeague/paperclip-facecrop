require File.join(File.dirname(__FILE__), "/oauth_authentication.rb")

module Mashape
  class OAuth2Authentication < OAuthAuthentication
     def initialize(consumer_key, consumer_secret, redirect_url)
       super(consumer_key, consumer_secret, redirect_url)
     end
  end
end