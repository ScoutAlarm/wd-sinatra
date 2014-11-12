module WDSinatra
  class Middleware
    class Authentication

      MOBILE_X_HEADER   = 'HTTP_X_MOBILE_TOKEN'
      INTERNAL_X_HEADER = 'HTTP_X_INTERNAL_API_KEY'

      MEMBER_X_GLOBAL_ID_HEADER = 'HTTP_X_MEMBER_GLOBAL_ID'

      def initialize(app)
        @app = app

        if ENV['INTERNAL_X_HEADER']
          @allowed_internal_tokens = ENV['INTERNAL_X_HEADER'].split(',').map { |pw| pw.strip }.freeze
        end
      end

      def call(env)
        http_mobile_x_header = env[MOBILE_X_HEADER]
        http_internal_x_header = env[INTERNAL_X_HEADER]

        if http_mobile_x_header.present?
          env[MEMBER_X_GLOBAL_ID_HEADER] = mobile_auth_check(http_mobile_x_header)
        elsif http_internal_x_header.present?
          internal_api_key_check(http_internal_x_header)
        else
          halt_access_denied!
        end

        @app.call(env)
      end

      def mobile_auth_check(http_mobile_x_header)
        mobile_token_cache_expiration = ENV['MOBILE_TOKEN_CACHE_EXPIRATION'] ||= 5
        cached_valid_auth_result = WDSinatra.cache.fetch(http_mobile_x_header.to_sym, expires_in: mobile_token_cache_expiration.to_i.minutes) do
          data = ScoutApiClient::Auth::MobileToken.valid?(http_mobile_x_header)
          valid = data[:token_valid]
          member_global_id = data[:member_global_id]
          { valid: true, member_global_id: member_global_id }
        end

        unless cached_valid_auth_result[:valid]
          LOGGER.error "Invalid Token #{http_mobile_x_header}"
          halt_access_denied!
        else
          cached_valid_auth_result[:member_global_id]
        end
      end

      def internal_api_key_check(http_internal_x_header)
        unless @allowed_internal_tokens.nil?
          unless @allowed_internal_tokens.include? http_internal_x_header
            LOGGER.error "Invalid Token #{http_internal_x_header}"
            halt_access_denied!
          end
        else
          [403, {'Content-Type' => 'application/json'}, {:error => "internal token not configured" }.to_json]
        end
      end

      def halt_access_denied!
        [403, {'Content-Type' => 'application/json'}, {:error => "access denied!" }.to_json]
      end

    end
  end
end
