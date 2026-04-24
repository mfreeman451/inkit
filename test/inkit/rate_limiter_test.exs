defmodule Inkit.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Inkit.RateLimiter

  setup do
    prior = Application.get_env(:inkit, :rate_limit)

    on_exit(fn ->
      RateLimiter.reset()
      if prior, do: Application.put_env(:inkit, :rate_limit, prior)
    end)

    RateLimiter.reset()
    :ok
  end

  test "allows requests under the limit and rejects the one over" do
    Application.put_env(:inkit, :rate_limit,
      enabled: true,
      window_ms: 60_000,
      max_requests: 3
    )

    key = {:test, "1.2.3.4"}

    assert {:ok, %{remaining: 2}} = RateLimiter.check(key)
    assert {:ok, %{remaining: 1}} = RateLimiter.check(key)
    assert {:ok, %{remaining: 0}} = RateLimiter.check(key)

    assert {:error, :rate_limited, %{limit: 3, retry_after_ms: retry_after}} =
             RateLimiter.check(key)

    assert retry_after > 0
  end

  test "different keys have independent counters" do
    Application.put_env(:inkit, :rate_limit,
      enabled: true,
      window_ms: 60_000,
      max_requests: 1
    )

    assert {:ok, _} = RateLimiter.check({:test, "a"})
    assert {:error, :rate_limited, _} = RateLimiter.check({:test, "a"})
    assert {:ok, _} = RateLimiter.check({:test, "b"})
  end

  test "disabled limiter is always a pass" do
    Application.put_env(:inkit, :rate_limit, enabled: false)

    for _ <- 1..100 do
      assert {:ok, %{remaining: :infinity}} = RateLimiter.check({:test, "unbounded"})
    end
  end
end
