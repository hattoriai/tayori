defmodule Tayori.TestTest do
  use TayoriTest.ConnCase

  import Tayori.Test

  test "publish!, unread, open_news and close_news", %{conn: conn} do
    conn = with_session(conn, %{"reader" => %{"id" => "u1", "segments" => ["plan:pro"]}})
    {:ok, view, _html} = live(conn, "/")
    assert unread(view) == 0

    publish!("Faster search", categories: ["Improved"])

    publish!("Shared boards",
      segments: ["plan:pro"],
      translations: %{"pt-PT" => "Quadros partilhados"}
    )

    publish!("Free only", segments: ["plan:free"])
    publish!("Later", at: minutes(30))

    assert unread(view) == 2

    assert [
             %{title: "Shared boards", new: true},
             %{title: "Faster search", categories: ["Improved"], new: true}
           ] = open_news(view)

    assert unread(view) == 0
    :ok = close_news(view)
    refute has_element?(view, "#tayori-panel")

    publish!("Fresh")
    assert unread(view) == 1
    assert [%{title: "Fresh", new: true} | _] = open_news(view)
  end
end
