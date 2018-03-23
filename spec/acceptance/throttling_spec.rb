require_relative "../spec_helper"
require "timecop"

describe "#throttle" do
  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  it "allows one request per minute by IP" do
    Rack::Attack.throttle("by ip", limit: 1, period: 60) do |request|
      request.ip
    end

    get "/", {}, "REMOTE_ADDR" => "1.2.3.4"

    assert_equal 200, last_response.status

    get "/", {}, "REMOTE_ADDR" => "1.2.3.4"

    assert_equal 429, last_response.status
    assert_equal "60", last_response.headers["Retry-After"]
    assert_equal "Retry later\n", last_response.body

    get "/", {}, "REMOTE_ADDR" => "5.6.7.8"

    assert_equal 200, last_response.status

    Timecop.travel(60) do
      get "/", {}, "REMOTE_ADDR" => "1.2.3.4"

      assert_equal 200, last_response.status
    end
  end

  it "supports limit to be dynamic" do
    # Could be used to have different rate limits for authorized
    # vs general requests
    limit_proc = lambda do |request|
      if request.env["X-APIKey"] == "private-secret"
        2
      else
        1
      end
    end

    Rack::Attack.throttle("by ip", limit: limit_proc, period: 60) do |request|
      request.ip
    end

    get "/", {}, "REMOTE_ADDR" => "1.2.3.4"
    assert_equal 200, last_response.status

    get "/", {}, "REMOTE_ADDR" => "1.2.3.4"
    assert_equal 429, last_response.status

    get "/", {}, "REMOTE_ADDR" => "5.6.7.8", "X-APIKey" => "private-secret"
    assert_equal 200, last_response.status

    get "/", {}, "REMOTE_ADDR" => "5.6.7.8", "X-APIKey" => "private-secret"
    assert_equal 200, last_response.status

    get "/", {}, "REMOTE_ADDR" => "5.6.7.8", "X-APIKey" => "private-secret"
    assert_equal 429, last_response.status
  end

  it "supports period to be dynamic" do
    # Could be used to have different rate limits for authorized
    # vs general requests
    period_proc = lambda do |request|
      if request.env["X-APIKey"] == "private-secret"
        10
      else
        30
      end
    end

    Rack::Attack.throttle("by ip", limit: 1, period: period_proc) do |request|
      request.ip
    end

    # Using Time#at to align to start/end of periods exactly
    # to achieve consistenty in different test runs

    Timecop.travel(Time.at(0)) do
      get "/", {}, "REMOTE_ADDR" => "1.2.3.4"
      assert_equal 200, last_response.status

      get "/", {}, "REMOTE_ADDR" => "1.2.3.4"
      assert_equal 429, last_response.status
    end

    Timecop.travel(Time.at(10)) do
      get "/", {}, "REMOTE_ADDR" => "1.2.3.4"
      assert_equal 429, last_response.status
    end

    Timecop.travel(Time.at(30)) do
      get "/", {}, "REMOTE_ADDR" => "1.2.3.4"
      assert_equal 200, last_response.status
    end

    Timecop.travel(Time.at(0)) do
      get "/", {}, "REMOTE_ADDR" => "5.6.7.8", "X-APIKey" => "private-secret"
      assert_equal 200, last_response.status

      get "/", {}, "REMOTE_ADDR" => "5.6.7.8", "X-APIKey" => "private-secret"
      assert_equal 429, last_response.status
    end

    Timecop.travel(Time.at(10)) do
      get "/", {}, "REMOTE_ADDR" => "5.6.7.8", "X-APIKey" => "private-secret"
      assert_equal 200, last_response.status
    end
  end
end