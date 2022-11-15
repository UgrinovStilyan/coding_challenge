defmodule UtrustChallenge.Etherscan.ProcManager do
  @moduledoc """
  A manager proc that makes sure that the etherscan proc/procs are running and restarts them if they crash.
  """

  alias UtrustChallenge.Etherscan.EtherscanProc

  require Logger

  use TypedStruct
  use GenServer, start: {__MODULE__, :start_link, []}

  @typedoc """
  - `refs` : A map of monitored references to the etherscan atoms they are for.
  """
  typedstruct do
    field(:refs, %{reference() => atom()}, default: %{})
  end

  ########################################### Public API ###########################################

  @doc """
  Starts the etherscan manager proc.
  """
  @spec start_link() :: GenServer.on_start()
  def start_link(), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  ################################### Gen Server Implementation ####################################

  @impl GenServer
  def init(_) do
    {:ok, %__MODULE__{}, {:continue, :start_etherscan_procs}}
  end

  @impl GenServer
  def handle_continue(:start_etherscan_procs, %__MODULE__{} = state) do
    case find_or_start_and_monitor(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _} -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _, reason}, %__MODULE__{} = state) do
    Process.demonitor(ref, [:flush])
    {_etherscan_atom, refs} = Map.pop(state.refs, ref)
    new_state = %__MODULE__{state | refs: refs}

    if reason in [:normal, :noproc] do
      {:noreply, new_state}
    else
      Logger.warn("EtherscanProc crashed with reason #{inspect(reason)}, restarting...")

      case find_or_start_and_monitor(new_state) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, _} -> {:noreply, state}
      end
    end
  end

  @impl GenServer
  def handle_info(_msg, %__MODULE__{} = state), do: {:noreply, state}

  ######################################## Helper Functions ########################################

  @doc """
  Attempts to find or start the etherscan proc, then monitors it and tracks the monitor ref.

  - `state` : The state of the GenServer.
  """
  @spec find_or_start_and_monitor(state :: t()) :: {:ok, t()} | {:error, term()}
  def find_or_start_and_monitor(%__MODULE__{} = state) do
    with {:ok, pid} <- EtherscanProc.find_or_start_etherscan_proc() do
      ref = Process.monitor(pid)
      refs = Map.put(state.refs, ref, :etherscan)

      {:ok, %__MODULE__{state | refs: refs}}
    else
      {:error, e} ->
        Logger.error("Unable to start etherscan proc: #{inspect(e)}")
        {:error, e}
    end
  end
end
