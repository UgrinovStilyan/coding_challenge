defmodule UtrustChallengeWeb.PaymentsControllerTest do
  use UtrustChallengeWeb.ConnCase, async: true

  alias UtrustChallengeWeb.PaymentsController

  setup do
    %{
      valid_tx_hash: "0xd8d4c7ca8e6a0fe71eacc5f8e0c323c692eb46bc792f2b6b0f8f3db68a64f920",
      invalid_tx_hash: "123"
    }
  end

  @moduletag :capture_log

  doctest PaymentsController

  test "module exists" do
    assert is_list(PaymentsController.module_info())
  end

  describe "POST /make_payment" do
    test "user makes a payment with invalid tx_hash", %{
      conn: conn,
      invalid_tx_hash: invalid_tx_hash
    } do
      conn =
        post(conn, Routes.payments_path(conn, :make_payment), %{"tx_hash" => invalid_tx_hash})

      assert conn.status == 200
      assert conn.resp_body == "Invalid tx_hash"
    end

    test "user makes a payment with valid tx_hash", %{conn: conn, valid_tx_hash: valid_tx_hash} do
      conn = post(conn, Routes.payments_path(conn, :make_payment), %{"tx_hash" => valid_tx_hash})

      assert conn.status == 200
      assert conn.resp_body == "Payment received"
    end
  end
end
