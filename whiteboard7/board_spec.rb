require 'spec_helper'

describe Board do
  let(:user) { create :user }

  subject do
    create :board
  end

  it 'should create subject' do
    subject.should_not be_nil
    subject.uid.should_not be_blank
    ap subject
  end

  context 'users' do
    it '#validate_user_remove' do
      b1 = create :board, board_owner: user
      b1.users.should include(user)
      expect {
        b1.users.delete(user)
      }.to raise_error
      b1.users.should include(user)
    end
  end

  context 'scope' do
    it 'without_user' do
      b1 = create :board
      b2 = create :board
      b3 = create :board
      b3.users << create(:user)

      all = Board.without_user(user)
      ap all
      all.should include(b1, b2, b3)

      b1.users << user
      all = Board.without_user(user)
      all.should_not include(b1)
      all.should include(b2, b3)
    end
  end

  context 'validates' do
    it 'board_lock_status' do
      expect {
        create :board, board_owner: nil, board_lock_status: :lock
      }.to raise_error /can't be locked/
    end
  end

  it 'should have board_access enum' do
    subject.update_attributes board_access: :public_board
    subject.should be_public_board

    subject.update_attributes board_access: :private_board
    subject.should be_private_board
  end

  context 'files' do
    it 'folder should exist' do
      Board::BOARD_FOLDER.should be_exist
    end

    it 'should assign file to each board' do
      subject.board_file.to_s.should == "#{Board::BOARD_FOLDER}/#{subject.id}.#{subject.uid}.#{subject.board_mode}"
    end

  end

  it '#board_mode=' do
    Board::BOARD_MODES.each do |mode|
      b1 = build :board, board_mode: mode
      b1.board_mode.should == mode
    end

    expect { build :board, board_mode: 'ashjd' }.to raise_error
  end

  describe '.available_boards' do
    it 'without user' do
      b1 = create :board, board_access: :public_board
      b2 = create :board, board_access: :private_board
      Board.count.should == 2

      all = Board.available_boards
      all.should include b1
      all.should_not include b2
    end

    it 'for user' do
      b1 = create :board, board_access: :public_board
      b2 = create :board, board_access: :private_board
      b2.users << user
      b3 = create :board, board_access: :private_board
      Board.count.should == 3

      all = Board.available_boards(user)
      ap all
      all.count.should == 2
      all.should include(b1, b2)
      all.should_not include b3
    end
  end

  it '.expired_boards' do
    b1 = create :board, updated_at: 4.days.ago
    b2 = create :board, updated_at: 3.days.ago
    b3 = create :board, updated_at: 2.days.ago
    b4 = create :board, updated_at: 10.days.ago, board_owner: user

    all = Board.expired_boards(3)
    all.should include(b1, b2)
    all.should_not include(b3, b4)
  end

  describe '#can_process_channel_command?' do
    context 'locked board' do
      it 'user' do
        u1 = create :user
        u2 = create :user
        u3 = create :user
        b1 = create :board, board_owner: u1, board_lock_status: :lock
        b1.users << u2

        b1.can_process_channel_command?('object:create', u1).should == true
        b1.can_process_channel_command?('object:create', u2).should == true
        b1.can_process_channel_command?('object:create', u3).should == false
        b1.can_process_channel_command?('object:create', nil).should == false
      end
    end

    context 'unlocked board' do
      it 'user' do
        u1 = create :user
        u2 = create :user
        u3 = create :user
        b1 = create :board, board_owner: u1, board_lock_status: :unlock
        b1.users << u2

        b1.can_process_channel_command?('object:create', u1).should == true
        b1.can_process_channel_command?('object:create', u2).should == true
        b1.can_process_channel_command?('object:create', u3).should == true
        b1.can_process_channel_command?('object:create', nil).should == true
      end
    end

  end

  describe '#process_channel_event' do
    let(:ev1) {
      ev = double('Event')
      ev.stub_chain(:connection, :user)
      ev.stub_chain(:connection, :id)
      ev.stub(data: nil)
      ev
    }

    context 'object:create' do
      before(:each) { ev1.stub(name: :'object:create') }

      it 'good' do
        ev1.stub(data: { 'object' => '{"type":"path"}' })

        subject.process_channel_event(ev1).should == true
        ev1.data['object_id'].should == 1
        subject.read_board_file.should be_present
      end

      it 'bad' do
        ev1.stub(data: { 'object' => '{"type":"path"' })

        subject.process_channel_event(ev1).should == false
        ev1.data['object_id'].should == nil
        subject.read_board_file.should == nil
      end

      it 'empty' do
        ev1.stub(data: { 'object' => '' })
        subject.process_channel_event(ev1).should == false
        ev1.stub(data: { 'object' => nil })
        subject.process_channel_event(ev1).should == false
        ev1.stub(data: {})
        subject.process_channel_event(ev1).should == false
      end
    end

    context 'object:modified' do
      let!(:obj_id1) { subject.save_object('{"type":"path"}') }

      before(:each) { ev1.stub(name: :'object:modified') }

      it 'good' do
        ev1.stub(data: { 'object_id' => obj_id1.to_s, 'object' => '{"type":"text"}' })

        subject.process_channel_event(ev1).should == true
        ev1.data['object_id'].should == obj_id1
        subject.read_board_file.should == "[\n{\"object_id\":1,\"object\":{\"type\":\"text\"}}\n]"
      end

      it 'bad' do
        ev1.stub(data: { 'object_id' => obj_id1.to_s, 'object' => '{"type":"text"' })
        subject.process_channel_event(ev1).should == false
        ev1.stub(data: { 'object' => '{"type":"text"}' })
        subject.process_channel_event(ev1).should == false
        ev1.stub(data: { 'object_id' => '', 'object' => '{"type":"text"}' })
        subject.process_channel_event(ev1).should == false
        ev1.stub(data: { 'object_id' => obj_id1, 'object' => '' })
        subject.process_channel_event(ev1).should == false
        ev1.stub(data: { 'object_id' => obj_id1, 'object' => nil })
        subject.process_channel_event(ev1).should == false
      end

      it 'empty' do
        ev1.stub(data: {})
        subject.process_channel_event(ev1).should == false
      end
    end

    it 'board:clear' do
      subject.save_object('{"type":"path"}')
      subject.read_board_file.should be_present

      ev1.stub(name: :'board:clear')
      subject.process_channel_event(ev1).should == true

      subject.read_board_file.should == nil
    end

    context 'laser:move' do
      it 'good' do
        u1 = create :user, user_package: :pro
        subject.users << u1
        ev1.stub_chain(:connection, :user) { u1 }

        ev1.stub(name: :'laser:move')
        subject.process_channel_event(ev1).should == true
      end

      it 'bad' do
        ev1.stub(name: :'laser:move')
        subject.process_channel_event(ev1).should == false
      end
    end

    it 'block all other messages' do
      ev1.stub(name: :'board')
      subject.process_channel_event(ev1).should == false

      ev1.stub(name: '')
      subject.process_channel_event(ev1).should == false

      ev1.stub(name: nil)
      subject.process_channel_event(ev1).should == false
    end

  end

  it '#valid_options?' do
    subject.valid_options?({"background_color"=>"#ac7c7c"}).should == true
    subject.valid_options?({"background_color"=>"#AC7C7C"}).should == true
    subject.valid_options?({"background_color2"=>"#ac7c7c"}).should == false
    subject.valid_options?({"background_color"=>"#ac7c7cc"}).should == false
    subject.valid_options?({"background_color"=>"#ac7c7g"}).should == false
    subject.valid_options?({}).should == false
    subject.valid_options?(nil).should == false
  end

  it '#board_data' do
    pp subject.board_data
    puts subject.board_data
    subject.board_data.should == "{\n\"options\":{},\n\"objects\":[]\n}"

    subject.save_object('{"type":"path"}')
    subject.update_canvas_options({ 'k1'=>'v1' })

    pp subject.board_data
    puts subject.board_data
    subject.board_data.should == "{\n\"options\":{\"k1\":\"v1\"},\n\"objects\":[\n{\"object_id\":1,\"object\":{\"type\":\"path\"}}\n]\n}"
  end
end
