defmodule InvaderWeb.PageControllerTest do
  use InvaderWeb.ConnCase

  test "GET / redirects to sign-in when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/sign-in"
  end

  test "GET /sign-in shows sign in page", %{conn: conn} do
    conn = get(conn, ~p"/sign-in")
    assert html_response(conn, 200) =~ "PLAYER LOGIN"
  end
end
