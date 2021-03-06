defmodule Blockchain.Miner.Worker do
  @moduledoc """
  Worker with mining process
  """
  alias Blockchain.Structures.SignedTx
  alias Blockchain.Structures.Block
  alias Blockchain.Structures.Header
  alias Blockchain.Structures.Header
  alias Blockchain.Utilities.Serialization
  alias Blockchain.Verify.Tx
  alias Blockchain.Pool.Worker, as: Pool
  alias Blockchain.Chain.Worker, as: Chain
  alias Blockchain.Keys.Mock

  use GenServer

  @limit_diff_target_zeroes <<0::256>>

  # Client API

  def start_link(_arg) do
    GenServer.start(__MODULE__, :ok, name: __MODULE__)
  end

  def start() do
    GenServer.call(__MODULE__, :start)
  end

  def get_state() do
    GenServer.call(__MODULE__, :check)
  end

  def mine_one_block() do
    candidate_block() |> Chain.add_block()
  end

  def stop() do
    GenServer.call(__MODULE__, :stop)
  end

  # Server callbacks

  def init(:ok) do
    state = %{miner: :stop, should_stop: false}
    {:ok, state}
  end

  def handle_info(:work, state) do
    mine_one_block()

    case state.should_stop do
      true -> nil
      false -> schedule_work()
    end

    {:noreply, state}
  end

  def handle_call(:start, _from, %{miner: :stop} = state) do
    schedule_work()
    {:reply, :ok, %{state | miner: :working, should_stop: false}}
  end

  def handle_call(:start, _from, %{miner: :working} = state) do
    {:reply, {:error, "Already working!"}, state}
  end

  def handle_call(:stop, _from, %{miner: :working} = state) do
    {:reply, :ok, %{state | miner: :stop, should_stop: true}}
  end

  def handle_call(:stop, _from, %{miner: :stop} = state) do
    {:reply, {:error, "Already stopped!"}, state}
  end

  def handle_call(:check, _from, state) do
    {:reply, state, state}
  end

  @spec candidate_block() :: Block.t()
  def candidate_block() do
    chain_state = Chain.get_state()
    txs = filter_txs()
    merkle_tree_hash = Chain.merkle_tree_hash(txs)

    previous_block_hash = Chain.last_block() |> Serialization.hash()
    difficulty_target = 2
    chain_state_root_hash = Chain.chain_state_root_hash(chain_state)
    txs_root_hash = merkle_tree_hash
    nonce = 0

    candidate_header =
      Header.create(
        previous_block_hash,
        difficulty_target,
        chain_state_root_hash,
        txs_root_hash,
        nonce
      )

    header = proof(candidate_header)
    Block.create(header, txs)
  end

  @spec proof(Header.t()) :: Header.t()
  defp proof(header) do
    hash_header = Serialization.hash(header)
    difficulty_target = header.difficulty_target
    <<max_zeroes::binary-size(difficulty_target), _::binary>> = @limit_diff_target_zeroes
    <<leading_zeroes::binary-size(difficulty_target), _::binary>> = hash_header

    if max_zeroes == leading_zeroes do
      header
    else
      new_header = %{header | nonce: header.nonce + 1}
      proof(new_header)
    end
  end

  defp schedule_work() do
    Process.send_after(self(), :work, 3000)
  end

  defp filter_txs() do
    candidate_txs_list = Pool.take_and_remove_all_tx()
    coinbase_tx = Mock.pub_key_miner() |> SignedTx.coinbase_tx()

    Enum.reduce(candidate_txs_list, [coinbase_tx], fn x, acc ->
      case Tx.verify(x) do
        true ->
          acc ++ [x]

        false ->
          Pool.add_tx(x)
          acc
      end
    end)
  end
end
