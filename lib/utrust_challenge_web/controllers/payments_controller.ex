defmodule UtrustChallengeWeb.PaymentsController do
  @moduledoc false
  use UtrustChallengeWeb, :controller

  alias UtrustChallenge.Etherscan.EtherscanProc

  def index(conn, _params) do
    render(conn, "payments.html")
  end

  def make_payment(conn, params) do
    case EtherscanProc.confirm_payment(params["tx_hash"]) do
      {:ok, _resp} -> text(conn, "Payment received")
      {:error, _error} -> text(conn, "Invalid tx_hash")
    end
  end
end
