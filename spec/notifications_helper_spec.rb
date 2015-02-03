require 'spec_helper'

describe NotificationsHelper do
  before :all do 
    CoolNotification = Class.new(Notification)
  end
  let(:notification) {CoolNotification.new}

  describe '#notification_icon' do 
    it 'returns the path to the notification type icon' do
      expect(helper.notification_icon(notification)).to eq "icons/notifications/cool_notification.png"
    end
  end

  describe '#notification_body' do
    it 'delegates to notification_body type specific method' do
      expect(helper).to receive(:cool_notification_body).and_return('ciao')
      expect(helper.notification_body(notification)).to eq 'ciao'
    end
  end

  describe "#form_for_notifications_last_read + #click_on_notifications_last_read" do 
    let(:user) { FactoryGirl.create :user }

    it "uses the right id:'notifications_last_read_form'" do 
      id = /notifications_last_read_form/
      expect(helper.form_for_notifications_last_read(user)).to match id
      expect(helper.click_on_notifications_last_read).to match id
    end
  end
end
