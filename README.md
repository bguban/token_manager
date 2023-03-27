# TokenManager

`TokenManager` is designed to handle inter micro-service communication without sharing secrets between the services.
It uses asymmetric signature to verify the hosts.

The workflow schema looks next:
1. Service A generates a signed token and adds it to a request
2. Service B receives the request with the token, takes a public_key id (`kid`) from the token and requests Service A for the public key via http request
3. Service A responds with the public key
4. Service B verifies the token using the public_key 

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add token_manager

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install token_manager

## Usage

### Basic configuration

Create classes that inherit from TokenManager. 

You need to override `with_redis` method. It must `yield` the given block and
provide `Redis::Client` instance as an argument (the implementation depends on your redis config).

Also it can be useful to make a "factory" method that will return an instance of the token manager. 

Token manager expects to receive next arguments:

* service_name (required) is a string that represents the current micro-service name. It will be used as `iss` 
in the JWT. It must be in the `trusted_issuers` (see below) in the receiver's config to be able to verify during the decoding.

* trusted_issuers (optional) is a hash where the keys represent allowed issuer and value is a config to retrieve a public_key for
that issuer. TokenManager will send a GET request to the provided url with `kid` (key id) parameter. As a result it 
expects a JSON response like { public_key: "...public_key_here..." }

* token_ttl (optional) will add an expiration claim to every encoded JWT (`exp: Time.now + token_ttl`). If the config 
is skipped it will require to pass `exp` claim explicitly to every `encode` method call.

* public_key_ttl (default 1 month) not to retrieve the public_key each time the receiver caches it in Redis. 
This is the Redis cache TTL

* old_key_ttl (default 1 year) after you regenerate the `private_key` its `public_key` still must be 
stored to verify already generated tokens. This is the Redis cache TTL for the private and public keys.

```ruby
######### micro-service A

# app/models/a_token.rb 
class AToken < TokenManager
  def self.instance
    @instance ||= new(
      service_name: 'a_service',
      token_ttl: 1.minute,
      trusted_issuers: { 
        b_service: { url: 'http://localhost:3001/public_keys' } 
      }
    )
  end

  # uses redis for caching
  private def with_redis
    Rails.cache.redis.with { |redis| yield(redis) }
  end
end

# app/controllers/public_keys_controller
class PublicKeysController < ApplicationController
  def index
    return render(json: { error: '`kid` is required' }, status: 400) unless params[:kid]

    public_key = AToken.instance.public_key(params[:kid])
    return render(json: { error: 'public_keys not found' }, status: 404) unless public_key
    
    render json: {
      kid: params[:kid],
      public_key: public_key,
    }
  end
end
# config/routes.rb
get 'public_keys', to: 'public_keys#index'

######### micro-service B

# app/models/a_token.rb
class BToken < TokenManager
  def self.instance
    @instance ||= new(
      service_name: 'b_service',
      token_ttl: 10.minutes,
      trusted_issuers: {
        a_service: { url: 'https://localhost:3000/public_keys' }
      }
    )
  end

  # uses redis for caching
  private def with_redis
    @redis ||= ::Redis.new
    yield(@redis)
  end
  
  def retrieve_issuer_key(iss, kid)
    AToken.instance.public_key(kid)
  end
end

# app/controllers/public_keys_controller
class PublicKeysController < ApplicationController
  def index
    return render(json: { error: '`kid` is required' }, status: 400) unless params[:kid]

    public_key = BToken.instance.public_key(params[:kid])
    return render(json: { error: 'public_keys not found' }, status: 404) unless public_key

    render json: {
      kid: params[:kid],
      public_key: public_key,
    }
  end
end

# config/routes.rb
get 'public_keys', to: 'public_keys#index'
```

Now you need to run `rails s -p 3000` for service A and `rails s -p 3001` for service B in different terminals 
so the services can retrieve public keys and play in consoles 

```ruby
# console A
token = AToken.instance.encode(aud: 'b_service', foo: 'bar') # "eyJraWQiOiJjNTcxNDRjYS04YWJhLTRlMWMtOGUwNC05YjZkYTc..."
# console B
BToken.instance.decode(token) # [{"exp"=>1679914355, "aud"=>"b_service", "foo"=>"bar", "iss"=>"a_service"}, {"kid"=>"c57144ca-8aba-4e1c-8e04-9b6da70a5dc6", "alg"=>"RS256"}]
```
As you can see the `encode` method requires you to specify `aud` claim with the destination service name. Also it adds
`iss` and `exp` claims (`exp` claim adds automatically only if `token_ttl` was specified).

### Helpers

#### Faraday middleware

If you use libraries which create a connection instance an reuse it you can face a problem that you can't just generate 
a token and specify it in the connection because the token has its TTL. To solve it you can 
use `TokenManager::FaradayMiddleware` that receives a block to generate tokens on the fly. 
Here is an example of the middleware usage with JsonApiClient gem:

```ruby
ServiceB::Resources::Base.connection do |connection|
  connection.use TokenManager::FaradayMiddleware do
    AToken.instance.encode(aud: 'service_b')
  end
end
```

On the ServiceB side you can use `token_from` method to retrieve the token:

```ruby
class ApplicationController < ActionController::API
  # ... code ...
  before_action :authenticate

  private

  def authenticate
    raise(Unauthorized, 'not authorized') unless token['iss'] == 'service_a' # only service_a has access
  end

  def token
    return @token if defined?(@token)

    encoded_token = BToken.token_from(request.headers) || raise(Unauthorized, 'token is absent')
    @token = BToken.instance.decode(encoded_token).first
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/token_manager. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/token_manager/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the TokenManager project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/token_manager/blob/master/CODE_OF_CONDUCT.md).
