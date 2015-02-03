class NotificationsController < ApplicationController
  before_filter :authenticate_user!

  def index
    @notifications = current_user.notifications(unread_only: false, clean: true, options: {max_num: 30})
    current_user.pending_last_read = Time.now
  end
end
