module ApplicationCable
  # This is a single-user local application, so connections are not identified.
  class Connection < ActionCable::Connection::Base
  end
end
