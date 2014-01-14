class BoardsController < InheritedResources::Base
  load_and_authorize_resource except: [:create]

  respond_to :json
  respond_to :html, only: [:accept_invitation]

  def create
    authorize! :create, Board

    canvas_params = params[:board].delete :canvas_params
    @board = Board.new(params[:board])
    @board.canvas_params = canvas_params

    if current_user
      @board.board_owner = current_user
      @board.board_access = :private_board
    end

    if @board.save
      unless current_user
        User.anonymous_user_create_board(session, @board)
      end

      render :json => @board, :status => :created
    else
      render :json => { errors: @board.errors }, :status => :unprocessable_entity
    end
  end

  def update
    update!

    if @board.errors.empty? # updated
      WebsocketRails[@board.uid].trigger 'board:updated', board: params[:board]
    end
  end

  def destroy
    @board.board_owner = nil # to pass validate_user_remove
    destroy!

    if @board.destroyed?
      WebsocketRails[@board.uid].trigger 'board:destroyed'

      unless current_user
        User.anonymous_user_remove_board(session, @board)
      end
    end
  end

  # GET /board/:id/file
  def file
    expires_now
    if @board.board_file.exist?
      # Update access time
      @board.touch

      #send_file @board.board_file, type: 'text/plain', disposition: 'inline'
      send_data @board.board_data, type: 'application/json', disposition: 'inline'
    else
      send_data ''
    end
  end

  # POST /board/:id/invite?email=:email
  def invite
    BoardInvitation.create_invitation(resource, params[:email], current_user)

    render :json => {}, :status => :ok
  rescue => ex
    log_error(ex)

    render :json => { errors: ex.message }, :status => :unprocessable_entity
  end

  # POST /invite/:invitation_code?choice=:choice
  def accept_invitation
    if request.post?
      if params[:choice] == 'accept'
        board = BoardInvitation.accept_invitation(params[:invitation_code], current_user, session)

        WebsocketRails[board.uid].trigger 'board:member:added', user: UserNameSerializer.new(current_user).as_json

        redirect_to draw_path(anchor: board.uid)
        return
      elsif params[:choice] == 'reject'
        @board = BoardInvitation.reject_invitation(params[:invitation_code], current_user, session)
        redirect_to root_path, alert: "Invitation rejected"
        return
      else
        flash.now[:alert] = "Unknown action: #{params[:choice]}"
      end
    end

    @invitation = BoardInvitation.find_by_invitation_code(params[:invitation_code])
    unless @invitation.try :can_accept_invitation?
      raise "Invitation expired"
    end
  rescue => ex
    log_error(ex)

    @error_message = ex.message
    @invitation = nil
  end

  # POST /board/:id/add_user?user_id=:user_id
  def add_user
    user = User.find(params[:user_id])
    unless current_user == user || current_user == @board.board_owner
      raise "Can't add other user"
    end

    if @board.users.include?(user)
      raise "User is a member"
    end

    @board.users << user

    WebsocketRails[@board.uid].trigger 'board:member:added', user: UserNameSerializer.new(user).as_json

    render :json => {}, :status => :ok
  rescue => ex
    log_error(ex)

    render :json => { errors: ex.message }, :status => :unprocessable_entity
  end

  # POST /board/:id/remove_user?user_id=:user_id
  def remove_user
    user = @board.users.find(params[:user_id])

    unless current_user == user || current_user == @board.board_owner
      raise "Can't remove other user"
    end

    @board.users.delete(user)

    WebsocketRails[@board.uid].trigger 'board:member:removed', user_id: user.id

    render :json => {}, :status => :ok
  rescue => ex
    log_error(ex)

    render :json => { errors: ex.message }, :status => :unprocessable_entity
  end

  # POST /board/:id/send_to_email
  def send_to_email
    @board.send_to_email(current_user, params)

    render :json => {}, :status => :ok
  rescue => ex
    log_error(ex)

    render :json => { errors: ex.message }, :status => :unprocessable_entity
  end
end
