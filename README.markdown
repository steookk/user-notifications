# Note
This is a work in progress. 
todo: make it a gem, write proper documentation

# What this is about
This gem provides simple notifications mechanism to users in your website, like those that you see on Facebook or any other social network.
The aim is to define type of notifications, store them and finally show them to the user.

It uses Redis to store notifications, therefore it's completely indipendent on the type of database you're using.
It lets you create your own notification types with ease, and it provides common notifications types so that you can use them out of the box.
It relies on conventions over configuration.

# How to use it
As an example, let's say that you want to create a notification everytime a user follows another user.
The followed user will see an unread notification (for example an icon in the header) and it will be able to read the list of notifications at www.yourproject.com/notifications
Notifications are marked as read when the user visits */notification* page.

## Model

In the model where you want to apply notifications (tipically User), write:

```ruby
extend Notification::UserHelpers
has_notifications 
```

If your model is not named User or if you don't use a *.find(id)* method, you need to pass a block specifying how to retrieve records from your db, i.e.:

```ruby
has_notifications { |id| Person.find(id) }
```

## Controller
Use the the method *notifications* to retrieve notifications and set *last_read*:

```ruby
@notifications = current_user.notifications(unread_only: false, clean: true, options: {max_num: 30})
current_user.pending_last_read = Time.now
```

## Views
Your header displaying the number of new notifications could look like this:

```ruby
<li>
  <%= link_to notifications_path, id: "notifications-icon" do %>
    <% if current_user.has_new_notifications? %>
      <span class="round label">
        <span style="margin-right: 3px;"><%= count_new_notifications %></span>
    <% else %>
      <span class="round secondary label">
    <% end %>
    <%= image_tag("icons/fischietto.png") %></span>
  <% end %>
</li>
```

Your index page could look like this:

```ruby
<% if @notifications.empty? %>
  No notifications
<% else %>
  <%= render partial: 'notification', collection: @notifications %>
<% end %>

<%= form_for_notifications_last_read(current_user) %>

<script>
  <%= click_on_notifications_last_read %>
</script>
```

Each notification is based on three components:

```ruby
<div class="row">
  
  <div class="small-1 column notification-icon">
    <%= image_tag notification_icon(notification) %>
  </div>

  <div class="small-2 column notification-date">
    <small><%= notification_date(notification) %></small>
  </div>

  <div class="small-9 columns notification-body">
    <%= notification_body(notification) %>
  </div>

</div>
```

### Assets

## Routes

```ruby  
resources :notifications, :only => :index
```

## Custom notifications
Obviously you will want to create your own custom notifications.
To do so, follow this template:

```ruby
class FollowerNotification < Notification
  attr_accessor :actor_id
  attr_accessor :actor_name
  attr_accessor :actor_pic_url

  def initialize(*args)
    if args.size == 2
      follower = args[0]
      follower = args[1]
      actor_id = follower.id
      actor_name = "#{follower.firstname} #{follower.lastname}"
      actor_pic_url = follower.photo.url
      super(followed) unless followed.nil?
    else
      yield self if block_given?
    end
  end
end
```

### Helpers
See notifications_helper.rb

# When is the best moment to create a notification? 
Continuing with our example, there is an important question that might arise: should I create a notification everytime a user follows another user (like push notifications, so you'll end up with one notification per one follow action) or should I create a lazy notification with the sum of the follow actions (something like: Five people are now following you) at the moment the user is visiting your site?
Obviously that's your choice, but as a general guidelines I would suggest to go for lazy notifications for notifications you want to store, and use push notifications (for which you don't need this gem) if you really need them.

However, lazy notifications have a price: in our example, you need to store how many followers the user had last time he visited and make a diff.
Therefore, in same cases it makes sense to still create and store a notification each time a certain action is accomplished, because it would be way too expensive to create lazy notifications: that's the case of notifications for new comments on posts the user has alreday commented. It also makes sense to present a notification for each comment.
You could evaluate an hibrid approach too: use lazy notifications (ie: Five your friends have commented on Walter's post), and to do so store which posts have been commented so that it's then quick to retrieve these posts at the moment of the notifications' creation.
If you have more strategies, write a comment!


