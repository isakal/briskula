defmodule Briskula.Repo do
  use Ecto.Repo,
    otp_app: :briskula,
    adapter: Ecto.Adapters.Postgres
end
