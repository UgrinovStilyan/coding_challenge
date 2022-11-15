defmodule UtrustChallenge.Etherscan.EtherscanProc do
  @moduledoc """
  This module is responsible for making requests to Etherscan API.
  """

  require Logger

  import Swarm, only: [whereis_or_register_name: 4]

  use TypedStruct
  use GenServer

  @base_url "https://api.etherscan.io/api"
  # 5 seconds in milliseconds
  @polling_interval 5 * 1_000

  @typedoc """
  The proc state:

  - `api_key` : The API key needed to make requests to Etherscan API.
  - `transaction_statuses` :  A map of tx_hashes to transaction status atoms.
  """
  typedstruct do
    field(:api_key, String.t() | nil, default: nil)
    field(:transaction_statuses, %{String.t() => atom()}, default: %{})
  end

  ########################################### Public API ###########################################

  @doc """
  Returns the status of a payment give its tx_hash.
  """
  @spec confirm_payment(tx_hash :: String.t()) ::
          {:ok, :payment_complete | :pending_transaction}
          | {:error, :invalid_tx_hash | :requests_limit_reached}
  def confirm_payment(tx_hash) do
    with {:ok, pid} <- find_or_start_etherscan_proc() do
      GenServer.call(pid, {:check_transaction, tx_hash})
    end
  end

  @doc """
  Finds or starts the etherscan proc via Swarm and registers it.
  """
  @spec find_or_start_etherscan_proc() :: {:ok, pid()} | {:error, term()}
  def find_or_start_etherscan_proc() do
    case whereis_or_register_name(__MODULE__, __MODULE__, :start_link, []) do
      {:ok, pid} -> {:ok, pid}
      err -> err
    end
  end

  @doc """
  Starts the etherscan proc.
  """
  @spec start_link() :: GenServer.on_start()
  def start_link() do
    api_key = Application.get_env(:utrust_challenge, :etherscan_api_key)
    GenServer.start_link(__MODULE__, %__MODULE__{api_key: api_key})
  end

  ################################### Gen Server Implementation ####################################

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:check_transaction, tx_hash}, _from, state) do
    case state.transaction_statuses[tx_hash] do
      nil ->
        case handle_check_transaction(state.api_key, tx_hash) do
          {:error, _msg} = err ->
            {:reply, err, state}

          {:ok, result} ->
            Logger.info("Payment status not found in memory, making HTTP call to Etherscan.io")

            if result == :pending_transaction do
              Process.send_after(self(), {:check_transaction, tx_hash}, @polling_interval)

              Logger.info(
                "Payment status is still pending, rechecking in #{inspect(trunc(@polling_interval / 1_000))} seconds!"
              )
            else
              Logger.info("Payment with tx_hash: #{inspect(tx_hash)} completed!")
            end

            new_transaction_statuses = Map.put(state.transaction_statuses, tx_hash, result)

            {:reply, {:ok, result},
             %__MODULE__{state | transaction_statuses: new_transaction_statuses}}
        end

      status ->
        Logger.info("Payment status retrieved from memory.")
        {:reply, {:ok, status}, state}
    end
  end

  def handle_call(msg, _from, state) do
    Logger.info("Unknown call received by etherscan_api proc #{msg}")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:check_transaction, tx_hash}, state) do
    case handle_check_transaction(state.api_key, tx_hash) do
      {:error, _error} = _err ->
        {:noreply, state}

      {:ok, :pending_transaction} ->
        Process.send_after(self(), {:check_transaction, tx_hash}, @polling_interval)

        Logger.info(
          "Payment status is still pending, rechecking in #{inspect(trunc(@polling_interval / 1_000))} seconds!"
        )

        {:noreply, state}

      {:ok, :payment_complete} ->
        Logger.info("Payment with tx_hash: #{inspect(tx_hash)} completed!")
        new_transaction_statuses = Map.put(state.transaction_statuses, tx_hash, :payment_complete)
        {:noreply, %__MODULE__{state | transaction_statuses: new_transaction_statuses}}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ######################################## Helper Functions ########################################

  @doc """
  Returns the integer corresponding to the block number or error if the block number is `nil`.

  - `block_number` - The block number for the transaction.
  """
  @spec block_number_to_int(block_number :: String.t() | nil) ::
          {:ok, pos_integer()} | {:error, :invalid_tx_hash}
  def block_number_to_int(nil), do: {:error, :invalid_tx_hash}

  def block_number_to_int(block_number) do
    "0x" <> hex = block_number
    {integer, _} = Integer.parse(hex, 16)
    {:ok, integer}
  end

  @doc """
  Return details for a transaction, given tx_hash.

  - `api_key` - The API key needed to make requests to Etherscan API
  - `tx_hash` - The tx_hash for which to grab the status
  """
  @spec request_transaction_details(api_key :: String.t(), tx_hash :: String.t()) ::
          {:error, :request_failed | :requests_limit_reached | HTTPoison.Error.t()} | {:ok, any}
  def request_transaction_details(api_key, tx_hash) do
    url =
      "#{@base_url}/?module=proxy&action=eth_getTransactionByHash&txhash=" <>
        tx_hash <> "&apiKey=#{api_key}"

    case get_request(url) do
      {:ok, "{\"status\":\"0\",\"message\":\"NOTOK\",\"result\":\"Max rate limit reached\"}"} ->
        {:error, :requests_limit_reached}

      resp ->
        resp
    end
  end

  @doc """
  Returns the latest block.

  - `api_key` - The API key needed to make requests to Etherscan API
  """
  @spec request_latest_block(api_key :: String.t()) ::
          {:error, :request_failed | :requests_limit_reached | HTTPoison.Error.t()} | {:ok, any}
  def request_latest_block(api_key) do
    url = "#{@base_url}/?module=proxy&action=eth_blockNumber&apiKey=#{api_key}"

    case get_request(url) do
      {:ok, "{\"status\":\"0\",\"message\":\"NOTOK\",\"result\":\"Max rate limit reached\"}"} ->
        {:error, :requests_limit_reached}

      resp ->
        resp
    end
  end

  @spec handle_check_transaction(api_key :: String.t(), tx_hash :: String.t()) ::
          {:ok, :payment_complete | :pending_transaction}
          | {:error, :invalid_tx_hash | :requests_limit_reached}
  def handle_check_transaction(api_key, tx_hash) do
    with {:ok, transaction_details} <- request_transaction_details(api_key, tx_hash),
         td_decoded_response <- Jason.decode!(transaction_details),
         {:ok, maybe_td_block_number_int} <-
           block_number_to_int(td_decoded_response["result"]["blockNumber"]),
         {:ok, latest_block} <- request_latest_block(api_key) do
      lb_decoded_response = Jason.decode!(latest_block)
      {:ok, lb_block_number_int} = block_number_to_int(lb_decoded_response["result"])

      case lb_block_number_int - maybe_td_block_number_int >= 2 do
        true -> {:ok, :payment_complete}
        false -> {:ok, :pending_transaction}
      end
    else
      {:error, _error} = err ->
        err
    end
  end

  @doc """
  Performs GET request against `url`. In case of timeout, it will retry `retry` number of times.
  If all retries have failed with timeouts, it will return error.

  - `url` - URL to request
  - `retry` - Number of retries on timeout
  """
  @spec get_request(String.t(), integer()) ::
          {:error, :request_failed | HTTPoison.Error.t()} | {:ok, String.t()}
  def get_request(url, retry \\ 5)

  def get_request(url, 0) do
    Logger.error("Request failed for #{url}")
    {:error, :request_failed}
  end

  def get_request(url, retry) do
    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{body: json}} ->
        {:ok, json}

      {:error, %HTTPoison.Error{id: nil, reason: :timeout}} ->
        get_request(url, retry - 1)

      {:error, _} = error ->
        error
    end
  end
end
