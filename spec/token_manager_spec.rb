# frozen_string_literal: true

class AuthToken < TokenManager
  private

  def with_redis
    yield(REDIS)
  end
end

RSpec.describe TokenManager do
  let(:encoder) { AuthToken.new({ service_name: 'encoder', token_ttl: 20 }) }
  let(:decoder) { AuthToken.new({ service_name: 'decoder', trusted_issuers: { encoder: { url: 'https://encoder.com/encoder' } } }) }

  it 'works' do
    expect(Curl).to receive(:get).with('https://encoder.com/encoder', { kid: encoder.key_id })
                                 .and_return(
                                   instance_double(
                                     Curl::Easy,
                                     response_code: 200,
                                     body: { public_key: encoder.public_key(encoder.key_id) }.to_json
                                   )
                                 )

    jwt = encoder.encode({ foo: :bar, aud: 'decoder' })
    expect(decoder.decode(jwt).first).to include('foo' => 'bar')
  end

  it 'has a version number' do
    expect(TokenManager::VERSION).not_to be_nil
  end
end
