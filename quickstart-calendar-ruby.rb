# frozen_string_literal: true

require 'nylas'
require 'dotenv/load'
require 'sinatra'

set :show_exceptions, :after_handler
enable :sessions

error 404 do
  'No authorization code returned from Nylas'
end

error 500 do
  'Failed to exchange authorization code for token'
end

nylas = Nylas::Client.new(
  api_key: ENV['NYLAS_API_KEY'],
  api_uri: ENV['NYLAS_API_URI']
)

get '/nylas/auth' do
  config = {
    client_id: ENV['NYLAS_CLIENT_ID'],
    provider: 'google',
    redirect_uri: 'http://localhost:4567/oauth/exchange',
    login_hint: 'atejada@gmail.com',
    access_type: 'offline'
  }

  url = nylas.auth.url_for_oauth2(config)
  redirect url
end

get '/oauth/exchange' do
  code = params[:code]
  status 404 if code.nil?

  begin
    response = nylas.auth.exchange_code_for_token({
                                                    client_id: ENV['NYLAS_CLIENT_ID'],
                                                    redirect_uri: 'http://localhost:4567/oauth/exchange',
                                                    code: code
                                                  })
  rescue StandardError
    status 500
  else
    response[:grant_id]
    response[:email]
    session[:grant_id] = response[:grant_id]
  end
end

get '/nylas/primary-calendar' do
  query_params = { limit: 5 }
  calendars, = nylas.calendars.list(identifier: session[:grant_id],
                                    query_params: query_params)
  calendars.each do |calendar|
    @primary = calendar[:id] if calendar[:is_primary] == true
  end
  session[:primary] = @primary
rescue StandardError => e
  e.to_s
end

get '/nylas/list-events' do
  query_params = { calendar_id: session[:primary], limit: 5 }
  events, _request_ids = nylas.events.list(identifier: session[:grant_id],
                                           query_params: query_params)
  events.to_json
rescue StandardError => e
  e.to_s
end

# To handle time manipulation
class Numeric
  def minutes
    self / 1440.0
  end
  alias minute minutes

  def seconds
    self / 86_400.0
  end
  alias second seconds
end

get '/nylas/create-event' do
  now = DateTime.now
  now += 5.minutes
  start_time = Time.local(now.year, now.month, now.day,
                          now.hour, now.minute, now.second).strftime('%s')
  now += 35.minutes
  end_time = Time.local(now.year, now.month, now.day,
                        now.hour, now.minute, now.second).strftime('%s')

  query_params = { calendar_id: session[:primary] }

  request_body = {
    when: {
      start_time: start_time.to_i,
      end_time: end_time.to_i
    },
    title: 'Your event title here'
  }

  event, = nylas.events.create(identifier: session[:grant_id],
                               query_params: query_params, request_body: request_body)
  event.to_json
rescue StandardError => e
  e.to_s
end
