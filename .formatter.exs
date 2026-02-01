[
  import_deps: [
    :ash_state_machine,
    :ash_sqlite,
    :ash_oban,
    :oban,
    :ash_phoenix,
    :ash,
    :ash_authentication,
    :ash_authentication_phoenix,
    :ash_admin,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
