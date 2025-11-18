defmodule BriskulaWeb.PageController do
  use BriskulaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
