defmodule Briskula.Card do
  @moduledoc """
  A card in the Triestine deck
  """
  defstruct [:suit, :rank]

  @type t :: %__MODULE__{
          suit: atom(),
          rank: atom()
        }
end
