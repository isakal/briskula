# https://hexdocs.pm/ex_unit/ExUnit.html#configure/1
# https://hexdocs.pm/ex_unit/ExUnit.html#t:configure_opts/0

# Start the Registry for GameServer tests
{:ok, _} = Registry.start_link(keys: :unique, name: :BriskulaRegistry)

ExUnit.start(
  trace: true,
  seed: 0
)
