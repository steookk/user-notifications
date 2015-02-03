require 'spec_helper'

describe Notification do
  before :all do
    MyUser = Struct.new(:id) do
      extend Notification::UserHelpers
      def self.before_destroy(&block)
        class_variable_set(:@@callback, block)
      end
      has_notifications { |id| MyUser.new(id) }
      def destroy 
        block = self.class.class_variable_get(:@@callback)
        self.instance_eval(&block)
      end
    end
  end
  let(:myuser) { MyUser.new(1) }
  let(:time) { Time.now }
  let(:notification) { Notification.new(myuser, time) }

  describe ".new" do
    it "sets the owner of the notification" do
      expect(notification.user).to eq myuser
    end

    it "sets the time of the notification" do
      expect(notification.time).to eq Time.at(time.to_f)
    end

    it "sets a default time when it is not given" do
      expect(Notification.new(myuser).time).to_not be nil
    end

    it "yields the given block" do 
      expect(Notification.new {|n| n.time=time.to_f}.time).to eq Time.at time.to_f
    end

    context "when no arguments are given" do 
      subject { Notification.new }

      it 'only sets the time to time.now' do
        expect(subject.user_id).to be_nil
        expect(subject.time).to_not be_nil
      end
    end
  end

  describe "#time" do
    it "sets a Float and returns a Time object" do
      notification.time = Time.now.to_f
      expect(notification.time).to be_a Time
    end
  end

  describe "#user_id" do
    it "sets and returns an Integer" do
      notification.user_id = 1234
      expect(notification.user_id).to be 1234
    end
  end

  let(:myproc) { Proc.new { |id| MyUser.new(id) } }

  describe "#user" do
    it "returns a User object" do
      expect(notification.user).to be_a MyUser
    end

    context "when proc is not defined" do
      before do
        Notification.user_proc = nil
        begin
          #sets the default proc
          notification.user #User.find(1) throws exception
        rescue
        end
      end

      it "sets the dafault proc for finding a user" do
        expect(Notification.class_variable_get(:@@user_proc)).to_not be_nil
      end

      after do
        Notification.user_proc = myproc
      end
    end
  end

  describe ".user_proc=" do
    before do
      @rails_proc = Proc.new { |id| User.find id }
      Notification.user_proc = @rails_proc
    end

    it "sets the proc needed to return a user object (depending on the framework/db used)" do
      expect(Notification.class_variable_get(:@@user_proc)).to eq @rails_proc
    end

    after do
      Notification.user_proc = myproc
    end
  end

  describe '#save (in Redis)' do
    subject { notification.save }

    it "saves the notification (in a sorted set)" do
      expect(subject).to be_true
    end

    it 'saves with a score equivalent to the epoch time (with fractions) of the notification' do
      subject
      expect(RedisInstance.get_instance.zrange("user:#{myuser.id}:notifications", 0, -1, with_scores: true)[0][1]).
             to eq notification.time.to_f
    end
  end

  describe ".create" do 
    it "makes a new notification and saves it" do
      Notification.create(myuser, Time.now)
      expect(RedisInstance.get_instance.zrange("user:#{myuser.id}:notifications", 0, -1).count).to be 1
    end
  end

  describe '.deserialize' do
    it "restores a notification equivalent to the one previously stored" do
      expect(Notification.deserialize(notification.to_json)).to eq(notification)
    end

    context "when type was defined" do
      before do
        SubNotification = Class.new(Notification)
        @sub_notification = SubNotification.new
      end

      it "restores a notification of the same type of the one previously stored" do
        expect(Notification.deserialize(@sub_notification.to_json)).to be_a SubNotification
      end
    end
  end

  describe "#==" do
    context "when two objects have the same instance variables with the same values" do
      let(:notification2) { Notification.new(myuser, time) }

      it "is true" do
        expect(notification == notification2).to be true
      end
    end

    context "when two objects have different instance variables" do
      let(:notification2) { Notification.new(myuser, time) }
      before do
        notification2.instance_variable_set :@test, 'this is a spec'
      end

      it "is false" do
        expect(notification == notification2).to be false
      end
    end

    context "when two objects have the same instance variables but different values" do
      let(:notification2) { Notification.new(myuser, Time.now.yesterday) }

      it "is false" do
        expect(notification == notification2).to be false
      end
    end
  end

  describe "#new?" do
    context "user last read is after the notification time" do
      before do
        myuser.last_read = Time.now.tomorrow
      end

      it "returns false" do
        expect(notification.new?).to be_false
      end
    end

    context "user last visit is prior the notification time" do
      before do
        myuser.last_read = Time.now.yesterday
      end

      it "returns true" do
        expect(notification.new?).to be_true
      end
    end
  end


  describe Notification::UserHelpers do

    describe '#sortedset_key' do
      it "returns the key containing notifications for the user" do
        expect(myuser.sortedset_key).to eq("user:1:notifications")
      end
    end

    describe "last read methods" do
      describe "#last_read" do
        before :each do
          myuser.last_read = time
        end

        it "returns a Float representing the time (because it is used mainly internally so float is more convenient)" do
          expect(myuser.last_read).to eq(time.to_f)
        end

        it "restores the time from db since it was automatically saved" do
          myuser.instance_variable_set(:@last_read, nil)
          expect(myuser.last_read).to eq(time.to_f)
        end
      end

      describe "#last_read key (private method)" do
        it 'returns the key for user\'s last read variable' do
          expect(myuser.send(:last_read_key)).to eq("user:1:last_read")
        end
      end

      describe "#pending_last_read" do
        before :each do
          myuser.pending_last_read = time
        end

        it 'returns a Float representing time' do 
          expect(myuser.pending_last_read).to eq time.to_f
        end

        it "restores the time from db since it was automatically saved" do
          myuser.instance_variable_set(:@pending_last_read, nil)
          expect(myuser.pending_last_read).to eq(time.to_f)
        end
      end

      describe "#pending_last_read_key (private method)" do 
        it 'returns the key for user\'s pending last read variable' do
          expect(myuser.send(:pending_last_read_key)).to eq("user:1:pending_last_read")
        end
      end

      describe "#confirm_last_read" do 
        before do 
          myuser.pending_last_read = time 
        end

        it "sets last_read to the same value of pending_last_read" do
          expect {myuser.confirm_last_read}.to change {myuser.last_read}.to(time.to_f)
        end
      end
    end

    describe "new notifications methods" do
      before :each do
        Notification.new(myuser, Time.now.yesterday).save
        Notification.new(myuser, 30.minutes.ago).save
      end

      describe "#count_new_notifications" do
        context "all the notifications are unread" do
          before do
            myuser.last_read = 1.week.ago
          end

          it "returns 2" do
            expect(myuser.count_new_notifications).to be 2
          end
        end

        it "caches the first call" do 
          expect {Notification.create(myuser)}.to_not change {myuser.count_new_notifications}
        end

        context "some notifications are unread" do
          before do
            myuser.last_read = 60.minutes.ago
          end

          it "returns 1" do
            expect(myuser.count_new_notifications).to be 1
          end
        end

        context "no notification is unread" do
          before do
            myuser.last_read = Time.now
          end

          it "returns 0" do
            expect(myuser.count_new_notifications).to be 0
          end
        end
      end

      describe "has_new_notifications?" do
        context "there are new notifications" do
          before do
            myuser.last_read = 60.minutes.ago
          end

          it "is true" do
            expect(myuser.has_new_notifications?).to be_true
          end
        end
      end
    end

    describe "#count_notifications" do
      before do
        5.times {Notification.create(myuser)}
      end

      it "returns the count of all the saved notifications" do
        expect(myuser.count_notifications).to be 5
      end

      it "caches the first call" do 
        expect {Notification.create(myuser)}.to_not change {myuser.count_notifications}
      end
    end

    describe "#notifications (loads notifications from Redis)" do
      before :all do
        MyNotification = Class.new(Notification) #Notification simple subclass
      end
      before :each do
        Notification.new(myuser, Time.now.yesterday).save
        Notification.new(myuser, 30.minutes.ago).save
        MyNotification.new(myuser, Time.now).save
        myuser.last_read = 60.minutes.ago
      end

      it "returns a notifications array" do
        expect(myuser.notifications).to be_a Array
      end

      it "returns newest notifications first" do
        expect(myuser.notifications[0].time).to be >= myuser.notifications[1].time
      end

      it "returns notifications of the proper class (deserialize to the proper subclass)" do
        expect(myuser.notifications[0]).to be_a MyNotification
        expect(myuser.notifications[1]).to be_a Notification
      end

      context "when unread_only=true" do
        it "returns unread notifications only" do
          expect(myuser.notifications(unread_only: true).count).to be 2
        end
      end

      context "when unread_only=false (default)" do
        it "returns all notifications" do
          expect(myuser.notifications(unread_only: false).count).to be 3
          expect(myuser.notifications.count).to be 3 #this shows it's default
        end
      end

      context "when we want to only keep the last n notifications in db" do 
        before :each do
          35.times { Notification.new(myuser).save }
        end

        it "deletes notifications in excess and returns the last n notifications" do 
          expect(myuser.notifications(clean: true, options: {max_num: 30}).count).to be 30
          expect(myuser.notifications.count).to be 30 #following calls return 30 as well
        end
      end 

      context "when we want to only keep notifications more recent than the given date" do
        before :each do
          10.times { Notification.new(myuser, 1.week.ago).save }
          # note: 3 more notifications are created in the outer before :each
        end

        it "deletes notifications prior to the given date and returns the more recent ones" do 
          expect(myuser.notifications(clean: true, options: {max_time: 1.hour.ago}).count).to be 2
          expect(myuser.notifications.count).to be 2
        end
      end

      context "when we want to provide our own cleaning strategy" do 
        before :each do
          10.times { Notification.new(myuser, 1.week.ago).save }
        end

        it "deletes notifications based on the block passed to the method" do 
          expect(myuser.notifications(clean: true) {|redis_instance| redis_instance
                      .zremrangebyrank(myuser.sortedset_key, 0, -1)}.count).to be 0
          expect(myuser.notifications.count).to be 0
        end
      end
    end

    describe "#flush_notifications" do 
      before {3.times { Notification.create(myuser, 1.week.ago) }}

      it "deletes all user's notifications" do 
        expect {myuser.flush_notifications}.
            to change {RedisInstance.get_instance.zcount myuser.sortedset_key, '-inf', '+inf'}.
                from(3).to(0)
      end
    end

    describe ".before_destroy callback" do 
      before :each do 
        # let's create the three notifications data structures 
        Notification.new(myuser).save
        myuser.last_read = time
        myuser.pending_last_read = time
      end

      it "destroy Redis data structures when the user is destroyed" do 
        expect(RedisInstance.get_instance.exists("user:1:notifications")).to be true
        expect(RedisInstance.get_instance.exists("user:1:last_read")).to be true
        expect(RedisInstance.get_instance.exists("user:1:pending_last_read")).to be true
        myuser.destroy
        expect(RedisInstance.get_instance.exists("user:1:notifications")).to be false
        expect(RedisInstance.get_instance.exists("user:1:last_read")).to be false
        expect(RedisInstance.get_instance.exists("user:1:pending_last_read")).to be false
      end
    end
  end # end of Notification::UserHelpers specs
end # end of Notification specs


describe 'any subclass of Notification' do 
  before :all do
    LikerNotification = Class.new(Notification) do #Notification simple subclass
      attr_accessor :liker_id
      def initialize(liker=nil)
        yield self if block_given?
        self.liker_id ||= liker.id  #liker.try(:id) if it's acceptable for liker to be nil
      end
    end
  end

  it "must yield to an eventual block" do 
    expect(LikerNotification.new {|n| n.liker_id = '123'}.liker_id).to eq('123')
  end
end

# ------------
# all kinds of notification have an owner, and they must initialize it
shared_examples_for "notification has an user" do
  it "sets the owner of the notification" do 
    expect(notification.user.id).to eq(user.id)
  end
end

# Notification::Actor
shared_examples_for "notification has an actor" do |fullname|
  it "sets actor's data (name,picture,id) needed to show the notification" do 
    expect(notification.actor_id).to eq(actor.id)
    expect(notification.actor_name).to eq fullname
    expect(notification.actor_pic_url).to eq(actor.photo.url)
  end
end

# Notification::Post
shared_examples_for 'notification has a status' do
  it "sets post data needed to show the notification" do 
    expect(notification.post_id).to eq status.id
    expect(notification.post_type).to eq 'Status'
    expect(notification.post_thumbnail_url).to be_nil
    expect(notification.post_user_id).to be status.user.id
    expect(notification.post_user_name).to eq "#{status.user.firstname} #{status.user.lastname}"
  end
end

shared_examples_for 'notification has a photo' do
  it "sets post data needed to show the notification" do 
    expect(notification.post_id).to eq photo.id
    expect(notification.post_type).to eq 'Photo'
    expect(notification.post_thumbnail_url).to eq photo.image.url
    expect(notification.post_user_id).to be photo.user.id
    expect(notification.post_user_name).to eq "#{photo.user.firstname} #{photo.user.lastname}"
  end
end

shared_examples_for 'notification has a video' do
  it "sets post data needed to show the notification" do 
    expect(notification.post_id).to eq video.id
    expect(notification.post_type).to eq 'Video'
    expect(notification.post_thumbnail_url).to eq video.thumbnail_url
    expect(notification.post_user_id).to be video.user.id
    expect(notification.post_user_name).to eq "#{video.user.firstname} #{video.user.lastname}"
  end
end
# ------------


describe FollowerNotification do
  describe ".new" do
    let(:follower) {FactoryGirl.create :user, firstname: 'stefano', lastname: 'test'}
    let(:followed) {FactoryGirl.create(:user)}
    subject(:notification) {FollowerNotification.new(follower, followed)}

    it_behaves_like 'notification has an user' do 
      let(:user) { followed }
    end

    it_behaves_like 'notification has an actor', 'Stefano Test' do
      let(:actor) { follower }
    end
  end
end


describe LikeNotification do
  let(:liker) {FactoryGirl.create :user, firstname: 'stefano', lastname: 'test'}
  let(:post_owner) {FactoryGirl.create :user, firstname: 'claudio', lastname: 'test'}

  describe ".new" do
    let(:post) {FactoryGirl.create(:status)}  #can be any kind of post
    subject(:notification) { LikeNotification.new(liker, post) }

    it_behaves_like 'notification has an user' do
      let(:user) { post.user }
    end

    it_behaves_like 'notification has an actor', 'Stefano Test' do
      let(:actor) { liker }
    end

    context "post is a status" do 
      let(:post) {FactoryGirl.create(:status, user: post_owner)}
      
      it_behaves_like 'notification has a status' do
        let(:status) {post}
      end
    end

    context "post is a photo" do 
      let(:post) {FactoryGirl.create(:photo, user: post_owner)}

      it_behaves_like 'notification has a photo' do 
        let(:photo) {post}
      end
    end

    context "post is a video" do 
      let(:post) {FactoryGirl.create(:completed_video, user: post_owner)}
      
      it_behaves_like 'notification has a video' do 
        let(:video) {post}
      end
    end
  end
end


describe CommentNotification do
  let(:commenter) {FactoryGirl.create :user, firstname: 'stefano', lastname: 'test'}
  let(:post_owner) {FactoryGirl.create :user, firstname: 'claudio', lastname: 'test'}

  describe ".new" do
    let(:post) {FactoryGirl.create(:status)}  #can be any kind of post
    let(:comment) {post.comments.build(user: commenter, comment: "#{'a'*200}")}
    subject(:notification) { CommentNotification.new(comment, post) }

    it_behaves_like 'notification has an user' do
      let(:user) { post.user }
    end

    context "when we want to specify a notification user" do 
      let(:other_commenter) {FactoryGirl.create(:user)}
      subject(:notification) {CommentNotification.new(comment, post, other_commenter)}

      it_behaves_like 'notification has an user' do 
        let(:user) { other_commenter }
      end
    end

    it_behaves_like 'notification has an actor', 'Stefano Test' do
      let(:actor) { commenter }
    end

    it "sets the comment id" do 
      expect(notification.comment_id).to eq comment.id
    end

    it "sets the comment preview" do
      expect(notification.comment_preview.length).to be 100
    end

    context "post is a status" do 
      let(:post) {FactoryGirl.create(:status, user: post_owner)}
      
      it_behaves_like "notification has a status" do
        let(:status) {post}
      end
    end

    context "post is a photo" do
      let(:post) {FactoryGirl.create(:photo, user: post_owner)}

      it_behaves_like "notification has a photo" do
        let(:photo) {post}
      end     
    end

    context "post is a video" do 
      let(:post) {FactoryGirl.create(:completed_video, user: post_owner)}
      
      it_behaves_like "notification has a video" do
        let(:video) {post}
      end
    end
  end
end
