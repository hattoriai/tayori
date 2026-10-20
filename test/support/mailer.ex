defmodule TayoriTest.Mailer do
  @moduledoc "The emails of the tests, sent to the test's process."
  use Swoosh.Mailer, otp_app: :tayori
end
