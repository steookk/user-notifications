require 'spec_helper'

feature "Notifications", :js => true do 
  background do
    @user = FactoryGirl.create :user
    login_as @user, :scope => :user
  end
  given!(:notifications_icon_highlighted) { 'a#notifications-icon span.label' }
  given!(:notifications_icon) { 'a#notifications-icon span.secondary.label' }
  given!(:unread_notification) { "div.notification-date span.underlined" }

  describe "Notifications flow: from icon in the header to page with all recent notifications" do
    context "user has notifications including some unread" do
      background do
        Notification.new(@user, Time.now.yesterday).save
        Notification.new(@user, 30.minutes.ago).save
        @user.last_read = 60.minutes.ago
      end

      scenario "user clicks on the highlighted notifications' icon in order to 
                go to notifications' page which has highlighted unread notifications and 
                then comes back to homepage where notifications' icon won't be highlighted anymore" do
        visit home_path
        expect(page).to have_selector(notifications_icon_highlighted)
        expect(page).to_not have_selector(notifications_icon)
        expect(page).to have_content '1' #one unread notification
        click_link 'notifications-icon'
        expect(page).to have_selector(unread_notification)
        visit home_path
        expect(page).to have_selector(notifications_icon)
      end
    end

    context "user has notifications but they have been all already read" do
      background do
        Notification.new(@user, Time.now.yesterday).save
        Notification.new(@user, 30.minutes.ago).save
        @user.last_read = Time.now
      end

      scenario "user clicks on the default notifications' icon in order to 
                go to notifications' page which does not have any highlighted unread notifications" do
        visit home_path
        expect(page).to have_selector(notifications_icon)
        click_link 'notifications-icon'
        expect(page).to_not have_selector(unread_notification)
      end
    end

    context "user does not have any notification at all" do
      scenario "user clicks on the default notifications' icon in order to 
                go to notifications' page which alerts about having no notifications" do
        visit home_path
        expect(page).to have_selector(notifications_icon)
        click_link 'notifications-icon'
        expect(page).to have_selector('div.alert-box')
      end
    end
  end


  describe "Notifications' policy" do
    context "there are more than 30 unread notifications" do
      background do 
        50.times do 
          Notification.new(@user).save
        end
      end

      scenario "notifications' icon shows '30+' new notifications, then user clicks on it and he sees the last 30 notifications" do
        visit home_path
        expect(page).to have_content '30+'
        click_link 'notifications-icon'
        page.assert_selector(unread_notification, count: 30)
      end
    end
  end
end


feature "FollowerNotification", js: true do 
  background do
    @stefano = FactoryGirl.create :user, firstname: "Stefano", lastname: 'Uli'
    @giovanni = FactoryGirl.create :user, firstname: 'Giovanni', lastname: 'Rossi'
    login_as @stefano, :scope => :user
    visit user_path @giovanni
    click_link 'Follow'
    logout :user
  end

  scenario "Followed sees a notification: Stefano is following you" do
    login_as @giovanni, scope: :user
    visit notifications_path
    expect(page).to have_content 'Stefano Uli ti sta seguendo.'
    click_link 'Stefano Uli'
    expect(page).to have_content 'Stefano Uli'
  end
end


feature "LikeNotification", js: true do 
  given(:liker) { FactoryGirl.create :user, firstname: "Stefano", lastname: 'Uli' }
  given(:owner) { FactoryGirl.create :user, firstname: "Giovanni", lastname: 'Rossi' }
  given(:status) { FactoryGirl.create :status, user: owner }
  given(:photo) { FactoryGirl.create :photo, user: owner }
  given(:video) { FactoryGirl.create :completed_video, user: owner }

  background do
    login_as liker, :scope => :user
    # -------
    pending 'status_path etc have a non working like button'
    # -------
    visit status_path status
    click_link '.like'
    visit photo_path photo
    click_link '.like'
    visit video_path video
    click_link '.like'
    logout :user
  end

  scenario "The posts' owner sees three like notifications (on a status, photo and video)" do
    login_as owner, scope: :user
    visit notifications_path
    page.assert_selector(unread_notification, count: 3)
    expect(page).to have_content 'A Stefano Uli piace il tuo status'
    expect(page).to have_content 'A Stefano Uli piace la tua photo'
    expect(page).to have_content 'A Stefano Uli piace il tuo video'
    click_link 'status'
    visit notifications_path
    click_link 'photo'
    visit notifications_path
    click_link 'video'
  end
end

feature "CommentNotification", js: true do 
  given(:commenter) { FactoryGirl.create :user, firstname: "Stefano", lastname: 'Uli' }
  given(:other_commenter) { FactoryGirl.create :user, firstname: "Marco", lastname: 'Bianchi' }
  given(:owner) { FactoryGirl.create :user, firstname: "Giovanni", lastname: 'Rossi' }
  given(:status) { FactoryGirl.create :status, user: owner }
  given(:photo) { FactoryGirl.create :photo, user: owner }
  given(:video) { FactoryGirl.create :completed_video, user: owner }

  background do
    login_as commenter, :scope => :user
    # -------
    pending 'status_path etc have a non working comment button'
    # -------
    visit status_path status 
    fill_in :comment, :with => "commento su uno status"
    click_button 'Invia'
    visit photo_path photo
    fill_in :comment, :with => "commento su una foto"
    click_button 'Invia'
    visit video_path video
    fill_in :comment, :with => "commento su un video"
    click_button 'Invia'
    logout :user
  end

  scenario "The posts' owner sees three comment notifications (on a status, photo and video)" do
    login_as owner, scope: :user
    visit notifications_path
    page.assert_selector(unread_notification, count: 3)
    expect(page).to have_content 'Stefano Uli ha commentato il tuo status'
    expect(page).to have_content 'Stefano Uli ha commentato la tua photo'
    expect(page).to have_content 'Stefano Uli ha commentato il tuo video'
    click_link 'status'
    visit notifications_path
    click_link 'photo'
    visit notifications_path
    click_link 'video'
  end

  scenario 'the post owner comments his own post and the previous commenter receives
            a notification' do
    pending 'todo'
  end

  scenario 'a new commenter comments on the post and both the previous commenter 
            and the post owner receive a notification' do
    pending 'todo'
  end
end
