# UtrustChallenge

## Project setup

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`
  * Run credo `mix credo --strict`
  * Run dialyzer `mix dialyzer`
  * Run tests `mix test`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.


## Implementation details

Implement a supervised gen_server process that will be responsible for making calls to 
Etherscan.io API and hold payment statuses in its state. For the purposes of this exercise I avoided 
using a database to keep things simpler.

The Endpoint for "making a payment" makes a gen_server call to the `EtherscanProc` and 
returns `Payment received` if `tx_hash` is valid(i.e. successfully retrieved from `EtherscanProc` state or `Etherscan.io` API)
or `Invalid tx_hash` if the provided `tx_hash` is invalid.

If a payment is not confirmed than the `EtherscanProc` will attempt again in 5 seconds
(this number was picked based on how long on average it takes to get two confirmations and
the limitation of the max number of requests per 5 seconds constraint for `Etherscan.io`). 
This attempt is async using `Process.send_after/3` so that it does not block the process from responding other requests.

Any requests made to the `EtherscanProc` attempt to retrieve the payment status from the gen_server's
state first before making calls to `Etherscan.io` If a status for the `tx_hash` is not found in memory
then a call to `Etherscan.io` is made and its response `:payment_pending` or `:payment_complete`
is stored in the `EtherscanProc` state. Additionally, if status is pending and retries are made, when
eventually conditions for status complete are met the state is once more update for the corresponding `tx_hash`.
