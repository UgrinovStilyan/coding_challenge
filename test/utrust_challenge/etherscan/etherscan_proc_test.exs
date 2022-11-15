defmodule UtrustChallenge.Etherscan.EtherscanProcTest do
  use ExUnit.Case

  alias UtrustChallenge.Etherscan.EtherscanProc

  @moduletag :capture_log

  doctest EtherscanProc

  setup do
    %{api_key: Application.get_env(:utrust_challenge, :etherscan_api_key)}
  end

  test "module exists" do
    assert is_list(EtherscanProc.module_info())
  end

  describe "block_number_to_int/1" do
    test "when provided block number is nil, return `nil`" do
      assert {:error, :invalid_tx_hash} == EtherscanProc.block_number_to_int(nil)
    end

    test "when provided block number is valid, returns it as integer " do
      assert {:ok, 15_976_628} == EtherscanProc.block_number_to_int("0xf3c8b4")
    end
  end

  describe "handle_check_transaction/2" do
    test "when provided tx_hash is invalid, returns error", %{api_key: api_key} do
      # adding sleeps to guarantee successful response because these calls hit etherscan to avoid mocking http responses
      Process.sleep(5_000)
      assert {:error, :invalid_tx_hash} == EtherscanProc.handle_check_transaction(api_key, "123")
    end

    test "when provided tx_hash is valid and more there are more than two block confirmations, " <>
           "returns `payment_complete`",
         %{api_key: api_key} do
      # adding sleeps to guarantee successful response because these calls hit etherscan to avoid mocking http responses
      Process.sleep(5_000)

      assert {:ok, :payment_complete} ==
               EtherscanProc.handle_check_transaction(
                 api_key,
                 "0xd8d4c7ca8e6a0fe71eacc5f8e0c323c692eb46bc792f2b6b0f8f3db68a64f920"
               )
    end
  end
end
