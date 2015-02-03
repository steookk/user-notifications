module NotificationsHelper
  def count_new_notifications
    num = current_user.count_new_notifications
    num <= 30 ? num : '30+'
  end

  def notification_icon(notification)
    "icons/notifications/#{type(notification)}_notification.png"
  end

  def notification_body(notification)
    send("#{type(notification)}_notification_body", notification)
  end

  def notification_date(notification)
    content_tag(:span, time_ago_in_words(notification.time), :class => "#{'underlined' if notification.new?}")
  end

  def form_for_notifications_last_read(user)
    content_tag(:div, id: "notifications_last_read_form", style: "display:none;" ) do 
      form_for(:user, url: notifications_last_read_user_path(user), remote: true, method: :patch) do |f|
        f.submit ""
      end
    end
  end

  def click_on_notifications_last_read
    raw('$("#notifications_last_read_form input").click();')
  end

  private 
  def type(notification)
    notification.class.to_s.gsub("Notification", '').downcase
  end

  #generic notification body, used for dev/testing and as example
  def _notification_body(notification)
    content_tag(:div, "generic notification") + 
      content_tag(:div, time_ago_in_words(notification.time))
  end

  def follower_notification_body(n)
    content_tag(:div, :class => 'row') do
      content_tag(:div, image_tag(n.actor_pic_url, :size => "50x50", :title => "#{n.actor_name} photo"),
                  :class => 'small-2 columns userpic') + 
      content_tag(:div, :class => 'small-10 columns') do
        link_to(n.actor_name, user_path(n.actor_id)) + 
        " ti sta seguendo."
      end
    end
  end

  def like_notification_body(n)
    post_notification_body(n) do
      content_tag(:span, 'A ') +
      link_to_actor(n) + 
      'piace' +
      "#{n.post_type.eql?('Photo') ? ' la tua' : ' il tuo'}" +
      link_to_post(n)
    end
  end

  def comment_notification_body(n)
    post_notification_body(n) do
      link_to_actor(n) + 
      ' ha commentato ' +
      raw(
        if n.user_id.eql?(n.post_user_id)
          "#{n.post_type.eql?('Photo') ? 'la tua' : 'il tuo'}" + link_to_post(n)
        elsif n.actor_id.eql? n.post_user_id
          "#{n.post_type.eql?('Photo') ? 'la sua' : 'il suo'}" + link_to_post(n)
        else
          "#{n.post_type.eql?('Photo') ? 'la' : (n.post_type.eql?('Status') ? 'lo' : 'il')}" +
          link_to_post(n) +
          " di #{n.post_user_name}"
        end) +
      content_tag(:div, content_tag(:small, "\"#{n.comment_preview}\""))
    end
  end

  # skeleton for all kinds of post related notifications
  def post_notification_body(n)
    content_tag(:div, :class => 'row') do
      # left: actor's profile pic
      content_tag(:div, image_tag(n.actor_pic_url, :size => "50x50", :title => "#{n.actor_name} photo"),
                  :class => 'small-2 columns userpic') + 
      # center: text of the nofification
      content_tag(:div, :class => "small-#{n.post_thumbnail_url ? '8' : '10'} columns") do
        yield 
      end +
      # right: eventual post thumbnail 
      (content_tag(:div, image_tag(n.post_thumbnail_url, :size => "50x50", :title => "post photo"), 
                 :class => 'small-2 columns') if n.post_thumbnail_url)
    end
  end

  def link_to_actor(n)
    link_to("#{n.actor_name} ", user_path(n.actor_id))
  end

  def link_to_post(n)
    link_to(" #{n.post_type.downcase}", send("#{n.post_type.downcase}_path", n.post_id))
  end

end
