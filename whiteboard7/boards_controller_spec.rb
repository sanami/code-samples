require 'spec_helper'

describe BoardsController do
  let(:valid_session) { {} }

  before :each do
    request.env["HTTP_ACCEPT"] = 'application/json'
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  describe 'POST create' do
    let(:valid_params) { HashWithIndifferentAccess.new board: { board_name: 'board1' } }

    it 'user' do
      user = create :user
      sign_in user
      subject.current_user.should_not be_nil

      post :create, valid_params, valid_session
      ap session
      ap response.body
      response.status.should == 201

      board = assigns(:board)
      board.should be_persisted
      board.users.should include(user)
      board.board_owner.should == user

      json = JSON.parse(response.body)
      ap json
      json['id'].should == board.id
      json['board_name'].should == 'board1'
    end

    it 'with canvas_params' do
      valid_params[:board][:canvas_params] = {
        canvas_objects: "[{\"type\":\"path\"}]",
        canvas_options: { 'background_color' => '#123456' }
      }
      post :create, valid_params, valid_session
      response.status.should == 201

      board = assigns(:board)
      board.should be_persisted

      puts board.board_data
      pp board.read_options_file
      board.read_options_file['background_color'].should == '#123456'
      board.read_board_file.should == "[\n{\"object_id\":1,\"object\":{\"type\":\"path\"}}\n]"
    end

    it 'anon' do
      post :create, valid_params, valid_session
      response.status.should == 201

      board = assigns(:board)
      board.should be_persisted
      session[:board_ids].should == [ board.id ]
      session[:own_boards_ids].should == [ board.id ]
      board.users.should be_empty
    end

    it 'error' do
      params = { board: { board_access_cd: 123 } }

      post :create, params, valid_session
      ap response.body
      response.status.should == 422

      board = assigns(:board)
      board.should_not be_persisted
      session[:board_ids].should be_nil
      board.users.should be_empty
    end
  end

  describe 'DELETE destroy' do
    it 'user' do
      user = create :user
      sign_in user
      b1 = create :board, board_owner: user

      delete :destroy, id: b1.id
      response.status.should == 204

      Board.find_by_id(b1.id).should == nil
    end

    it 'anon' do
      b1 = create :board
      valid_session[:own_boards_ids] = [b1.id]
      params = { id: b1.id }

      delete :destroy, params, valid_session
      response.status.should == 204

      Board.find_by_id(b1.id).should == nil
    end

    it 'error' do
      b1 = create :board
      params = { id: b1.id }

      delete :destroy, params, valid_session
      response.status.should == 302

      user = create :user
      sign_in user

      delete :destroy, params
      response.status.should == 302

      Board.find_by_id(b1.id).should == b1
    end

  end

  describe 'POST remove_user' do
    it 'owner' do
      owner = create :user
      sign_in owner

      u1 = create :user
      u2 = create :user
      b1 = create :board, board_owner: owner
      b1.users << u1
      b1.users << u2
      b1.users.should include(u1, u2)

      params = { id: b1.id, user_id: u1.id }
      post :remove_user, params
      ap response.body
      response.status.should == 200

      b1.reload
      b1.users.should_not include u1
      u1.boards.should_not include b1
      b1.users.should include u2
    end

    it 'self' do
      u1 = create :user
      sign_in u1

      u2 = create :user
      b1 = create :board
      b1.users << u1
      b1.users << u2

      # other
      params = { id: b1.id, user_id: u2.id }
      post :remove_user, params
      ap response.body
      response.status.should == 422

      # self
      params = { id: b1.id, user_id: u1.id }
      post :remove_user, params
      ap response.body
      response.status.should == 200

      b1.reload
      b1.users.should_not include u1
      u1.boards.should_not include b1
    end

    it 'anon' do
      u1 = create :user
      b1 = create :board
      b1.users << u1

      valid_session[:own_boards_ids] = [b1.id]
      params = { id: b1.id, user_id: u1.id }
      post :remove_user, params, valid_session
      ap response.body
      response.status.should == 200

      b1.reload
      b1.users.should_not include u1
      u1.boards.should_not include b1
    end

    it 'error' do
      owner = create :user
      sign_in owner

      b1 = create :board, board_owner: owner

      params = { id: b1.id, user_id: owner.id }
      post :remove_user, params
      ap response.body
      response.status.should == 422

      b1.reload
      b1.board_owner.should == owner
      b1.users.should include owner

      params = { id: b1.id, user_id: 'asjd' }
      post :remove_user, params
      ap response.body
      response.status.should == 422
    end
  end
end

