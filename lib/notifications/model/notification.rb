require 'json'

# ----- base Notification class ---- 
class Notification
  # accessors
  def time
    Time.at @time
  end
  attr_writer :time

  attr_accessor :user_id

  def user
    @@user_proc ||= Proc.new { |id| User.find id }
    @@user_proc.call @user_id
  end

  def self.user_proc=(proc)
    @@user_proc = proc
  end

  def initialize(user=nil, time=Time.now)
    @type = self.class.to_s.gsub "Notification", ''
    @time ||= time.to_f
    @user_id ||= user.try(:id)
    yield self if block_given?
  end

  def save
    RedisInstance.get_instance.zadd user.sortedset_key, score, to_json
  end

  def self.create(*args)
    notification = new(*args)
    notification.save ? notification : nil 
  end

  def self.deserialize(string)
    hash = JSON.parse string
    type = hash['type']
    hash.delete('type')
    "#{type}Notification".constantize.new do |notification|
      hash.each do |key,value|
        notification.send("#{key}=", value)
      end
    end
  end

  def ==(notification)
    if instance_variables == notification.instance_variables
      instance_variables.each do |var|
        return false unless instance_variable_get(var) == notification.instance_variable_get(var)
      end
      true
    else
      false
    end
  end

  def new?
    Time.at(self.user.last_read) < self.time
  end

  def score
    self.time.to_f
  end

  def delete
    RedisInstance.get_instance.zremrangebyscore user.sortedset_key, score, score
  end
  private :score, :delete

  # ---- Modules ----
  module UserHelpers
    def has_notifications(&block)
      include Notification::UserHelpers::UserInstanceMethods

      before_destroy do 
         RedisInstance.get_instance.del sortedset_key
         RedisInstance.get_instance.del last_read_key
         RedisInstance.get_instance.del pending_last_read_key
      end

      Notification.user_proc = block if block_given?
    end

    module UserInstanceMethods

      def sortedset_key
        "user:#{self.id}:notifications"
      end

      def last_read
        @last_read ||= RedisInstance.get_instance.get(last_read_key).to_f
      end

      def last_read=(time)
        f_time = time.to_f
        @last_read = f_time if RedisInstance.get_instance.set last_read_key, f_time
      end

      def pending_last_read
        @pending_last_read ||= RedisInstance.get_instance.get(pending_last_read_key).to_f
      end

      def pending_last_read=(time)
        f_time = time.to_f
        @pending_last_read = f_time if RedisInstance.get_instance.set pending_last_read_key, f_time
      end

      def confirm_last_read
        self.last_read = pending_last_read
      end

      def count_notifications
        @count_notifications ||= RedisInstance.get_instance.zcount sortedset_key, '-inf', '+inf'  
      end

      def count_new_notifications
        @count_new_notifications ||= RedisInstance.get_instance.zcount sortedset_key, last_read, '+inf'
      end

      def has_new_notifications?
        count_new_notifications > 0
      end
      #note: new notifications refers to notifications created after last visit
      # unread notifications (to be done) refers to notification not yet been read
      #but created before or after last visit (to do this, each notification should)
      #know whether it was read.

      def notifications(unread_only: false, clean: false, options: {})
        if clean
          yield RedisInstance.get_instance if block_given?
          clean_notifications(options) unless options.empty?
        end
        min = unread_only ? last_read : '-inf'
        ary = RedisInstance.get_instance.zrevrangebyscore sortedset_key, '+inf', min
        notifications = ary.each_with_object([]) do |serialized, notifications|
          notifications << Notification.deserialize(serialized)
        end
      end

      def flush_notifications
        RedisInstance.get_instance.zremrangebyrank(sortedset_key, 0, -1)
      end

      private
      def last_read_key
        "user:#{self.id}:last_read"
      end

      def pending_last_read_key
        "user:#{self.id}:pending_last_read"
      end

      def clean_notifications(options)
        case options.keys.first
        when :max_num
          count = RedisInstance.get_instance.zcount(sortedset_key, '-inf', '+inf')
          RedisInstance.get_instance.zremrangebyrank(sortedset_key, 0, count-1-options[:max_num]) if count > options[:max_num]
        when :max_time
          max = options[:max_time].to_f
          RedisInstance.get_instance.zremrangebyscore(sortedset_key, '-inf', "(#{max}")
        end
      end
    end # end of module
  end # end of module
end


# ----- Common Notifications Provided for your convenience ----- 
module Notification::Actor
  attr_accessor :actor_id
  attr_accessor :actor_name
  attr_accessor :actor_pic_url

  private
  def name(user)
    "#{user.firstname} #{user.lastname}"
  end
end

module Notification::Post
  attr_accessor :post_id
  attr_accessor :post_type #video, photo or status
  attr_accessor :post_thumbnail_url
  attr_accessor :post_user_id #creator of the post
  attr_accessor :post_user_name

  private
  def thumbnail_url(post)
    case post.class.to_s
    when 'Video' then post.thumbnail_url
    when 'Photo' then post.image.url
    else nil
    end
  end
end


class FollowerNotification < Notification
  include Notification::Actor

  def initialize(follower=nil, followed=nil)
    yield self if block_given?
    self.actor_id ||= follower.id
    self.actor_name ||= "#{follower.firstname} #{follower.lastname}"
    self.actor_pic_url ||= follower.photo.url
    super(followed) unless followed.nil?
  end
end


class LikeNotification < Notification
  include Notification::Post
  include Notification::Actor

  def initialize(liker=nil, post=nil)
    yield self if block_given?      
    self.post_id ||= post.id
    self.post_type ||= post.class.to_s
    self.post_thumbnail_url ||= thumbnail_url(post)
    self.post_user_id ||= post.user.id
    self.post_user_name ||= name(post.user)
    self.actor_id ||= liker.id
    self.actor_name ||= name(liker)
    self.actor_pic_url ||= liker.photo.url
    super(post.user) unless post.nil?
  end
end



class CommentNotification < Notification
  include Notification::Post
  include Notification::Actor
  attr_accessor :comment_id
  attr_accessor :comment_preview

  def initialize(comment=nil, post=nil, user=nil)
    yield self if block_given?      
    self.post_id ||= post.id
    self.post_type ||= post.class.to_s
    self.post_thumbnail_url ||= thumbnail_url(post)
    self.post_user_id ||= post.user.id
    self.post_user_name ||= name(post.user)
    self.comment_id ||= comment.id
    self.comment_preview ||= comment.comment.truncate(100)
    self.actor_id ||= comment.user.id
    self.actor_name ||= name(comment.user)
    self.actor_pic_url ||= comment.user.photo.url
    super(user || post.user) unless post.nil?
  end
end
