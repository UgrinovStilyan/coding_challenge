defmodule UtrustChallenge.Repo do
  use Ecto.Repo,
    otp_app: :utrust_challenge,
    adapter: Ecto.Adapters.Postgres
end
