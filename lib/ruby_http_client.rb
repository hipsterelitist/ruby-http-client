# Quickly and easily access any REST or REST-like API.
module SendGrid
  require 'json'
  require 'net/http'
  require 'net/https'

  # Holds the response from an API call.
  class Response
    # * *Args*    :
    #   - +response+ -> A NET::HTTP response object
    #
    attr_reader :status_code, :response_body, :response_headers
    def initialize(response)
      @status_code = response.code
      @response_body = response.body
      @response_headers = response.to_hash.inspect
    end
  end

  # A simple REST client.
  class Client
    attr_reader :host, :request_headers, :url_path
    # * *Args*    :
    #   - +host+ -> Base URL for the api. (e.g. https://api.sendgrid.com)
    #   - +request_headers+ -> A hash of the headers you want applied on
    #                          all calls
    #   - +version+ -> The version number of the API.
    #                  Subclass add_version for custom behavior.
    #                  Or just pass the version as part of the URL
    #                  (e.g. client._("/v3"))
    #   - +url_path+ -> A list of the url path segments
    #
    def initialize(host: nil, request_headers: nil, version: nil, url_path: nil)
      @host = host
      @request_headers = request_headers ? request_headers : {}
      @version = version
      @url_path = url_path ? url_path : []
      @methods = %w(delete get patch post put)
      @query_params = nil
      @request_body = nil
    end

    # Update the headers for the request
    #
    # * *Args*    :
    #   - +request_headers+ -> Hash of request header key/values
    #
    def update_headers(request_headers)
      @request_headers = @request_headers.merge(request_headers)
    end

    # Build the final request headers
    #
    # * *Args*    :
    #   - +request+ -> HTTP::NET request object
    # * *Returns* :
    #   - HTTP::NET request object
    #
    def build_request_headers(request)
      @request_headers.each do |key, value|
        request[key] = value
      end
      request
    end

    # Add the API version, subclass this function to customize
    #
    # * *Args*    :
    #   - +url+ -> An empty url string
    # * *Returns* :
    #   - The url string with the version pre-pended
    #
    def add_version(url)
      url.concat("/#{@version}")
      url
    end

    # Add query parameters to the url
    #
    # * *Args*    :
    #   - +url+ -> path to endpoint
    #   - +query_params+ -> hash of query parameters
    # * *Returns* :
    #   - The url string with the query parameters appended
    #
    def build_query_params(url, query_params)
      url.concat('?')
      count = 0
      query_params.each do |key, value|
        url.concat('&') if count > 0
        url.concat("#{key}=#{value}")
        count += 1
      end
      url
    end

    # Set the query params, request headers and request body
    #
    # * *Args*    :
    #   - +args+ -> array of args obtained from method_missing
    #
    def build_args(args)
      args.each do |arg|
        arg.each do |key, value|
          case key.to_s
          when 'query_params'
            @query_params = value
          when 'request_headers'
            update_headers(value)
          when 'request_body'
            @request_body = value
          end
        end
      end
    end

    # Build the final url
    #
    # * *Args*    :
    #   - +query_params+ -> A hash of query parameters
    # * *Returns* :
    #   - The final url string
    #
    def build_url(query_params: nil)
      url = ''
      url = add_version(url) if @version
      @url_path.each do |x|
        url.concat("/#{x}")
      end
      url = build_query_params(url, query_params) if query_params
      URI.parse("#{@host}#{url}")
    end

    # Build the API request for HTTP::NET
    #
    # * *Args*    :
    #   - +name+ -> method name, received from method_missing
    #   - +args+ -> args passed to the method
    # * *Returns* :
    #   - A Response object from make_request
    #
    def build_request(name, args)
      build_args(args) if args
      uri = build_url(query_params: @query_params)
      http = Net::HTTP.new(uri.host, uri.port)
      http = add_ssl(http)
      net_http = Kernel.const_get('Net::HTTP::' + name.to_s.capitalize)
      request = net_http.new(uri.request_uri)
      request = build_request_headers(request)
      request.body = @request_body.to_json if @request_body
      make_request(http, request)
    end

    # Make the API call and return the response. This is separated into
    # it's own function, so we can mock it easily for testing.
    #
    # * *Args*    :
    #   - +http+ -> NET:HTTP request object
    #   - +request+ -> NET::HTTP request object
    # * *Returns* :
    #   - Response object
    #
    def make_request(http, request)
      response = http.request(request)
      Response.new(response)
    end

    # Allow for https calls
    #
    # * *Args*    :
    #   - +http+ -> HTTP::NET object
    # * *Returns* :
    #   - HTTP::NET object
    #
    def add_ssl(http)
      protocol = host.split(':')[0]
      if protocol == 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      http
    end

    # Add variable values to the url.
    # (e.g. /your/api/{variable_value}/call)
    # Another example: if you have a ruby reserved word, such as true,
    # in your url, you must use this method.
    #
    # * *Args*    :
    #   - +name+ -> Name of the url segment
    # * *Returns* :
    #   - Client object
    #
    def _(name = nil)
      url_path = name ? @url_path.push(name) : @url_path
      @url_path = []
      Client.new(host: @host, request_headers: @request_headers,
                 version: @version, url_path: url_path)
    end

    # Dynamically add segments to the url, then call a method.
    # (e.g. client.name.name.get())
    #
    # * *Args*    :
    #   - The args are autmoatically passed in
    # * *Returns* :
    #   - Client object or Response object
    #
    def method_missing(name, *args, &_block)
      # Capture the version
      if name.to_s == 'version'
        @version = args[0]
        return _
      end
      # We have reached the end of the method chain, make the API call
      return build_request(name, args) if @methods.include?(name.to_s)
      # Add a segment to the URL
      _(name)
    end
  end
end