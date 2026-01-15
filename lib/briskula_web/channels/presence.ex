defmodule BriskulaWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](https://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :briskula,
    pubsub_server: Briskula.PubSub

    def init(_opts) do
      # This initializes the Presence process's internal state
      {:ok, %{}}
    end

end
