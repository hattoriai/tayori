# The router macros of Tayori, without parentheses, in Tayori and in the
# apps that import its formatter (import_deps: [:tayori]).
router = [
  tayori_admin: 1,
  tayori_admin: 2,
  tayori_api: 1,
  tayori_api: 2,
  tayori_page: 1,
  tayori_page: 2
]

# Sake is optional, and left out of the oldest dependencies (TAYORI_OLDEST).
sake = if System.get_env("TAYORI_OLDEST") in ["1", "true"], do: [], else: [:sake]

[
  import_deps:
    [:ecto, :ecto_sql, :phoenix, :phoenix_html, :phoenix_live_view, :phoenix_mountable] ++
      sake,
  locals_without_parens: [attr: 2, attr: 3, slot: 1, slot: 2, slot: 3] ++ router,
  export: [locals_without_parens: router],
  inputs: ["{mix,.formatter,dev}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
