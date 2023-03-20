# frozen_string_literal: true

require_relative "token_manager/version"

class TokenManager
  OLD_KEY_TTL = 1.month
  ISSUER_PUBLIC_KEY_TTL = 1.day
  ALGO = 'RS256'

  def initialize(options)
    @service_name = options.delete('service_name') || raise(ArgumentError, '`service_name` is required')
    @trusted_issuers = options.delete('trusted_issuers') || raise(ArgumentError, '`trusted_issuers` is required')
    @ttl = options.delete('ttl')
  end

  def encode(payload)
    raise(ArgumentError, '`aud` is required') if !payload.key?('aud') && !payload.key?(:aud)

    raise(ArgumentError, '`exp` is required') if !payload.key?('exp') && !payload.key?(:exp) && !@ttl
    payload = { exp: Time.now.to_i + @ttl }.merge(payload) if @ttl

    payload = payload.merge(iss: @service_name)
    JWT.encode(payload, private_key, ALGO, { kid: key_id })
  end

  def decode(jwt, options = {})
    options = options.merge(
      algorithm: ALGO,
      required_claims: ['exp', 'iss', 'aud'],
      verify_iss: true,
      iss: @trusted_issuers.keys,
      verify_aud: true,
      aud: @service_name
    )
    JWT.decode(jwt, nil, true, options) do |header, payload|
      OpenSSL::PKey::RSA.new(issuer_public_key(iss: payload['iss'], kid: header['kid']))
    end
  end

  def public_key(kid = key_id)
    @public_key ||= {}
    @public_key[kid.to_s] ||= with_redis { |redis| redis.get(cache_key(:public_key, kid)) }
  end

  def regenerate_key(old_key_ttl: OLD_KEY_TTL)
    rsa_private = OpenSSL::PKey::RSA.generate(2048)
    rsa_public = rsa_private.public_key
    next_key_id = key_id + 1
    with_redis do |redis|
      redis.multi do |multi|
        # expire current token
        multi.expire(cache_key(:private_key, key_id), old_key_ttl)
        multi.expire(cache_key(:public_key, key_id), old_key_ttl)
        # set new token
        multi.set(cache_key(:private_key, next_key_id), rsa_private.to_pem)
        multi.set(cache_key(:public_key, next_key_id), rsa_public.to_pem)
        multi.set('permission_token:key_id', next_key_id)
      end
    end
    # drop memoization
    @private_key = rsa_private
    @key_id = next_key_id
  end

  def key_id
    @key_id ||= with_redis { |c| c.get(cache_key(:key_id)).to_i }
  end

  private

  def issuer_public_key(iss:, kid:)
    @issuer_public_key ||= {}
    @issuer_public_key[iss] ||= {}
    @issuer_public_key[iss][kid] ||= if iss == @service_name
                                       public_key(kid)
                                     else
                                       redis_fetch(cache_key(:issuer_public_key, iss, kid), ex: 1.day) do
                                         retrieve_issuer_key(iss, kid)
                                       end
                                     end
  end

  def retrieve_issuer_key(iss, kid)
    # TODO: add more checks
    response = Curl.get(@trusted_issuers.dig(iss, 'url'), kid: kid)
    JSON.parse(response.body)['public_key']
  end

  def redis_fetch(key, options = {})
    res = with_redis { |redis| redis.get(key) }
    return res if res

    res = yield
    with_redis { |redis| redis.set(key, res, **options) }
    res
  end

  def private_key
    @private_key ||= OpenSSL::PKey::RSA.new(with_redis { |c| c.get(cache_key(:private_key, key_id)) })
  end

  def cache_key(*args)
    [:token_manager, @service_name, *args].join(':')
  end

  def with_redis
    raise NotImplementedError
  end
end
