class TokenManager::FaradayMiddleware
  AUTH_HEADER = 'Authorization'.freeze

  def initialize(app = nil, &block)
    @app = app
    @block = block
  end

  def call(env)
    env[:request_headers][AUTH_HEADER] ||= %(Token token="#{@block.call}")

    @app.call(env)
  end
end
