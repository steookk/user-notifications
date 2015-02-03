require 'spec_helper'

describe NotificationsController do
  render_views
  
  describe "GET 'index'" do
    context "user is signed in" do 
      before :each do 
        @user = FactoryGirl.create :user
        sign_in @user
        40.times { Notification.new(@user, 1.week.ago).save }
        get :index
      end

      it "returns http success" do
        expect(response).to be_success
      end

      it "returns at most the latest 30 current_user's notifications" do 
        expect(assigns(:notifications).count).to be 30
      end

      it "returns notifications from the newest to the oldest" do 
        n = assigns(:notifications)
        expect(n[0].time >= n[1].time && n[1].time >= n[2].time).to be_true
      end

      it "updates user's 'pending last read' to now" do
        expect(Time.at @user.pending_last_read).to be_between (Time.now-5.seconds), Time.now 
      end
    end

    context "user is not signed in" do 
      it "redirects to home page" do
        get 'index'
        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
